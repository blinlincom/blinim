import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/app_logger.dart';
import '../models/call_signal.dart';
import 'call_media_engine.dart';
import 'call_signaling_adapter.dart';

class CallSessionController {
  final CallMediaEngine media;
  final CallSignalingAdapter signaling;
  final String callId;
  final bool video;
  final bool incoming;
  final List<Map<String, dynamic>> initialSignals;
  final MediaStream? sharedLocalStream;
  final bool autoAccept;

  final _stateController = StreamController<CallFlowState>.broadcast();
  final CallStateMachine machine;
  StreamSubscription? _signalSub;
  Timer? _pullTimer;
  Map<String, dynamic>? _pendingRemoteOffer;
  bool _acceptRequested = false;
  bool _accepting = false;
  bool _started = false;
  bool _disposed = false;
  bool _readyToSendIce = false;
  final List<RTCIceCandidate> _pendingLocalIce = <RTCIceCandidate>[];

  CallSessionController({
    required this.media,
    required this.signaling,
    required this.callId,
    required this.video,
    required this.incoming,
    this.initialSignals = const <Map<String, dynamic>>[],
    this.sharedLocalStream,
    this.autoAccept = false,
  }) : machine = CallStateMachine(
         incoming ? CallFlowState.incomingRinging : CallFlowState.idle,
       );

  Stream<CallFlowState> get states => _stateController.stream;
  CallFlowState get state => machine.state;
  String get mediaType => video ? 'video' : 'audio';

  Future<void> start() async {
    if (_started) return;
    _started = true;
    AppLogger.call(
      'Session start call=$callId incoming=$incoming video=$video initial=${initialSignals.length}',
    );
    signaling.start();
    _signalSub = signaling.signals.listen((signal) {
      if (signal.callId == callId) unawaited(handleSignal(signal));
    });
    media.onIceCandidate = (candidate) => sendIce(candidate);
    media.onRemoteMediaReady = (_) {
      _markMediaConnected('remote_stream');
    };
    media.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markMediaConnected('ice_$state');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (!machine.ended) {
          machine.markFailed();
          _emitState();
          unawaited(
            signaling.send(
              callId: callId,
              action: 'hangup',
              media: mediaType,
              content: {'reason': 'ice_$state'},
            ),
          );
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (!machine.ended) {
          machine.markEnded();
          _emitState();
        }
      }
    };
    media.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markMediaConnected('peer_$state');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!machine.ended) {
          machine.markFailed();
          _emitState();
          unawaited(
            signaling.send(
              callId: callId,
              action: 'hangup',
              media: mediaType,
              content: {'reason': 'peer_$state'},
            ),
          );
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!machine.ended) {
          machine.markEnded();
          _emitState();
        }
      }
    };
    _emitState();
    for (final payload in initialSignals) {
      final signal = CallSignal.tryParse(payload);
      if (signal != null && signal.callId == callId) await handleSignal(signal);
    }
    unawaited(signaling.pull(callId: callId));
    _pullTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_disposed && !machine.ended)
        unawaited(signaling.pull(callId: callId));
    });

    if (!incoming) {
      if (sharedLocalStream != null) {
        await media.useLocalStream(sharedLocalStream!);
      }
      await startOutgoing();
    } else {
      if (sharedLocalStream != null) {
        await media.useLocalStream(sharedLocalStream!);
      } else {
        await media.initializeRenderers();
      }
      if (autoAccept) unawaited(accept());
    }
  }

  Future<void> startOutgoing() async {
    var inviteSent = false;
    try {
      await signaling.send(callId: callId, action: 'invite', media: mediaType);
      inviteSent = true;
      machine.markSent('invite');
      _emitState();
      await media.ensurePeerConnection(video: video);
      if (_disposed || machine.ended) return;
      final offer = await media.createOffer();
      if (_disposed || machine.ended) return;
      await signaling.send(
        callId: callId,
        action: 'offer',
        media: mediaType,
        content: {
          'description': {'sdp': offer.sdp, 'type': offer.type},
        },
      );
      _readyToSendIce = true;
      unawaited(_flushPendingLocalIce());
      machine.markSent('offer');
      _emitState();
    } catch (e, st) {
      AppLogger.error('CALL', 'Session 发起失败 call=$callId', error: e, stack: st);
      machine.markFailed();
      _emitState();
      try {
        await signaling.send(
          callId: callId,
          action: inviteSent ? 'cancel' : 'timeout',
          media: mediaType,
          content: {'reason': 'outgoing_start_failed', 'error': '$e'},
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> accept() async {
    if (_accepting || machine.ended) return;
    _acceptRequested = true;
    _accepting = true;
    try {
      final offer = await _waitForRemoteOffer();
      if (offer.isEmpty) {
        AppLogger.warn('CALL', 'Session 接听失败：等待offer超时 call=$callId');
        await signaling.send(
          callId: callId,
          action: 'timeout',
          media: mediaType,
          content: {'reason': 'offer_timeout'},
        );
        machine.markFailed();
        _emitState();
        return;
      }
      if (sharedLocalStream != null && media.localStream == null) {
        await media.useLocalStream(sharedLocalStream!);
      }
      await media.ensurePeerConnection(video: video);
      await media.setRemoteOffer(offer);
      await signaling.send(callId: callId, action: 'accept', media: mediaType);
      machine.markSent('accept');
      _emitState();
      final answer = await media.createAnswer();
      await signaling.send(
        callId: callId,
        action: 'answer',
        media: mediaType,
        content: {
          'description': {'sdp': answer.sdp, 'type': answer.type},
        },
      );
      _readyToSendIce = true;
      unawaited(_flushPendingLocalIce());
      machine.markSent('answer');
      _emitState();
    } catch (e, st) {
      AppLogger.error('CALL', 'Session 接听失败 call=$callId', error: e, stack: st);
      machine.markFailed();
      _emitState();
      try {
        await signaling.send(
          callId: callId,
          action: 'timeout',
          media: mediaType,
          content: {'reason': 'accept_failed', 'error': '$e'},
        );
      } catch (_) {}
      rethrow;
    } finally {
      _accepting = false;
    }
  }

  Future<void> reject() async {
    await signaling.send(callId: callId, action: 'reject', media: mediaType);
    machine.markSent('reject');
    _emitState();
    await closeMediaOnly();
  }

  Future<void> hangup() async {
    final action =
        incoming &&
            (state == CallFlowState.incomingRinging ||
                state == CallFlowState.offerReceived)
        ? 'reject'
        : 'hangup';
    await signaling.send(callId: callId, action: action, media: mediaType);
    machine.markSent(action);
    machine.markEnded();
    _emitState();
    await closeMediaOnly();
  }

  Future<void> handleSignal(CallSignal signal) async {
    if (_disposed || signal.fromUserId == signaling.selfId) return;
    final action = signal.action;
    final content = signal.content;
    AppLogger.call(
      'Session 收到信令 call=$callId action=$action from=${signal.fromUserId} state=${machine.state}',
    );
    if (action == 'ice' && !media.hasPeerConnection) {
      final candidate = _asMap(content['candidate']);
      if (candidate.isNotEmpty) await media.addRemoteCandidate(candidate);
      return;
    }
    if (action == 'offer') {
      final description = _descriptionFromContent(content);
      if (description.isNotEmpty) _pendingRemoteOffer = description;
      if (!machine.canReceive(action)) return;
      machine.markReceived(action);
      _emitState();
      if (_acceptRequested && !_accepting && description.isNotEmpty) {
        unawaited(accept());
      }
      return;
    }
    if (action == 'answer') {
      final description = _descriptionFromContent(content);
      if (description.isNotEmpty) await media.setRemoteAnswer(description);
      _readyToSendIce = true;
      unawaited(_flushPendingLocalIce());
      if (machine.canReceive(action)) machine.markReceived(action);
      _emitState();
      return;
    }
    if (!machine.canReceive(action)) return;
    switch (action) {
      case 'invite':
        machine.markReceived(action);
        _emitState();
        break;
      case 'accept':
        machine.markReceived(action);
        _emitState();
        break;
      case 'ice':
        final candidate = _asMap(content['candidate']);
        if (candidate.isNotEmpty) await media.addRemoteCandidate(candidate);
        break;
      case 'hangup':
      case 'cancel':
      case 'reject':
      case 'busy':
      case 'timeout':
        machine.markReceived(action);
        _emitState();
        await closeMediaOnly();
        break;
    }
  }

  Future<void> sendIce(RTCIceCandidate candidate) {
    if (!_readyToSendIce) {
      _pendingLocalIce.add(candidate);
      AppLogger.call(
        'Session 暂存本地ICE call=$callId pending=${_pendingLocalIce.length}',
      );
      return Future<void>.value();
    }
    return _sendIceNow(candidate);
  }

  Future<void> _sendIceNow(RTCIceCandidate candidate) {
    return signaling.send(
      callId: callId,
      action: 'ice',
      media: mediaType,
      content: {
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      },
    );
  }

  Future<void> _flushPendingLocalIce() async {
    if (!_readyToSendIce || _pendingLocalIce.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingLocalIce);
    _pendingLocalIce.clear();
    AppLogger.call('Session 发送暂存ICE call=$callId count=${pending.length}');
    for (final candidate in pending) {
      try {
        await _sendIceNow(candidate);
      } catch (e) {
        AppLogger.warn('CALL', 'Session 发送暂存ICE失败 call=$callId', data: e);
      }
    }
  }

  void _markMediaConnected(String reason) {
    if (_disposed ||
        machine.ended ||
        machine.state == CallFlowState.connected) {
      return;
    }
    AppLogger.call('Session 媒体已连接 call=$callId reason=$reason');
    machine.markConnected();
    _emitState();
  }

  void toggleMic() {
    media.toggleMic();
    _emitState();
  }

  void toggleCamera() {
    media.toggleCamera();
    _emitState();
  }

  Future<void> switchCamera() => media.switchCamera();

  Future<Map<String, dynamic>> _waitForRemoteOffer() async {
    var offer = _pendingRemoteOffer;
    if (offer != null && offer.isNotEmpty) return offer;

    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      final pulled = await signaling.pull(callId: callId);
      for (final signal in pulled) {
        if (signal.callId == callId &&
            signal.fromUserId != signaling.selfId &&
            signal.action == 'offer') {
          await handleSignal(signal);
        }
      }
      offer = _pendingRemoteOffer;
      if (offer != null && offer.isNotEmpty) return offer;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return <String, dynamic>{};
  }

  Map<String, dynamic> _descriptionFromContent(Map<String, dynamic> content) {
    final nested = _asMap(content['description']);
    if (nested.isNotEmpty) return nested;
    final sdp = '${content['sdp'] ?? ''}'.trim();
    final rawType = '${content['type'] ?? ''}'.trim().toLowerCase();
    final type = rawType.startsWith('call_') ? rawType.substring(5) : rawType;
    if (sdp.isNotEmpty && (type == 'offer' || type == 'answer')) {
      return {'sdp': sdp, 'type': type};
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  void _emitState() {
    if (!_stateController.isClosed) _stateController.add(machine.state);
  }

  Future<void> closeMediaOnly() => media.close();

  Future<void> dispose() async {
    _disposed = true;
    await _signalSub?.cancel();
    _pullTimer?.cancel();
    await media.dispose();
    await signaling.dispose();
    await _stateController.close();
  }
}
