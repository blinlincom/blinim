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
  static String get activeCallId => _activeCallId ?? '';

  static bool isActiveCall(String callId) {
    final id = callId.trim();
    return id.isNotEmpty && _activeCallId == id;
  }

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
  static const Duration _callSetupStartDelay = Duration(milliseconds: 120);
  static const Duration _outgoingAnswerTimeout = Duration(minutes: 2);
  static final Map<String, dynamic> _peerConstraints = {
    'mandatory': <String, dynamic>{},
    'optional': <Map<String, dynamic>>[
      {'DtlsSrtpKeyAgreement': false},
    ],
  };

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final api = const ApiService();
  RTCPeerConnection? peer;
  MediaStream? localStream;
  MediaStream? remoteStream;
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
  bool _remoteVideoTrackReceived = false;
  Timer? mediaConnectTimer;
  Timer? ringTimer;
  Timer? outgoingAnswerTimer;
  Timer? remoteRenderRetryTimer;
  int remoteRendererRevision = 0;
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
    final entered = CallRouteGuard.tryEnter(callId);
    if (!entered) {
      ending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
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

  Map<String, dynamic> get _offerAnswerConstraints => {
    'mandatory': <String, dynamic>{
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': widget.video,
    },
    'optional': <dynamic>[],
  };

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
      await _initRenderers();
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
      final offer = await peer!.createOffer(_offerAnswerConstraints);
      await peer!.setLocalDescription(offer);
      final localDescription = await peer!.getLocalDescription() ?? offer;
      await sendSignal('offer', {
        'type': 'call_offer',
        'sdp': {
          'type': localDescription.type,
          'sdp': localDescription.sdp,
        },
      });
    }
  }

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    renderersReady = true;
    if (mounted) setState(() {});
  }
  Future<void> _bindRemoteRenderer() async {
    if (!widget.video || remoteStream == null || ending) return;
    try {
      remoteRenderRetryTimer?.cancel();
      final stream = remoteStream!;
      if (remoteRenderer.srcObject != stream) {
        remoteRenderer.srcObject = stream;
        remoteRendererRevision++;
      }
      addLog(
        '远端视频渲染器已绑定 tracks=${stream.getTracks().length} '
        'video=${stream.getVideoTracks().length} '
        'renderVideoWidth=${remoteRenderer.videoWidth} '
        'renderVideoHeight=${remoteRenderer.videoHeight}',
      );
      if (mounted) setState(() {});
      _scheduleRemoteRenderProbe();
    } catch (e) {
      addLog('绑定远端渲染器失败 $e');
    }
  }

  void _scheduleRemoteRenderProbe([int attempt = 0]) {
    remoteRenderRetryTimer?.cancel();
    if (!widget.video || ending || remoteStream == null || attempt >= 12) return;
    remoteRenderRetryTimer = Timer(Duration(milliseconds: 350 + attempt * 250), () {
      if (!mounted || ending || remoteStream == null) return;
      final videoTracks = remoteStream!.getVideoTracks();
      final width = remoteRenderer.videoWidth;
      final height = remoteRenderer.videoHeight;
      addLog(
        '远端视频渲染检查 attempt=$attempt '
        'tracks=${remoteStream!.getTracks().length} '
        'video=${videoTracks.length} '
        'render=${width}x$height',
      );
      if (videoTracks.isEmpty) return;
      if (width == 0 || height == 0) {
        _scheduleRemoteRenderProbe(attempt + 1);
      }
    });
  }

  bool get _remoteVideoReadyForDebug =>
      widget.video && renderersReady && remoteRenderer.srcObject != null;


  String _trackState(MediaStreamTrack track) {
    Object enabled = 'unknown';
    Object muted = 'unknown';
    Object readyState = 'unknown';
    try {
      enabled = (track as dynamic).enabled;
    } catch (_) {}
    try {
      muted = (track as dynamic).muted;
    } catch (_) {}
    try {
      readyState = (track as dynamic).readyState;
    } catch (_) {}
    return 'id=${track.id} kind=${track.kind} enabled=$enabled muted=$muted readyState=$readyState';
  }

  void _logMediaTracks(String label, MediaStream? stream) {
    final tracks = stream?.getTracks() ?? <MediaStreamTrack>[];
    addLog('$label tracks=${tracks.length} video=${stream?.getVideoTracks().length ?? 0}');
    for (final track in tracks) {
      addLog('$label track ${_trackState(track)}');
    }
  }

  Future<void> setupPeer() async {
    addLog('开始获取媒体 audio=true video=${widget.video}');
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video
          ? {
              'mandatory': {
                'minWidth': '$_videoWidth',
                'minHeight': '$_videoHeight',
                'minFrameRate': '$_videoFrameRate',
              },
              'facingMode': 'user',
              'optional': <dynamic>[],
            }
          : false,
    });
    if (widget.video) {
      localRenderer.srcObject = localStream;
    }
    addLog('媒体获取成功 tracks=${localStream?.getTracks().length ?? 0}');
    _logMediaTracks('本地媒体', localStream);
    peer = await createPeerConnection({
      'iceServers': AppConfig.rtcIceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    }, _peerConstraints);
    for (final track in localStream!.getTracks()) {
      final sender = await peer!.addTrack(track, localStream!);
      addLog('已添加本地发送轨道 ${_trackState(track)} sender=$sender');
    }
    peer!.onTrack = (event) async {
      addLog('收到远端媒体 streams=${event.streams.length} kind=${event.track.kind} ${_trackState(event.track)}');
      if (event.streams.isEmpty) {
        addLog('远端媒体无原生stream，按官方接入跳过手动聚合 kind=${event.track.kind}');
        return;
      }
      final stream = event.streams[0];
      remoteStream = stream;
      addLog(
        '绑定官方远端媒体流 tracks=${stream.getTracks().length} '
        'video=${stream.getVideoTracks().length} kind=${event.track.kind}',
      );
      if (event.track.kind == 'video' && widget.video) {
        _remoteVideoTrackReceived = true;
        try {
          (event.track as dynamic).onEnded = () {
            addLog('远端视频轨道结束');
            remoteRenderer.srcObject = null;
            _remoteVideoTrackReceived = false;
            if (mounted) setState(() {});
          };
        } catch (_) {}
        await _bindRemoteRenderer();
      }
      if (mounted) setState(() {});
    };
    peer!.onSignalingState = (state) {
      addLog('Signaling状态 $state');
    };
    peer!.onIceGatheringState = (state) {
      addLog('ICE采集状态 $state');
    };
    peer!.onIceConnectionState = (state) {
      addLog('ICE连接状态 $state');
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
    final answer = await peer!.createAnswer(_offerAnswerConstraints);
    await peer!.setLocalDescription(answer);
    final localDescription = await peer!.getLocalDescription() ?? answer;
    await sendSignal('answer', {
      'type': 'call_answer',
      'sdp': {
        'type': localDescription.type,
        'sdp': localDescription.sdp,
      },
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
    if (signalId.isNotEmpty && !handledSignals.add(signalId)) {
      addLog('重复信令已跳过 $action $signalId');
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
      await closeCall(
        notifyPeer: false,
        reject: action == 'reject' || action == 'busy',
        recordCall: !widget.incoming,
      );
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
    bool recordCall = false,
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
        final shouldCancel = cancel || (!callStarted && !accepted);
        await sendSignal(
          reject
              ? 'reject'
              : shouldCancel
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
    if (!widget.incoming && (notifyPeer || recordCall)) {
      unawaited(sendCallSummary(reject: reject));
    }
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
    remoteRenderRetryTimer?.cancel();
    if (notifyPeer) {
      try {
        await sendSignal(
          reject ? 'reject' : 'hangup',
          const {},
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    for (final track in remoteStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await localStream?.dispose();
    } catch (_) {}
    try {
      await remoteStream?.dispose();
    } catch (_) {}
    remoteStream = null;
    localStream = null;
    _remoteVideoTrackReceived = false;
    try {
      await peer?.close();
    } catch (_) {}
    peer = null;
    remoteRenderRetryTimer?.cancel();
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
    remoteRenderRetryTimer?.cancel();
    ringTimer?.cancel();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    for (final track in remoteStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    localStream?.dispose();
    remoteStream?.dispose();
    localStream = null;
    remoteStream = null;
    _remoteVideoTrackReceived = false;
    peer?.close();
    peer = null;
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: _handleBackPressed,
    child: Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.video
                ? renderersReady
                    ? _mainVideoLayer()
                    : _videoPreparingBackdrop()
                : _audioBackdrop(),
          ),
          SafeArea(
            child: Stack(
              children: [
                if (widget.video && renderersReady)
                  Positioned(
                    right: 18,
                    top: 22,
                    width: 110,
                    height: 160,
                    child: GestureDetector(
                      onTap: () => setState(() => showLocalLarge = !showLocalLarge),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .86),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BlinStyle.softShadow(.22)],
                        ),
                        child: _floatingVideoLayer(),
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
        ],
      ),
    ),
  );

  Widget _mainVideoLayer() {
    final renderer = showLocalLarge ? localRenderer : remoteRenderer;
    final isRemoteLarge = !showLocalLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: RTCVideoView(
                renderer,
                key: ValueKey(
                  isRemoteLarge
                      ? 'remote-main-view-$remoteRendererRevision'
                      : 'local-main-view',
                ),
                mirror: showLocalLarge,
                objectFit: isRemoteLarge
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _floatingVideoLayer() {
    final renderer = showLocalLarge ? remoteRenderer : localRenderer;
    final isRemoteSmall = showLocalLarge;
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: RTCVideoView(
            renderer,
            key: ValueKey(
              isRemoteSmall
                  ? 'remote-floating-view-$remoteRendererRevision'
                  : 'local-floating-view',
            ),
            mirror: !showLocalLarge,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }

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

  Widget _remoteVideoWaitingOverlayDeprecated() => const SizedBox.shrink();

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
        color: onTap == null ? color.withValues(alpha: .45) : color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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
