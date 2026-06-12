import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/app_config.dart';

class CallMediaEngine {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCRtpSender> _senders = <RTCRtpSender>[];
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _renderersReady = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;

  Future<void> Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCIceConnectionState state)? onIceConnectionState;
  void Function(MediaStream stream)? onRemoteStream;
  VoidCallbackLike? onLocalStreamChanged;

  bool get hasPeerConnection => _pc != null;
  bool get micEnabled => _micEnabled;
  bool get cameraEnabled => _cameraEnabled;
  List<Map<String, dynamic>>? iceServers;
  final Map<String, dynamic> _lastRemoteDescriptions = <String, dynamic>{};

  Future<void> initializeRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> openLocalMedia({required bool video}) async {
    await initializeRenderers();
    _localStream ??= await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '24',
              },
              'facingMode': 'user',
              'optional': <dynamic>[],
            }
          : false,
    });
    localRenderer.srcObject = _localStream;
    onLocalStreamChanged?.call();
  }

  Future<void> ensurePeerConnection({
    required bool video,
    List<Map<String, dynamic>>? iceServers,
  }) async {
    if (_pc != null) return;
    await openLocalMedia(video: video);
    final config = <String, dynamic>{
      'iceServers': iceServers ?? this.iceServers ?? AppConfig.rtcIceServers,
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config, {
      'mandatory': <String, dynamic>{},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final handler = onIceCandidate;
      if (handler != null) unawaited(handler(candidate));
    };
    pc.onIceConnectionState = (state) => onIceConnectionState?.call(state);
    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_$hashCode');
        _remoteStream!.addTrack(event.track);
      }
      remoteRenderer.srcObject = _remoteStream;
      onRemoteStream?.call(_remoteStream!);
    };
    pc.onAddStream = (stream) {
      _remoteStream = stream;
      remoteRenderer.srcObject = stream;
      onRemoteStream?.call(stream);
    };

    for (final track in _localStream!.getTracks()) {
      _senders.add(await pc.addTrack(track, _localStream!));
    }
    _pc = pc;
    await _flushRemoteCandidatesIfReady();
  }

  Future<RTCSessionDescription> createOffer() async {
    final pc = _requirePc();
    final offer = await pc.createOffer(<String, dynamic>{});
    final fixed = _fixSdp(offer);
    await pc.setLocalDescription(fixed);
    return fixed;
  }

  Future<void> setRemoteOffer(Map<String, dynamic> description) async {
    if (_isDuplicateRemoteDescription('offer', description)) return;
    final pc = _requirePc();
    await pc.setRemoteDescription(
      RTCSessionDescription('${description['sdp'] ?? ''}', '${description['type'] ?? 'offer'}'),
    );
    _rememberRemoteDescription('offer', description);
    await _flushRemoteCandidatesIfReady();
  }

  Future<RTCSessionDescription> createAnswer() async {
    final pc = _requirePc();
    final answer = await pc.createAnswer(<String, dynamic>{});
    final fixed = _fixSdp(answer);
    await pc.setLocalDescription(fixed);
    return fixed;
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> description) async {
    if (_isDuplicateRemoteDescription('answer', description)) return;
    final pc = _requirePc();
    await pc.setRemoteDescription(
      RTCSessionDescription('${description['sdp'] ?? ''}', '${description['type'] ?? 'answer'}'),
    );
    _rememberRemoteDescription('answer', description);
    await _flushRemoteCandidatesIfReady();
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidateMap) async {
    final candidateText = '${candidateMap['candidate'] ?? ''}';
    if (candidateText.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateText,
      candidateMap['sdpMid'] == null ? null : '${candidateMap['sdpMid']}',
      int.tryParse('${candidateMap['sdpMLineIndex'] ?? 0}') ?? 0,
    );
    final pc = _pc;
    final remoteDescription = await pc?.getRemoteDescription();
    if (pc == null || remoteDescription == null) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  Future<void> _flushRemoteCandidatesIfReady() async {
    final pc = _pc;
    if (pc == null || _pendingRemoteCandidates.isEmpty) return;
    final remoteDescription = await pc.getRemoteDescription();
    if (remoteDescription == null) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await pc.addCandidate(candidate);
    }
  }

  Future<void> switchCamera() async {
    final videos = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (videos.isEmpty) return;
    await Helper.switchCamera(videos.first);
  }

  void toggleMic() {
    _micEnabled = !_micEnabled;
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _micEnabled;
    }
  }

  void toggleCamera() {
    _cameraEnabled = !_cameraEnabled;
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _cameraEnabled;
    }
  }

  bool _isDuplicateRemoteDescription(String expectedType, Map<String, dynamic> description) {
    final sdp = '${description['sdp'] ?? ''}';
    if (sdp.isEmpty) return false;
    final type = '${description['type'] ?? expectedType}'.toLowerCase();
    return _lastRemoteDescriptions[type] == sdp;
  }

  void _rememberRemoteDescription(String expectedType, Map<String, dynamic> description) {
    final sdp = '${description['sdp'] ?? ''}';
    if (sdp.isEmpty) return;
    final type = '${description['type'] ?? expectedType}'.toLowerCase();
    _lastRemoteDescriptions[type] = sdp;
  }

  RTCSessionDescription _fixSdp(RTCSessionDescription s) {
    final sdp = s.sdp;
    if (sdp == null) return s;
    return RTCSessionDescription(
      sdp.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032'),
      s.type,
    );
  }

  RTCPeerConnection _requirePc() {
    final pc = _pc;
    if (pc == null) throw StateError('PeerConnection 尚未创建');
    return pc;
  }

  Future<void> close() async {
    _pendingRemoteCandidates.clear();
    _lastRemoteDescriptions.clear();
    for (final sender in _senders) {
      try {
        await _pc?.removeTrack(sender);
      } catch (_) {}
    }
    _senders.clear();
    await _pc?.close();
    _pc = null;
    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _remoteStream?.dispose();
    _remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  Future<void> dispose() async {
    await close();
    if (_renderersReady) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersReady = false;
    }
  }
}

typedef VoidCallbackLike = void Function();
