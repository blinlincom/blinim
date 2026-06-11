import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../services/api_service.dart';
import '../models/user_session.dart';
import '../models/call_signal.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';

class CallRouteGuard {
  static const Duration _closedCallTtl = Duration(minutes: 10);
  static const Duration _outgoingCallTtl = Duration(minutes: 10);
  static String? _activeCallId;
  static final Map<String, DateTime> _closedCallIds = <String, DateTime>{};
  static final Map<String, DateTime> _outgoingCallIds = <String, DateTime>{};

  static bool get hasActiveCall => _activeCallId != null;

  static void _sweepClosedCalls() {
    final now = DateTime.now();
    _closedCallIds.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
    _outgoingCallIds.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  static bool isClosed(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return false;
    _sweepClosedCalls();
    return _closedCallIds.containsKey(id);
  }

  static bool isOutgoing(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return false;
    _sweepClosedCalls();
    return _outgoingCallIds.containsKey(id);
  }

  static void markOutgoing(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _sweepClosedCalls();
    _outgoingCallIds[id] = DateTime.now().add(_outgoingCallTtl);
  }

  static void markClosed(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _sweepClosedCalls();
    _closedCallIds[id] = DateTime.now().add(_closedCallTtl);
    if (_activeCallId == id) _activeCallId = null;
  }

  static bool tryEnter(String callId) {
    final id = callId.trim();
    if (id.isEmpty || isClosed(id)) return false;
    if (_activeCallId == null || _activeCallId == id) {
      _activeCallId = id;
      return true;
    }
    return false;
  }

  static void exit(String callId) {
    if (_activeCallId == callId) _activeCallId = null;
  }
}

class CallScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final int peerId;
  final String peerName;
  final bool video;
  final bool incoming;
  final Map<String, dynamic>? initialSignal;
  final List<Map<String, dynamic>> initialSignals;

  const CallScreen({
    super.key,
    required this.session,
    required this.im,
    required this.peerId,
    required this.peerName,
    required this.video,
    this.incoming = false,
    this.initialSignal,
    this.initialSignals = const <Map<String, dynamic>>[],
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const int _videoWidth = 640;
  static const int _videoHeight = 480;
  static const int _videoFrameRate = 24;
  static const int _videoStartBitrateKbps = 800;
  static const int _videoMinBitrateKbps = 300;
  static const int _videoMaxBitrateKbps = 1200;
  static const int _videoMaxBitrateBps = _videoMaxBitrateKbps * 1000;
  static const Duration _callSetupStartDelay = Duration(milliseconds: 120);
  static const Duration _outgoingAnswerTimeout = Duration(minutes: 2);

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final api = const ApiService();
  RTCPeerConnection? peer;
  MediaStream? localStream;
  StreamSubscription? callSub;
  Timer? backendSignalTimer;
  bool accepted = false;
  bool connectingMedia = false;
  bool accepting = false;
  bool muted = false;
  bool cameraOff = false;
  bool usingFrontCamera = true;
  bool showLocalLarge = false;
  bool renderersReady = false;
  bool ending = false;
  bool callStarted = false;
  bool pendingAcceptAfterOffer = false;
  bool remoteDescriptionSet = false;
  Timer? mediaConnectTimer;
  Timer? ringTimer;
  Timer? outgoingAnswerTimer;
  DateTime? connectedAt;
  Map<String, dynamic>? pendingOffer;
  final List<Map<String, dynamic>> pendingIce = [];
  final List<String> callLogs = [];
  final Map<String, Completer<void>> pendingAcks = {};
  final Set<String> apiFallbackSentActions = {};
  final Set<String> handledSignals = {};
  int signalSeq = 0;
  String status = '正在准备通话...';
  late final String callId;
  late final CallStateMachine callState;

  @override
  void initState() {
    super.initState();
    callId =
        '${CallSignal.tryParse(widget.initialSignal)?.callId ?? widget.initialSignal?['content']?['call_id'] ?? DateTime.now().millisecondsSinceEpoch}';
    callState = CallStateMachine(
      widget.incoming ? CallFlowState.incomingRinging : CallFlowState.idle,
    );
    CallRouteGuard.tryEnter(callId);
    if (!widget.incoming) CallRouteGuard.markOutgoing(callId);
    unawaited(initCall());
  }

  void addLog(String message) {
    final line = '${DateTime.now().toIso8601String()}  $message';
    callLogs.add(line);
    if (callLogs.length > 200) callLogs.removeAt(0);
    AppLogger.call(
      'callId=$callId peer=${widget.peerId} incoming=${widget.incoming} $message',
    );
  }

  void startRinging() {
    ringTimer?.cancel();
    Future<void> ringOnce() async {
      try {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.vibrate();
      } catch (_) {}
    }

    unawaited(ringOnce());
    ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || ending || callStarted || accepted) {
        stopRinging();
        return;
      }
      unawaited(ringOnce());
    });
  }

  void stopRinging() {
    ringTimer?.cancel();
    ringTimer = null;
  }

  void startOutgoingAnswerTimeout() {
    outgoingAnswerTimer?.cancel();
    if (widget.incoming) return;
    outgoingAnswerTimer = Timer(_outgoingAnswerTimeout, () {
      if (!mounted || ending || accepted || callStarted) return;
      addLog('呼叫超时未接听，自动取消');
      if (mounted) setState(() => status = '对方暂未接听');
      unawaited(closeCall(notifyPeer: true, cancel: true));
    });
  }

  void stopOutgoingAnswerTimeout() {
    outgoingAnswerTimer?.cancel();
    outgoingAnswerTimer = null;
  }

  void showLogs() {
    final text = callLogs.join('\n');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('通话日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text.isEmpty ? '暂无日志' : text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  Future<void> initCall() async {
    callSub = widget.im.calls.listen(handleSignal);
    if (widget.incoming) {
      startRinging();
      if (mounted) {
        setState(
          () =>
              status = '${widget.peerName} 邀请你${widget.video ? '视频' : '语音'}通话',
        );
      }
    } else {
      startRinging();
      startOutgoingAnswerTimeout();
      if (mounted) setState(() => status = '正在呼叫 ${widget.peerName}...');
    }
    await Future<void>.delayed(_callSetupStartDelay);
    if (!mounted || ending) return;
    if (widget.video) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      renderersReady = true;
      if (mounted) setState(() {});
    }
    await setupPeer();
    startBackendSignalPolling();
    if (widget.incoming) {
      final offer = widget.initialSignal?['content']?['sdp'];
      if (offer is Map) pendingOffer = Map<String, dynamic>.from(offer);
      for (final signal in widget.initialSignals) {
        await handleSignal(signal);
      }
    } else {
      final offer = _withPreferredVideoBitrate(await peer!.createOffer());
      await peer!.setLocalDescription(offer);
      await sendSignal('offer', {
        'type': 'call_offer',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    }
  }

  Future<void> setupPeer() async {
    addLog('开始获取媒体 audio=true video=${widget.video}');
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': _videoWidth},
              'height': {'ideal': _videoHeight},
              'frameRate': {'ideal': _videoFrameRate, 'max': _videoFrameRate},
            }
          : false,
    });
    if (widget.video) localRenderer.srcObject = localStream;
    addLog('媒体获取成功 tracks=${localStream?.getTracks().length ?? 0}');
    peer = await createPeerConnection({
      'iceServers': AppConfig.rtcIceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    for (final track in localStream!.getTracks()) {
      await peer!.addTrack(track, localStream!);
    }
    peer!.onTrack = (event) async {
      addLog('收到远端媒体 streams=${event.streams.length} kind=${event.track.kind}');
      if (widget.video) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        } else {
          final stream = await createLocalMediaStream('remote_$callId');
          stream.addTrack(event.track);
          remoteRenderer.srcObject = stream;
        }
      }
      if (mounted) setState(() {});
    };
    peer!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        unawaited(
          sendSignal('ice', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        );
      }
    };
    peer!.onConnectionState = (state) {
      addLog('PeerConnection状态 $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        markCallStarted();
        if (mounted) {
          setState(() {
            connectingMedia = false;
            status = '通话中';
          });
        }
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (mounted && !ending) {
          setState(
            () => status =
                state == RTCPeerConnectionState.RTCPeerConnectionStateFailed
                ? '连接失败'
                : '通话结束',
          );
        }
        unawaited(closeCall(notifyPeer: false));
        return;
      }
      if (!mounted) return;
      setState(
        () => status = switch (state) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
            '正在建立媒体连接...',
          _ => status,
        },
      );
    };
  }

  Future<void> acceptCall() async {
    if (accepting) return;
    stopRinging();
    setState(() {
      accepting = true;
      accepted = false;
      connectingMedia = false;
      status = '正在接听...';
    });
    try {
      final offer = pendingOffer;
      if (offer == null) {
        pendingAcceptAfterOffer = true;
        setState(() {
          accepted = false;
          accepting = true;
          connectingMedia = false;
          status = '等待对方视频信令...';
        });
        return;
      }
      await _completeAcceptWithOffer(offer);
    } catch (e) {
      if (mounted) {
        setState(() {
          accepted = false;
          connectingMedia = false;
          status = '接听失败，请重试';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('接听失败：$e')));
      }
    } finally {
      if (mounted) setState(() => accepting = false);
    }
  }

  Future<void> _completeAcceptWithOffer(Map<String, dynamic> offer) async {
    pendingAcceptAfterOffer = false;
    await peer?.setRemoteDescription(
      RTCSessionDescription('${offer['sdp']}', '${offer['type']}'),
    );
    remoteDescriptionSet = true;
    await flushPendingIce();
    final answer = _withPreferredVideoBitrate(await peer!.createAnswer());
    await peer!.setLocalDescription(answer);
    await sendSignal('answer', {
      'type': 'call_answer',
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    accepted = true;
    connectingMedia = !callStarted;
    callState.markSent('answer');
    startMediaConnectWatchdog();
    if (mounted) {
      setState(() {
        status = callStarted ? '通话中' : '正在建立媒体连接...';
      });
    }
  }

  RTCSessionDescription _withPreferredVideoBitrate(
    RTCSessionDescription description,
  ) {
    if (!widget.video || description.sdp == null || description.sdp!.isEmpty) {
      return description;
    }
    return RTCSessionDescription(
      _preferHighQualityVideoSdp(description.sdp!),
      description.type,
    );
  }

  String _preferHighQualityVideoSdp(String sdp) {
    final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(RegExp(r'\r?\n'));
    final out = <String>[];
    var inVideo = false;
    var videoBandwidthInserted = false;
    final videoPayloadTypes = <String>{};
    final fmtpPayloadTypes = <String>{};

    for (final line in lines) {
      if (line.startsWith('m=')) {
        inVideo = line.startsWith('m=video');
        videoBandwidthInserted = false;
        if (inVideo) {
          final parts = line.split(' ');
          if (parts.length > 3) videoPayloadTypes.addAll(parts.skip(3));
        }
      }

      if (inVideo && line.startsWith('a=fmtp:')) {
        final payload = line.substring(7).split(RegExp(r'\s+')).first;
        fmtpPayloadTypes.add(payload);
        out.add(
          '$line;x-google-start-bitrate=$_videoStartBitrateKbps'
          ';x-google-min-bitrate=$_videoMinBitrateKbps'
          ';x-google-max-bitrate=$_videoMaxBitrateKbps',
        );
        continue;
      }

      out.add(line);

      if (inVideo &&
          !videoBandwidthInserted &&
          (line.startsWith('c=') || line.startsWith('i='))) {
        out.add('b=AS:$_videoMaxBitrateKbps');
        out.add('b=TIAS:$_videoMaxBitrateBps');
        videoBandwidthInserted = true;
      }
    }

    final insertIndex = out.indexWhere((line) => line.startsWith('m=video'));
    if (insertIndex >= 0) {
      var i = insertIndex + 1;
      while (i < out.length && !out[i].startsWith('m=')) {
        if (out[i].startsWith('c=') || out[i].startsWith('b=')) {
          i++;
        }
        break;
      }
      if (!out
          .sublist(insertIndex, i)
          .any((line) => line.startsWith('b=AS:'))) {
        out.insert(i, 'b=AS:$_videoMaxBitrateKbps');
        out.insert(i + 1, 'b=TIAS:$_videoMaxBitrateBps');
      }
    }

    for (final payload in videoPayloadTypes.difference(fmtpPayloadTypes)) {
      final rtpmapIndex = out.indexWhere(
        (line) => line.startsWith('a=rtpmap:$payload '),
      );
      if (rtpmapIndex >= 0) {
        out.insert(
          rtpmapIndex + 1,
          'a=fmtp:$payload x-google-start-bitrate=$_videoStartBitrateKbps'
          ';x-google-min-bitrate=$_videoMinBitrateKbps'
          ';x-google-max-bitrate=$_videoMaxBitrateKbps',
        );
      }
    }

    return out.join(newline);
  }

  void markCallStarted() {
    stopRinging();
    stopOutgoingAnswerTimeout();
    mediaConnectTimer?.cancel();
    backendSignalTimer?.cancel();
    backendSignalTimer = null;
    connectingMedia = false;
    accepted = true;
    callStarted = true;
    callState.markConnected();
    connectedAt ??= DateTime.now();
  }

  void startMediaConnectWatchdog() {
    mediaConnectTimer?.cancel();
    mediaConnectTimer = Timer(const Duration(seconds: 18), () {
      if (!mounted || callStarted || ending) return;
      setState(() {
        connectingMedia = false;
        status = '媒体连接超时，请重拨';
      });
      addLog('媒体连接超时，未进入Connected');
    });
  }

  void startBackendSignalPolling() {
    backendSignalTimer?.cancel();
    var busy = false;
    var lastSeenId = 0;
    Future<void> pollOnce() async {
      if (!mounted || ending || busy) return;
      busy = true;
      try {
        final rows = await api
            .getImCallSignals(
              token: widget.session.token,
              sinceId: lastSeenId,
              callId: callId,
              peerId: widget.peerId,
              limit: 100,
            )
            .timeout(const Duration(seconds: 4));
        for (final row in rows) {
          final id = int.tryParse('${row['id'] ?? 0}') ?? 0;
          if (id > lastSeenId) lastSeenId = id;
          await handleSignal(row);
        }
      } catch (e) {
        addLog('后端信令补偿失败 $e');
      } finally {
        busy = false;
      }
    }

    unawaited(pollOnce());
    backendSignalTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (callStarted || ending) {
        backendSignalTimer?.cancel();
        backendSignalTimer = null;
        return;
      }
      unawaited(pollOnce());
    });
  }

  Future<void> flushPendingIce() async {
    if (!remoteDescriptionSet || pendingIce.isEmpty) return;
    final items = List<Map<String, dynamic>>.from(pendingIce);
    pendingIce.clear();
    for (final ice in items) {
      await addIceCandidateFromContent(ice);
    }
  }

  Future<void> addIceCandidateFromContent(Map content) async {
    final candidateText = '${content['candidate'] ?? ''}';
    if (candidateText.isEmpty || candidateText == 'null') return;
    final hasRemoteDescription = remoteDescriptionSet;
    if (!hasRemoteDescription) {
      pendingIce.add(Map<String, dynamic>.from(content));
      addLog('远端描述未设置，缓存ICE');
      return;
    }
    try {
      await peer?.addCandidate(
        RTCIceCandidate(
          '${content['candidate']}',
          '${content['sdpMid']}',
          int.tryParse('${content['sdpMLineIndex']}'),
        ),
      );
    } catch (e) {
      addLog('添加ICE失败 $e');
    }
  }

  Future<void> handleSignal(Map<String, dynamic> payload) async {
    final signal = CallSignal.tryParse(payload);
    if (signal == null || signal.callId != callId) return;
    if (signal.fromUserId == widget.session.id &&
        (signal.deviceId.isEmpty ||
            signal.deviceId == widget.im.currentDeviceId)) {
      return;
    }
    final action = signal.action;
    final content = signal.content;
    final signalId = signal.signalId;
    if (signalId.isNotEmpty && action != 'ack') {
      unawaited(sendSignal('ack', {'ack_signal_id': signalId}));
      if (!handledSignals.add(signalId)) {
        addLog('重复信令已ACK但跳过 $action $signalId');
        return;
      }
    }
    if (action == 'ack') {
      final ackId = '${content['ack_signal_id'] ?? ''}';
      pendingAcks.remove(ackId)?.complete();
      addLog('收到ACK $ackId');
      return;
    }
    if (!callState.canReceive(action)) {
      addLog(
        '非法状态信令已忽略 state=${callState.state.name} action=$action signal=$signalId',
      );
      return;
    }
    callState.markReceived(action);
    if (action == 'offer') {
      final sdp = content['sdp'];
      if (sdp is Map) {
        pendingOffer = Map<String, dynamic>.from(sdp);
        if (pendingAcceptAfterOffer) {
          try {
            await _completeAcceptWithOffer(pendingOffer!);
          } finally {
            if (mounted) setState(() => accepting = false);
          }
        }
      }
      return;
    }
    if (action == 'answer' || action == 'accept') {
      stopRinging();
      stopOutgoingAnswerTimeout();
      final sdp = content['sdp'];
      if (sdp is Map) {
        await peer?.setRemoteDescription(
          RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'),
        );
        remoteDescriptionSet = true;
        await flushPendingIce();
        if (mounted) {
          setState(() {
            accepted = true;
            connectingMedia = !callStarted;
            status = callStarted ? '通话中' : '正在建立媒体连接...';
          });
          if (!callStarted) startMediaConnectWatchdog();
        }
      } else if (mounted && !callStarted) {
        setState(() => status = '对方已接听，等待媒体连接...');
      }
    } else if (action == 'ice') {
      await addIceCandidateFromContent(content);
    } else if (action == 'hangup' ||
        action == 'reject' ||
        action == 'busy' ||
        action == 'cancel') {
      if (mounted) {
        setState(
          () => status = action == 'reject'
              ? '对方已拒绝'
              : action == 'busy'
              ? '对方正在通话中'
              : action == 'cancel'
              ? '对方已取消'
              : '对方已挂断',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await closeCall(notifyPeer: false);
    }
  }

  String normalizeAction(Map content) =>
      CallSignal.normalizeAction(content['action'] ?? content['type']);

  Future<void> sendSignal(String action, Map<String, dynamic> extra) async {
    action = CallSignal.normalizeAction(action);
    if (!callState.canSend(action)) {
      addLog('非法状态发送已阻止 state=${callState.state.name} action=$action');
      return;
    }
    final signalId = '${callId}_${++signalSeq}_$action';
    final fromDeviceId = widget.im.currentDeviceId ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final signal = CallSignal(
      callId: callId,
      signalId: signalId,
      action: action,
      media: widget.video ? 'video' : 'audio',
      fromUserId: widget.session.id,
      toUserId: widget.peerId,
      fromUid: ImService.uidForUser(widget.session.id),
      toUid: ImService.uidForUser(widget.peerId),
      deviceId: fromDeviceId,
      seq: signalSeq,
      timestamp: now,
      content: {
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
        ...extra,
      },
      raw: const {},
    );
    final payload = signal.toPayload();
    addLog('发送 $action $signalId');
    callState.markSent(action);
    await _sendSignalViaBackend(payload, action);
  }

  Future<void> _sendSignalViaBackend(
    Map<String, dynamic> payload,
    String action,
  ) async {
    try {
      final fallbackKey = '${payload['client_msg_no'] ?? '${callId}_$action'}';
      if (!apiFallbackSentActions.add(fallbackKey)) return;
      addLog('后端实时通道发送 $action');
      final apiPayload = Map<String, dynamic>.from(payload);
      final contentRaw = apiPayload['content'];
      if (contentRaw is Map) {
        apiPayload['content'] = {
          ...Map<String, dynamic>.from(contentRaw),
          'call_record_key': callId,
          'dedupe_key': 'call_$callId',
        };
      }
      await api
          .sendImCallSignal(
            token: widget.session.token,
            toUserId: widget.peerId,
            payload: apiPayload,
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      addLog('后端实时通道发送失败 $action $e');
    }
  }

  Future<void> enterPictureInPicture() async {
    if (!widget.video || ending) return;
    try {
      await const MethodChannel('blinlin.com/message_alerts')
          .invokeMethod('enterPictureInPicture');
    } catch (_) {}
  }

  Future<bool> _handleBackPressed() async {
    if (widget.video && !ending) {
      await enterPictureInPicture();
      return false;
    }
    return true;
  }

  void toggleMute() {
    muted = !muted;
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    setState(() {});
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !cameraOff;
    }
    setState(() {});
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      if (mounted) setState(() => usingFrontCamera = !usingFrontCamera);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前设备无法切换摄像头')));
      }
    }
  }

  Future<void> closeCall({
    required bool notifyPeer,
    bool reject = false,
    bool cancel = false,
  }) async {
    if (ending) return;
    stopRinging();
    stopOutgoingAnswerTimeout();
    backendSignalTimer?.cancel();
    backendSignalTimer = null;
    connectingMedia = false;
    if (mounted) setState(() => status = '通话结束');
    if (notifyPeer) {
      try {
        await sendSignal(
          reject
              ? 'reject'
              : cancel
              ? 'cancel'
              : 'hangup',
          const {},
        ).timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }
    CallRouteGuard.markClosed(callId);
    ending = true;
    callState.markEnded();
    if (mounted) Navigator.pop(context);
    unawaited(_cleanupCall(notifyPeer: false, reject: reject));
    if (notifyPeer) unawaited(sendCallSummary(reject: reject));
  }

  Future<void> sendCallSummary({bool reject = false}) async {
    final duration = connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(connectedAt!);
    final seconds = duration.inSeconds;
    final callerUserId = widget.incoming ? widget.peerId : widget.session.id;
    final calleeUserId = widget.incoming ? widget.session.id : widget.peerId;
    final status = reject
        ? 'rejected'
        : callStarted
        ? 'finished'
        : 'canceled';
    final text = reject
        ? '[${widget.video ? '视频' : '语音'}通话] 已拒绝'
        : callStarted
        ? '[${widget.video ? '视频' : '语音'}通话] ${formatDuration(seconds)}'
        : '[${widget.video ? '视频' : '语音'}通话] 已取消';
    final payload = {
      'msg_type': 'call_record',
      'from_user_id': widget.session.id,
      'to_user_id': widget.peerId,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': ImService.uidForUser(widget.peerId),
      'content': {
        'text': text,
        'media': widget.video ? 'video' : 'audio',
        'duration': seconds,
        'status': status,
        'caller_user_id': callerUserId,
        'callee_user_id': calleeUserId,
        'ended_by_user_id': widget.session.id,
        'direction': callerUserId == widget.session.id ? 'outgoing' : 'incoming',
      },
      'create_time': DateTime.now().toIso8601String(),
    };
    try {
      await api
          .sendMessage(
            token: widget.session.token,
            receiverId: widget.peerId,
            content: text,
            messageType: 0,
            payload: payload,
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remain = seconds % 60;
    if (minutes <= 0) return '$remain秒';
    return '$minutes分${remain.toString().padLeft(2, '0')}秒';
  }

  Future<void> _cleanupCall({
    required bool notifyPeer,
    bool reject = false,
  }) async {
    stopRinging();
    stopOutgoingAnswerTimeout();
    if (notifyPeer) {
      try {
        await sendSignal(
          reject ? 'reject' : 'hangup',
          const {},
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await localStream?.dispose();
    } catch (_) {}
    localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    try {
      await peer?.close();
    } catch (_) {}
    peer = null;
  }

  Future<void> hangup({bool reject = false}) async {
    await closeCall(notifyPeer: true, reject: reject);
  }

  @override
  void dispose() {
    CallRouteGuard.exit(callId);
    callSub?.cancel();
    backendSignalTimer?.cancel();
    mediaConnectTimer?.cancel();
    outgoingAnswerTimer?.cancel();
    ringTimer?.cancel();
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    localRenderer.dispose();
    remoteRenderer.dispose();
    localStream?.dispose();
    peer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: _handleBackPressed,
    child: Scaffold(
      backgroundColor: const Color(0xFF0F172A),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.video
                ? renderersReady
                    ? RTCVideoView(
                        showLocalLarge ? localRenderer : remoteRenderer,
                        mirror: showLocalLarge && usingFrontCamera,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : _videoPreparingBackdrop()
                : _audioBackdrop(),
          ),
          if (widget.video && renderersReady)
            Positioned(
              right: 18,
              top: 22,
              width: 110,
              height: 160,
              child: GestureDetector(
                onTap: () => setState(() => showLocalLarge = !showLocalLarge),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: RTCVideoView(
                    showLocalLarge ? remoteRenderer : localRenderer,
                    mirror: !showLocalLarge && usingFrontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 18,
            top: widget.video ? 190 : 34,
            child: FilledButton.icon(
              onPressed: showLogs,
              icon: const Icon(Icons.bug_report_rounded, size: 18),
              label: const Text('日志'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 34,
            child: widget.incoming && !accepted
                ? _incomingActions()
                : _callActions(),
          ),
        ],
      ),
    ),
    ),
  );

  Widget _videoPreparingBackdrop() => Container(
    color: const Color(0xFF0F172A),
    child: const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white70,
        ),
      ),
    ),
  );

  Widget _audioBackdrop() => Center(
    child: Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        gradient: BlinStyle.brandGradient,
        shape: BoxShape.circle,
        boxShadow: [BlinStyle.softShadow(.25)],
      ),
      child: const Icon(Icons.call_rounded, color: Colors.white, size: 56),
    ),
  );

  Widget _incomingActions() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundCallButton(
        icon: Icons.call_end_rounded,
        color: const Color(0xFFFF5A5F),
        onTap: accepting ? null : () => hangup(reject: true),
      ),
      _RoundCallButton(
        icon: Icons.call_rounded,
        color: BlinStyle.green,
        onTap: accepting ? null : acceptCall,
        loading: accepting,
      ),
    ],
  );

  Widget _callActions() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundCallButton(
        icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        color: Colors.white24,
        onTap: toggleMute,
      ),
      if (widget.video)
        _RoundCallButton(
          icon: cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          color: Colors.white24,
          onTap: toggleCamera,
        ),
      if (widget.video)
        _RoundCallButton(
          icon: usingFrontCamera
              ? Icons.camera_rear_rounded
              : Icons.camera_front_rounded,
          color: Colors.white24,
          onTap: switchCamera,
        ),
      _RoundCallButton(
        icon: Icons.call_end_rounded,
        color: const Color(0xFFFF5A5F),
        onTap: hangup,
      ),
    ],
  );
}

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;
  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: onTap == null ? color.withValues(alpha: .55) : color,
        shape: BoxShape.circle,
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              ),
            )
          : Icon(icon, color: Colors.white, size: 28),
    ),
  );
}
