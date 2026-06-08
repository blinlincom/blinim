import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/app_config.dart';
import '../services/api_service.dart';
import '../models/user_session.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';

class CallScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final int peerId;
  final String peerName;
  final bool video;
  final bool incoming;
  final Map<String, dynamic>? initialSignal;

  const CallScreen({
    super.key,
    required this.session,
    required this.im,
    required this.peerId,
    required this.peerName,
    required this.video,
    this.incoming = false,
    this.initialSignal,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final api = const ApiService();
  RTCPeerConnection? peer;
  MediaStream? localStream;
  StreamSubscription? callSub;
  bool accepted = false;
  bool accepting = false;
  bool muted = false;
  bool cameraOff = false;
  bool usingFrontCamera = true;
  bool showLocalLarge = false;
  bool ending = false;
  bool callStarted = false;
  DateTime? connectedAt;
  Map<String, dynamic>? pendingOffer;
  final List<Map<String, dynamic>> pendingIce = [];
  String status = '正在准备通话...';
  late final String callId;

  @override
  void initState() {
    super.initState();
    callId =
        '${widget.initialSignal?['content']?['call_id'] ?? DateTime.now().millisecondsSinceEpoch}';
    unawaited(initCall());
  }

  Future<void> initCall() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    callSub = widget.im.calls.listen(handleSignal);
    await setupPeer();
    if (widget.incoming) {
      setState(
        () => status = '${widget.peerName} 邀请你${widget.video ? '视频' : '语音'}通话',
      );
      final offer = widget.initialSignal?['content']?['sdp'];
      if (offer is Map) pendingOffer = Map<String, dynamic>.from(offer);
    } else {
      setState(() => status = '正在呼叫 ${widget.peerName}...');
      final offer = await peer!.createOffer();
      await peer!.setLocalDescription(offer);
      await sendSignal('invite', {
        'type': 'call_invite',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      await sendSignal('offer', {
        'type': 'call_offer',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    }
  }

  Future<void> setupPeer() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = localStream;
    peer = await createPeerConnection({'iceServers': AppConfig.rtcIceServers});
    for (final track in localStream!.getTracks()) {
      await peer!.addTrack(track, localStream!);
    }
    peer!.onTrack = (event) {
      if (event.streams.isNotEmpty)
        remoteRenderer.srcObject = event.streams.first;
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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        markCallStarted();
      }
      if (!mounted) return;
      setState(
        () => status = switch (state) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected => '通话中',
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => '连接断开',
          RTCPeerConnectionState.RTCPeerConnectionStateFailed => '连接失败',
          RTCPeerConnectionState.RTCPeerConnectionStateClosed => '通话结束',
          _ => status,
        },
      );
    };
  }

  Future<void> acceptCall() async {
    if (accepting) return;
    setState(() {
      accepting = true;
      accepted = true;
      status = '正在接听...';
    });
    try {
      final offer = pendingOffer;
      if (offer == null) {
        setState(() {
          accepted = false;
          status = '等待对方视频信令...';
        });
        return;
      }
      await peer?.setRemoteDescription(
        RTCSessionDescription('${offer['sdp']}', '${offer['type']}'),
      );
      final answer = await peer!.createAnswer();
      await peer!.setLocalDescription(answer);
      unawaited(sendSignal('accept', {'type': 'call_accept'}));
      await sendSignal('answer', {
        'type': 'call_answer',
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      for (final ice in List<Map<String, dynamic>>.from(pendingIce)) {
        await handleSignal({
          'content': {'call_id': callId, 'action': 'ice', ...ice},
        });
      }
      pendingIce.clear();
      markCallStarted();
      if (mounted) setState(() => status = '通话中');
    } catch (e) {
      if (mounted) {
        setState(() {
          accepted = false;
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

  void markCallStarted() {
    if (callStarted) return;
    callStarted = true;
    connectedAt = DateTime.now();
  }

  Future<void> handleSignal(Map<String, dynamic> payload) async {
    final content = payload['content'];
    if (content is! Map || '${content['call_id']}' != callId) return;
    final action = normalizeAction(content);
    if (action == 'offer') {
      final sdp = content['sdp'];
      if (sdp is Map) pendingOffer = Map<String, dynamic>.from(sdp);
      return;
    }
    if (action == 'answer' || action == 'accept') {
      final sdp = content['sdp'];
      if (sdp is Map)
        await peer?.setRemoteDescription(
          RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'),
        );
      markCallStarted();
      if (mounted) setState(() => status = '通话中');
    } else if (action == 'ice') {
      final candidateText = '${content['candidate'] ?? ''}';
      if (candidateText.isEmpty || candidateText == 'null') return;
      if (widget.incoming && !accepted) {
        pendingIce.add(Map<String, dynamic>.from(content));
        return;
      }
      await peer?.addCandidate(
        RTCIceCandidate(
          '${content['candidate']}',
          '${content['sdpMid']}',
          int.tryParse('${content['sdpMLineIndex']}'),
        ),
      );
    } else if (action == 'hangup' || action == 'reject') {
      await closeCall(notifyPeer: false);
    }
  }

  String normalizeAction(Map content) {
    final raw = '${content['action'] ?? content['type'] ?? ''}';
    if (raw == 'call_invite') return 'invite';
    if (raw == 'call_offer') return 'offer';
    if (raw == 'call_accept') return 'accept';
    if (raw == 'call_answer') return 'answer';
    if (raw == 'call_ice') return 'ice';
    if (raw == 'call_hangup') return 'hangup';
    if (raw == 'call_reject') return 'reject';
    return raw;
  }

  Future<void> sendSignal(String action, Map<String, dynamic> extra) async {
    final signalType = switch (action) {
      'invite' => 'call_invite',
      'offer' => 'call_offer',
      'accept' => 'call_accept',
      'answer' => 'call_answer',
      'ice' => 'call_ice',
      'hangup' => 'call_hangup',
      'reject' => 'call_reject',
      _ => 'call_$action',
    };
    await widget.im.sendDirect(
      channelId: ImService.uidForUser(widget.peerId),
      payload: {
        'msg_type': 'call',
        'from_user_id': widget.session.id,
        'to_user_id': widget.peerId,
        'from_uid': ImService.uidForUser(widget.session.id),
        'to_uid': ImService.uidForUser(widget.peerId),
        'content': {
          'call_id': callId,
          'action': action,
          'type': signalType,
          'media': widget.video ? 'video' : 'audio',
          'nickname': widget.session.nickname ?? widget.session.username,
          'avatar': widget.session.avatar,
          ...extra,
        },
        'create_time': DateTime.now().toIso8601String(),
      },
    );
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
  }) async {
    if (ending) return;
    ending = true;
    if (mounted) setState(() => status = '通话结束');
    if (notifyPeer) {
      try {
        await sendSignal(
          reject ? 'reject' : 'hangup',
          const {},
        ).timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
    unawaited(_cleanupCall(notifyPeer: false, reject: reject));
    if (notifyPeer) unawaited(sendCallSummary(reject: reject));
  }

  Future<void> sendCallSummary({bool reject = false}) async {
    final duration = connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(connectedAt!);
    final seconds = duration.inSeconds;
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
        'status': reject
            ? 'rejected'
            : callStarted
            ? 'finished'
            : 'canceled',
      },
      'create_time': DateTime.now().toIso8601String(),
    };
    try {
      await widget.im
          .sendDirect(
            channelId: ImService.uidForUser(widget.peerId),
            payload: payload,
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
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
    if (minutes <= 0) return '${remain}秒';
    return '$minutes分${remain.toString().padLeft(2, '0')}秒';
  }

  Future<void> _cleanupCall({
    required bool notifyPeer,
    bool reject = false,
  }) async {
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
    callSub?.cancel();
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F172A),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.video
                ? RTCVideoView(
                    showLocalLarge ? localRenderer : remoteRenderer,
                    mirror: showLocalLarge && usingFrontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _audioBackdrop(),
          ),
          if (widget.video)
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
        onTap: () => hangup(reject: true),
      ),
      _RoundCallButton(
        icon: Icons.call_rounded,
        color: BlinStyle.green,
        onTap: acceptCall,
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
  final VoidCallback onTap;
  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 28),
    ),
  );
}
