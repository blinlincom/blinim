import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/app_config.dart';
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
  RTCPeerConnection? peer;
  MediaStream? localStream;
  StreamSubscription? callSub;
  bool accepted = false;
  bool muted = false;
  bool cameraOff = false;
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
      if (offer is Map)
        await peer?.setRemoteDescription(
          RTCSessionDescription('${offer['sdp']}', '${offer['type']}'),
        );
    } else {
      setState(() => status = '正在呼叫 ${widget.peerName}...');
      final offer = await peer!.createOffer();
      await peer!.setLocalDescription(offer);
      await sendSignal('invite', {
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
    final answer = await peer!.createAnswer();
    await peer!.setLocalDescription(answer);
    await sendSignal('answer', {
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    setState(() {
      accepted = true;
      status = '通话中';
    });
  }

  Future<void> handleSignal(Map<String, dynamic> payload) async {
    final content = payload['content'];
    if (content is! Map || '${content['call_id']}' != callId) return;
    final action = '${content['action']}';
    if (action == 'answer') {
      final sdp = content['sdp'];
      if (sdp is Map)
        await peer?.setRemoteDescription(
          RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'),
        );
      if (mounted) setState(() => status = '通话中');
    } else if (action == 'ice') {
      await peer?.addCandidate(
        RTCIceCandidate(
          '${content['candidate']}',
          '${content['sdpMid']}',
          int.tryParse('${content['sdpMLineIndex']}'),
        ),
      );
    } else if (action == 'hangup' || action == 'reject') {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> sendSignal(String action, Map<String, dynamic> extra) async {
    await widget.im.sendDirect(
      channelId: 'user_${widget.peerId}',
      payload: {
        'msg_type': 'call',
        'from_user_id': widget.session.id,
        'to_user_id': widget.peerId,
        'from_uid': 'user_${widget.session.id}',
        'to_uid': 'user_${widget.peerId}',
        'content': {
          'call_id': callId,
          'action': action,
          'media': widget.video ? 'video' : 'audio',
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

  Future<void> hangup({bool reject = false}) async {
    try {
      await sendSignal(reject ? 'reject' : 'hangup', const {});
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    callSub?.cancel();
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
                    remoteRenderer,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: RTCVideoView(
                  localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
