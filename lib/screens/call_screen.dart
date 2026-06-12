import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../calls/call_media_engine.dart';
import '../calls/call_session.dart';
import '../calls/call_signaling_adapter.dart';
import '../models/call_signal.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
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

  static void _sweepCalls() {
    final now = DateTime.now();
    _closedCallIds.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
    _outgoingCallIds.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  static bool isClosed(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return false;
    _sweepCalls();
    return _closedCallIds.containsKey(id);
  }

  static bool isOutgoing(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return false;
    _sweepCalls();
    return _outgoingCallIds.containsKey(id);
  }

  static void markOutgoing(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _sweepCalls();
    _outgoingCallIds[id] = DateTime.now().add(_outgoingCallTtl);
  }

  static void markClosed(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _sweepCalls();
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
    if (_activeCallId == callId.trim()) _activeCallId = null;
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
  final api = const ApiService();
  late final String callId;
  CallMediaEngine? media;
  CallSessionController? call;
  StreamSubscription? stateSub;
  CallFlowState flowState = CallFlowState.idle;
  bool starting = true;
  String error = '';

  bool get canAccept => widget.incoming &&
      (flowState == CallFlowState.incomingRinging ||
          flowState == CallFlowState.offerReceived);

  @override
  void initState() {
    super.initState();
    callId = _resolveCallId();
    if (!CallRouteGuard.tryEnter(callId)) {
      error = '已有通话正在进行';
      starting = false;
      return;
    }
    if (!widget.incoming) CallRouteGuard.markOutgoing(callId);
    unawaited(_boot());
  }

  String _resolveCallId() {
    final parsed = CallSignal.tryParse(widget.initialSignal);
    final fromSignal = parsed?.callId ?? '';
    if (fromSignal.isNotEmpty) return fromSignal;
    final content = widget.initialSignal?['content'];
    if (content is Map && '${content['call_id'] ?? ''}'.isNotEmpty) return '${content['call_id']}';
    return 'call_${widget.session.id}_${widget.peerId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _boot() async {
    final engine = CallMediaEngine()
      ..onRemoteStream = (_) {
        if (mounted) setState(() {});
      }
      ..onLocalStreamChanged = () {
        if (mounted) setState(() {});
      };
    media = engine;
    final adapter = CallSignalingAdapter(
      api: api,
      im: widget.im,
      token: widget.session.token,
      selfId: widget.session.id,
      peerId: widget.peerId,
    );
    final controller = CallSessionController(
      media: engine,
      signaling: adapter,
      callId: callId,
      video: widget.video,
      incoming: widget.incoming,
      initialSignals: [
        if (widget.initialSignal != null) widget.initialSignal!,
        ...widget.initialSignals,
      ],
    );
    call = controller;
    stateSub = controller.states.listen((state) {
      if (mounted) setState(() => flowState = state);
      if (state == CallFlowState.ended || state == CallFlowState.rejected || state == CallFlowState.failed) {
        _autoPopSoon();
      }
    });
    try {
      engine.iceServers = await api.getIceServers(widget.session.token);
      await widget.im.ensureConnected().timeout(const Duration(seconds: 10));
      await controller.start();
    } catch (e) {
      error = '$e';
      flowState = CallFlowState.failed;
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  void _autoPopSoon() {
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  String _stateText() {
    if (error.isNotEmpty) return '通话失败：$error';
    switch (flowState) {
      case CallFlowState.idle:
        return starting ? '正在准备媒体...' : '准备中';
      case CallFlowState.outgoingCalling:
        return '正在呼叫 ${widget.peerName}';
      case CallFlowState.offerSent:
        return '等待对方接听';
      case CallFlowState.incomingRinging:
        return '${widget.peerName} 邀请你${widget.video ? '视频' : '语音'}通话';
      case CallFlowState.offerReceived:
        return '等待你接听';
      case CallFlowState.answerSent:
      case CallFlowState.connectingMedia:
        return '正在建立安全媒体连接';
      case CallFlowState.connected:
        return '通话中';
      case CallFlowState.ending:
        return '正在结束通话';
      case CallFlowState.ended:
        return '通话已结束';
      case CallFlowState.rejected:
        return '通话已拒绝/占线';
      case CallFlowState.failed:
        return '连接失败';
    }
  }

  Future<void> _hangup() async {
    try {
      await call?.hangup();
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _accept() async {
    setState(() {
      starting = true;
      error = '';
    });
    try {
      await call?.accept();
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _reject() async {
    try {
      await call?.reject();
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    stateSub?.cancel();
    if (callId.isNotEmpty) {
      CallRouteGuard.markClosed(callId);
      CallRouteGuard.exit(callId);
    }
    final controller = call;
    if (controller != null) {
      if (controller.machine.ended) {
        unawaited(controller.dispose());
      } else {
        unawaited(
          controller.hangup().catchError((_) {}).whenComplete(controller.dispose),
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = media;
    final remoteReady = engine?.remoteRenderer.srcObject != null;
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildRemote(engine, remoteReady)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: .75),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(top: 18, left: 18, right: 18, child: _buildHeader()),
            if (widget.video && engine != null)
              Positioned(
                right: 18,
                top: 108,
                width: 112,
                height: 154,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: RTCVideoView(
                      engine.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            Positioned(left: 18, right: 18, bottom: 24, child: _buildControls(engine)),
          ],
        ),
      ),
    );
  }

  Widget _buildRemote(CallMediaEngine? engine, bool remoteReady) {
    if (widget.video && remoteReady && engine != null) {
      return RTCVideoView(
        engine.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [Color(0xFF164E63), Color(0xFF0F172A), Color(0xFF020617)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white24,
              child: Text(
                widget.peerName.isNotEmpty ? widget.peerName.characters.first : '?',
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 18),
            Text(widget.peerName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_stateText(), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Row(
        children: [
          IconButton.filledTonal(
            onPressed: _hangup,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            color: Colors.white,
            style: IconButton.styleFrom(backgroundColor: Colors.white12),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.video ? '视频通话' : '语音通话', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                Text(_stateText(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );

  Widget _buildControls(CallMediaEngine? engine) {
    if (starting) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (canAccept) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundCallButton(icon: Icons.call_end_rounded, color: Colors.redAccent, label: '拒绝', onTap: _reject),
          _RoundCallButton(icon: Icons.call_rounded, color: BlinStyle.green, label: '接听', onTap: _accept),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundCallButton(icon: (engine?.micEnabled ?? true) ? Icons.mic_rounded : Icons.mic_off_rounded, color: Colors.white24, label: '麦克风', onTap: () => setState(() => call?.toggleMic())),
        if (widget.video) _RoundCallButton(icon: Icons.cameraswitch_rounded, color: Colors.white24, label: '翻转', onTap: () => unawaited(call?.switchCamera() ?? Future<void>.value())),
        if (widget.video) _RoundCallButton(icon: (engine?.cameraEnabled ?? true) ? Icons.videocam_rounded : Icons.videocam_off_rounded, color: Colors.white24, label: '摄像头', onTap: () => setState(() => call?.toggleCamera())),
        _RoundCallButton(icon: Icons.call_end_rounded, color: Colors.redAccent, label: '挂断', onTap: _hangup),
      ],
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RoundCallButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(32),
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      );
}
