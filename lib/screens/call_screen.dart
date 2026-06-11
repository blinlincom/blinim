import 'package:flutter/material.dart';
import '../models/call_signal.dart';
import '../models/user_session.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';

/// Guards call routes while the audio/video frontend is being rebuilt.
///
/// Backend call signal models and APIs are intentionally kept in the project,
/// but all WebRTC/media capture/rendering code has been removed from the
/// Flutter client. This guard only prevents duplicated placeholder routes and
/// keeps the old Home/Chat navigation sites compiling during the rebuild.
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

/// Placeholder screen after removing the old audio/video frontend.
///
/// Keep this widget until the new official flutter-webrtc integration is
/// designed and implemented from scratch. It intentionally does not request
/// camera/microphone permission, create a media connection, send SDP, add ICE,
/// or render a native video view.
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
  late final String callId;

  @override
  void initState() {
    super.initState();
    callId = _resolveCallId();
    if (callId.isNotEmpty) {
      CallRouteGuard.tryEnter(callId);
      if (!widget.incoming) CallRouteGuard.markOutgoing(callId);
    }
  }

  String _resolveCallId() {
    final parsed = CallSignal.tryParse(widget.initialSignal);
    final fromSignal = parsed?.callId ?? '';
    if (fromSignal.isNotEmpty) return fromSignal;
    final content = widget.initialSignal?['content'];
    if (content is Map && '${content['call_id'] ?? ''}'.isNotEmpty) {
      return '${content['call_id']}';
    }
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  @override
  void dispose() {
    if (callId.isNotEmpty) {
      CallRouteGuard.markClosed(callId);
      CallRouteGuard.exit(callId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.video ? '视频通话已移除' : '语音通话已移除';
    final subtitle = widget.incoming
        ? '${widget.peerName} 发起的${widget.video ? '视频' : '语音'}通话暂不可用'
        : '正在重构${widget.video ? '视频' : '语音'}通话功能，暂不能发起通话';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  widget.video
                      ? Icons.videocam_off_rounded
                      : Icons.phone_disabled_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  '旧音视频前端代码已经删除，后端信令接口保留。下一版会基于 flutter-webrtc 官方示例重新设计采集、信令、PeerConnection 和渲染链路。',
                  style: TextStyle(
                    color: Color(0xBFFFFFFF),
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BlinStyle.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text(
                    '返回',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
