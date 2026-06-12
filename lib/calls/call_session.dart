import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

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

  final _stateController = StreamController<CallFlowState>.broadcast();
  final CallStateMachine machine;
  StreamSubscription? _signalSub;
  Timer? _pullTimer;
  Map<String, dynamic>? _pendingRemoteOffer;
  bool _acceptRequested = false;
  bool _accepting = false;
  bool _started = false;
  bool _disposed = false;

  CallSessionController({
    required this.media,
    required this.signaling,
    required this.callId,
    required this.video,
    required this.incoming,
    this.initialSignals = const <Map<String, dynamic>>[],
  }) : machine = CallStateMachine(incoming ? CallFlowState.incomingRinging : CallFlowState.idle);

  Stream<CallFlowState> get states => _stateController.stream;
  CallFlowState get state => machine.state;
  String get mediaType => video ? 'video' : 'audio';

  Future<void> start() async {
    if (_started) return;
    _started = true;
    signaling.start();
    _signalSub = signaling.signals.listen((signal) {
      if (signal.callId == callId) unawaited(handleSignal(signal));
    });
    media.onIceCandidate = (candidate) => sendIce(candidate);
    media.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        machine.markConnected();
        _emitState();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (!machine.ended) {
          machine.markFailed();
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
      if (!_disposed && !machine.ended) unawaited(signaling.pull(callId: callId));
    });

    if (!incoming) {
      await startOutgoing();
    } else {
      await media.initializeRenderers();
    }
  }

  Future<void> startOutgoing() async {
    await media.ensurePeerConnection(video: video);
    await signaling.send(callId: callId, action: 'invite', media: mediaType);
    machine.markSent('invite');
    _emitState();
    final offer = await media.createOffer();
    await signaling.send(
      callId: callId,
      action: 'offer',
      media: mediaType,
      content: {
        'description': {'sdp': offer.sdp, 'type': offer.type},
      },
    );
    machine.markSent('offer');
    _emitState();
  }

  Future<void> accept() async {
    if (_accepting || machine.ended) return;
    _acceptRequested = true;
    _accepting = true;
    try {
      final offer = await _waitForRemoteOffer();
      if (offer.isEmpty) {
        _emitState();
        return;
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
      machine.markSent('answer');
      machine.markConnected();
      _emitState();
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
    final action = incoming &&
        (state == CallFlowState.incomingRinging || state == CallFlowState.offerReceived)
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
      if (machine.canReceive(action)) machine.markReceived(action);
      machine.markConnected();
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
