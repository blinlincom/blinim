import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../calls/call_media_engine.dart';
import '../calls/call_session.dart';
import '../calls/call_signaling_adapter.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
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
  final String peerAvatar;
  final bool video;
  final bool incoming;
  final bool autoAccept;
  final Map<String, dynamic>? initialSignal;
  final List<Map<String, dynamic>> initialSignals;

  const CallScreen({
    super.key,
    required this.session,
    required this.im,
    required this.peerId,
    required this.peerName,
    this.peerAvatar = '',
    required this.video,
    this.incoming = false,
    this.autoAccept = false,
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
  bool recordSent = false;
  DateTime? connectedAt;
  CallFlowState? terminalState;
  bool localPreviewAsMain = false;
  bool compactMode = false;
  Offset compactOffset = const Offset(16, 124);

  bool get canAccept =>
      widget.incoming &&
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
    if (content is Map && '${content['call_id'] ?? ''}'.isNotEmpty)
      return '${content['call_id']}';
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
      extraContent: {
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
      },
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
      if (state == CallFlowState.connected) {
        connectedAt ??= DateTime.now();
      }
      if (state == CallFlowState.ended ||
          state == CallFlowState.rejected ||
          state == CallFlowState.failed) {
        terminalState = state;
        unawaited(_sendCallRecordIfNeeded(state));
      }
      if (mounted) setState(() => flowState = state);
      if (state == CallFlowState.ended ||
          state == CallFlowState.rejected ||
          state == CallFlowState.failed) {
        _autoPopSoon();
      }
    });
    unawaited(_loadIceServers(engine));
    try {
      await widget.im.ensureConnected().timeout(const Duration(seconds: 10));
      await controller.start();
      if (widget.incoming && widget.autoAccept && !controller.machine.ended) {
        await controller.accept();
      }
    } catch (e) {
      AppLogger.error('CALL', 'CallScreen 启动失败 call=$callId', error: e);
      error = '$e';
      flowState = CallFlowState.failed;
      terminalState = CallFlowState.failed;
      unawaited(_sendCallRecordIfNeeded(CallFlowState.failed));
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _loadIceServers(CallMediaEngine engine) async {
    try {
      final servers = await api
          .getIceServers(widget.session.token)
          .timeout(const Duration(seconds: 3));
      if (servers.isNotEmpty) engine.iceServers = servers;
      AppLogger.call(
        'CallScreen ICE服务器 count=${engine.iceServers?.length ?? 0} call=$callId',
      );
    } catch (e) {
      engine.iceServers ??= AppConfig.rtcIceServers;
      AppLogger.warn(
        'CALL',
        'CallScreen ICE服务器获取超时，使用内置配置 call=$callId',
        data: e,
      );
    }
  }

  Future<void> _sendCallRecordIfNeeded(CallFlowState state) async {
    if (recordSent || widget.incoming) return;
    recordSent = true;
    final status = _recordStatus(state);
    final duration = status == 'finished' && connectedAt != null
        ? DateTime.now().difference(connectedAt!).inSeconds
        : 0;
    final now = DateTime.now();
    final payload = {
      'message_id': 0,
      'client_msg_no':
          'call_record_${callId}_${widget.session.id}_${now.microsecondsSinceEpoch}',
      'from_user_id': widget.session.id,
      'to_user_id': widget.peerId,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': ImService.uidForUser(widget.peerId),
      'msg_type': 'call_record',
      'content': {
        'call_id': callId,
        'call_record_key': 'call_record_$callId',
        'media': widget.video ? 'video' : 'audio',
        'status': status,
        'duration': duration,
        'caller_user_id': widget.session.id,
        'callee_user_id': widget.peerId,
      },
      'create_time': now.toIso8601String(),
    };
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: _recordFallbackText(status, duration),
        messageType: 0,
        payload: payload,
      );
      AppLogger.call(
        'CallScreen 已发送通话记录 call=$callId status=$status duration=$duration',
      );
    } catch (e) {
      AppLogger.warn(
        'CALL',
        'CallScreen 通话记录发送失败',
        data: {'call': callId, 'error': '$e'},
      );
    }
  }

  String _recordStatus(CallFlowState state) {
    if (connectedAt != null && state == CallFlowState.ended) return 'finished';
    if (state == CallFlowState.rejected) {
      final lastAction = call?.machine.lastAction ?? '';
      return lastAction == 'busy' ? 'busy' : 'rejected';
    }
    if (state == CallFlowState.failed) {
      final lastAction = call?.machine.lastAction ?? '';
      return lastAction == 'timeout' ? 'missed' : 'failed';
    }
    return 'canceled';
  }

  String _recordFallbackText(String status, int duration) {
    final media = widget.video ? '视频' : '语音';
    if (status == 'finished') return '[$media通话] ${_durationText(duration)}';
    if (status == 'busy') return '[$media通话] 对方忙线';
    if (status == 'missed') return '[$media通话] 未接听';
    if (status == 'rejected') return '[$media通话] 已拒绝';
    if (status == 'failed') return '[$media通话] 连接失败';
    return '[$media通话] 已取消';
  }

  String _durationText(int total) {
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
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

  String get _peerAvatar {
    final signal = CallSignal.tryParse(widget.initialSignal);
    final content = signal?.content ?? const <String, dynamic>{};
    final values = [
      widget.peerAvatar,
      '${content['avatar'] ?? ''}',
      '${content['from_avatar'] ?? ''}',
      '${content['user_avatar'] ?? ''}',
    ];
    for (final value in values) {
      final text = value.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
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
          controller
              .hangup()
              .catchError((_) {})
              .whenComplete(controller.dispose),
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = media;
    final remoteReady = engine?.remoteRenderer.srcObject != null;
    if (compactMode) {
      return Scaffold(
        backgroundColor: BlinStyle.darkBg,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        BlinStyle.darkBg,
                        BlinStyle.darkBg.withValues(alpha: .96),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: compactOffset.dx,
                top: compactOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final size = MediaQuery.sizeOf(context);
                    setState(() {
                      compactOffset = Offset(
                        (compactOffset.dx + details.delta.dx).clamp(
                          8,
                          size.width - 250,
                        ),
                        (compactOffset.dy + details.delta.dy).clamp(
                          MediaQuery.paddingOf(context).top + 8,
                          size.height - 360,
                        ),
                      );
                    });
                  },
                  child: SizedBox(
                    width: 230,
                    height: widget.video ? 320 : 240,
                    child: _buildMiniWindow(engine, remoteReady),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: BlinStyle.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildMainStage(engine, remoteReady)),
            Positioned(
              top: 18,
              left: BlinStyle.pagePadding,
              right: BlinStyle.pagePadding,
              child: _buildHeader(),
            ),
            if (widget.video && engine != null)
              Positioned(
                right: BlinStyle.pagePadding,
                top: 108,
                width: 112,
                height: 154,
                child: _buildPreviewTile(engine, remoteReady),
              ),
            Positioned(
              left: BlinStyle.pagePadding,
              right: BlinStyle.pagePadding,
              bottom: 24,
              child: _buildControls(engine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStage(CallMediaEngine? engine, bool remoteReady) {
    if (widget.video && engine != null) {
      final localReady = engine.localRenderer.srcObject != null;
      if (localPreviewAsMain && localReady) {
        return _buildVideoSurface(
          engine.localRenderer,
          mirror: true,
          fallbackAvatar: _peerAvatar,
          fallbackName: widget.session.nickname ?? widget.session.username,
          fallbackText: '我的画面',
        );
      }
      if (remoteReady) {
        return _buildVideoSurface(
          engine.remoteRenderer,
          mirror: false,
          fallbackAvatar: _peerAvatar,
          fallbackName: widget.peerName,
          fallbackText: _stateText(),
        );
      }
      if (localReady && localPreviewAsMain) {
        return _buildVideoSurface(
          engine.localRenderer,
          mirror: true,
          fallbackAvatar: widget.session.avatar,
          fallbackName: widget.session.nickname ?? widget.session.username,
          fallbackText: '我的画面',
        );
      }
    }
    return _buildAvatarStage(
      avatar: _peerAvatar,
      name: widget.peerName,
      subtitle: _stateText(),
    );
  }

  Widget _buildPreviewTile(CallMediaEngine engine, bool remoteReady) {
    final localReady = engine.localRenderer.srcObject != null;
    final showLocal = !localPreviewAsMain;
    final useRemote = showLocal ? remoteReady : localReady;
    return GestureDetector(
      onTap: () => setState(() => localPreviewAsMain = !localPreviewAsMain),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border.all(color: Colors.white12),
          ),
          child: useRemote
              ? RTCVideoView(
                  showLocal ? engine.remoteRenderer : engine.localRenderer,
                  mirror: !showLocal,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : _buildAvatarStage(
                  avatar: showLocal ? widget.peerAvatar : widget.session.avatar,
                  name: showLocal
                      ? widget.peerName
                      : (widget.session.nickname ?? widget.session.username),
                  subtitle: showLocal ? '点击切换我的画面' : '点击切换对方画面',
                ),
        ),
      ),
    );
  }

  Widget _buildMiniWindow(CallMediaEngine? engine, bool remoteReady) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 14)],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _buildMainStage(engine, remoteReady)),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filledTonal(
                onPressed: () => setState(() => compactMode = false),
                icon: const Icon(Icons.fullscreen_exit_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: IconButton.filledTonal(
                onPressed: () =>
                    setState(() => localPreviewAsMain = !localPreviewAsMain),
                icon: const Icon(Icons.swap_horiz_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStage({
    required String avatar,
    required String name,
    required String subtitle,
  }) {
    return ColoredBox(
      color: const Color(0xFF0B1220),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 96,
                height: 96,
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _avatarFallback(name),
                      )
                    : _avatarFallback(name),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) => Container(
    color: Colors.white24,
    child: Center(
      child: Text(
        name.isNotEmpty ? name.characters.first : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _buildVideoSurface(
    RTCVideoRenderer renderer, {
    required bool mirror,
    required String fallbackAvatar,
    required String fallbackName,
    required String fallbackText,
  }) {
    final hasStream = renderer.srcObject != null;
    if (!hasStream) {
      return _buildAvatarStage(
        avatar: fallbackAvatar,
        name: fallbackName,
        subtitle: fallbackText,
      );
    }
    return RTCVideoView(
      renderer,
      mirror: mirror,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildHeader() => Row(
    children: [
      _CallTopAction(icon: Icons.keyboard_arrow_down_rounded, onTap: _hangup),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.video ? '视频通话' : '语音通话',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _stateText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xBFFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      _CallTopAction(
        icon: compactMode
            ? Icons.fullscreen_exit_rounded
            : Icons.picture_in_picture_alt_outlined,
        onTap: () => setState(() => compactMode = !compactMode),
      ),
    ],
  );

  Widget _buildControls(CallMediaEngine? engine) {
    if (starting)
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    if (canAccept) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundCallButton(
            icon: Icons.call_end_rounded,
            color: Colors.redAccent,
            label: '拒绝',
            onTap: _reject,
          ),
          _RoundCallButton(
            icon: Icons.call_rounded,
            color: BlinStyle.success,
            label: '接听',
            onTap: _accept,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundCallButton(
          icon: (engine?.micEnabled ?? true)
              ? Icons.mic_rounded
              : Icons.mic_off_rounded,
          color: Colors.white24,
          label: '麦克风',
          onTap: () => setState(() => call?.toggleMic()),
        ),
        if (widget.video)
          _RoundCallButton(
            icon: Icons.cameraswitch_rounded,
            color: Colors.white24,
            label: '翻转',
            onTap: () =>
                unawaited(call?.switchCamera() ?? Future<void>.value()),
          ),
        if (widget.video)
          _RoundCallButton(
            icon: (engine?.cameraEnabled ?? true)
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            color: Colors.white24,
            label: '摄像头',
            onTap: () => setState(() => call?.toggleCamera()),
          ),
        _RoundCallButton(
          icon: Icons.call_end_rounded,
          color: Colors.redAccent,
          label: '挂断',
          onTap: _hangup,
        ),
      ],
    );
  }
}

class _CallTopAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CallTopAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    ),
  );
}

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ],
  );
}
