import 'dart:async';

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
import '../services/message_alert_service.dart';
import '../utils/media_url.dart';
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

Route<T> callScreenRoute<T>(CallScreen screen) => _CallOverlayRoute<T>(screen);

class _CallOverlayRoute<T> extends PopupRoute<T> {
  final CallScreen screen;

  _CallOverlayRoute(this.screen);

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => screen;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

class _CallScreenState extends State<CallScreen> {
  final api = const ApiService();
  final alerts = MessageAlertService();
  late final String callId;
  CallMediaEngine? media;
  CallSessionController? call;
  StreamSubscription? stateSub;
  CallFlowState flowState = CallFlowState.idle;
  bool starting = true;
  String error = '';
  bool recordSent = false;
  bool routePopAllowed = false;
  bool endingCall = false;
  DateTime? connectedAt;
  CallFlowState? terminalState;
  bool localPreviewAsMain = false;
  bool compactMode = false;
  Offset compactOffset = const Offset(16, 124);

  bool get _mainShowsLocal => widget.video && localPreviewAsMain;

  void _swapVideoFocus() {
    if (!widget.video) return;
    setState(() => localPreviewAsMain = !localPreviewAsMain);
  }

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
    unawaited(alerts.startKeepAlive());
    unawaited(_boot());
  }

  String _resolveCallId() {
    final parsed = CallSignal.tryParse(widget.initialSignal);
    final fromSignal = parsed?.callId ?? '';
    if (fromSignal.isNotEmpty) return fromSignal;
    final content = widget.initialSignal?['content'];
    if (content is Map && '${content['call_id'] ?? ''}'.isNotEmpty) {
      return '${content['call_id']}';
    }
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
    try {
      await _loadIceServers(engine);
      if (widget.im.isConnectedForUser(widget.session.id)) {
        await widget.im
            .waitForConnected(
              timeout: const Duration(seconds: 8),
              requireStable: true,
            )
            .timeout(const Duration(seconds: 9));
      } else {
        await widget.im.ensureConnected().timeout(const Duration(seconds: 6));
      }
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
      engine.iceServers ??= AppConfig.publicStunServers;
      AppLogger.warn(
        'CALL',
        'CallScreen ICE服务器获取失败，仅使用公开STUN call=$callId',
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
      if (mounted) {
        routePopAllowed = true;
        Navigator.of(context).pop();
      }
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
    if (endingCall) return;
    endingCall = true;
    terminalState ??= CallFlowState.ended;
    unawaited(_sendCallRecordIfNeeded(CallFlowState.ended));
    try {
      await call?.hangup();
    } catch (e) {
      AppLogger.warn('CALL', 'CallScreen 挂断信令发送失败', data: e);
      try {
        await media?.close();
      } catch (_) {}
    }
    routePopAllowed = true;
    if (mounted) Navigator.of(context).pop();
  }

  void _minimizeCall() {
    if (!mounted || compactMode) return;
    setState(() => compactMode = true);
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
      final text = resolveMediaUrl(value);
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  Future<void> _reject() async {
    endingCall = true;
    terminalState ??= CallFlowState.rejected;
    try {
      await call?.reject();
    } catch (e) {
      AppLogger.warn('CALL', 'CallScreen 拒绝信令发送失败', data: e);
      try {
        await media?.close();
      } catch (_) {}
    }
    routePopAllowed = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    stateSub?.cancel();
    if (routePopAllowed && callId.isNotEmpty) {
      CallRouteGuard.markClosed(callId);
      CallRouteGuard.exit(callId);
    }
    unawaited(alerts.stopKeepAlive());
    final controller = call;
    if (controller != null) {
      if (!routePopAllowed) {
        // 透明小窗路由被系统临时处置时不主动挂断，避免误结束通话。
      } else if (controller.machine.ended) {
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
    return PopScope(
      canPop: routePopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (compactMode) {
          _hangup();
        } else {
          _minimizeCall();
        }
      },
      child: compactMode
          ? SafeArea(
              child: Stack(
                children: [
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
                      child: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 230,
                          height: widget.video ? 320 : 240,
                          child: _buildMiniWindow(engine, remoteReady),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Scaffold(
              backgroundColor: BlinStyle.darkBg,
              body: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _swapVideoFocus,
                        child: _buildMainStage(engine, remoteReady),
                      ),
                    ),
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
            ),
    );
  }

  Widget _buildMainStage(CallMediaEngine? engine, bool remoteReady) {
    if (widget.video && engine != null) {
      final localReady = engine.localRenderer.srcObject != null;
      if (_mainShowsLocal) {
        return _buildVideoSurface(
          engine.localRenderer,
          mirror: true,
          fallbackAvatar: widget.session.avatar,
          fallbackName: widget.session.nickname ?? widget.session.username,
          fallbackText: '我的画面',
        );
      }
      return _buildVideoSurface(
        engine.remoteRenderer,
        mirror: false,
        fallbackAvatar: _peerAvatar,
        fallbackName: widget.peerName,
        fallbackText: remoteReady
            ? _stateText()
            : localReady
            ? '等待对方视频'
            : _stateText(),
      );
    }
    return _buildAvatarStage(
      avatar: _peerAvatar,
      name: widget.peerName,
      subtitle: _stateText(),
    );
  }

  Widget _buildPreviewTile(
    CallMediaEngine engine,
    bool remoteReady, {
    bool compact = false,
  }) {
    final localReady = engine.localRenderer.srcObject != null;
    final tileIsLocal = !_mainShowsLocal;
    final tileReady = tileIsLocal ? localReady : remoteReady;
    return GestureDetector(
      onTap: _swapVideoFocus,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border.all(color: Colors.white12),
          ),
          child: tileReady
              ? RTCVideoView(
                  tileIsLocal ? engine.localRenderer : engine.remoteRenderer,
                  mirror: tileIsLocal,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : _buildAvatarStage(
                  avatar: tileIsLocal ? widget.session.avatar : _peerAvatar,
                  name: tileIsLocal
                      ? (widget.session.nickname ?? widget.session.username)
                      : widget.peerName,
                  subtitle: tileIsLocal ? '我的画面' : '对方画面',
                  compact: compact,
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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _swapVideoFocus,
                child: _buildMainStage(engine, remoteReady),
              ),
            ),
            if (widget.video && engine != null)
              Positioned(
                right: 10,
                bottom: 78,
                width: 72,
                height: 96,
                child: _buildPreviewTile(engine, remoteReady, compact: true),
              ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filledTonal(
                onPressed: () => setState(() => compactMode = false),
                icon: const Icon(Icons.open_in_full_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: IconButton.filled(
                  onPressed: _hangup,
                  icon: const Icon(Icons.call_end_rounded),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    fixedSize: const Size(52, 52),
                  ),
                ),
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
    bool compact = false,
  }) {
    return ColoredBox(
      color: const Color(0xFF0B1220),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: compact ? 38 : 96,
                height: compact ? 38 : 96,
                child: avatar.isNotEmpty
                    ? Image.network(
                        resolveMediaUrl(avatar),
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (_, _, _) => _avatarFallback(name),
                      )
                    : _avatarFallback(name),
              ),
            ),
            if (!compact) ...[
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
      _CallTopAction(
        icon: Icons.keyboard_arrow_down_rounded,
        onTap: _minimizeCall,
      ),
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
            ? Icons.open_in_full_rounded
            : Icons.picture_in_picture_alt_outlined,
        onTap: compactMode
            ? () => setState(() => compactMode = false)
            : _minimizeCall,
      ),
    ],
  );

  Widget _buildControls(CallMediaEngine? engine) {
    if (starting) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (canAccept) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundCallButton(
            icon: Icons.call_end_rounded,
            color: Colors.redAccent,
            label: '拒绝',
            onTap: () => unawaited(_reject()),
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
          onTap: () => unawaited(_hangup()),
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
