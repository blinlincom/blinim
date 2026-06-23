import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';

class CallMediaEngine {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _ownsLocalStream = true;
  final List<RTCRtpSender> _senders = <RTCRtpSender>[];
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  final Set<String> _remoteTrackIds = <String>{};
  bool _renderersReady = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;

  Future<void> Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCIceConnectionState state)? onIceConnectionState;
  void Function(RTCPeerConnectionState state)? onConnectionState;
  void Function(MediaStream stream)? onRemoteStream;
  void Function(MediaStream stream)? onRemoteMediaReady;
  VoidCallbackLike? onLocalStreamChanged;

  bool get hasPeerConnection => _pc != null;
  bool get micEnabled => _micEnabled;
  bool get cameraEnabled => _cameraEnabled;
  MediaStream? get localStream => _localStream;
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
    if (_localStream == null) {
      AppLogger.call('Media 打开本地媒体 video=$video');
    }
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
    AppLogger.call(
      'Media 本地媒体就绪 audio=${_localStream?.getAudioTracks().length ?? 0} video=${_localStream?.getVideoTracks().length ?? 0}',
    );
    onLocalStreamChanged?.call();
  }

  Future<void> useLocalStream(MediaStream stream) async {
    await initializeRenderers();
    _localStream = stream;
    _ownsLocalStream = false;
    localRenderer.srcObject = stream;
    _micEnabled = stream.getAudioTracks().every((track) => track.enabled);
    _cameraEnabled = stream.getVideoTracks().every((track) => track.enabled);
    AppLogger.call(
      'Media 复用本地媒体 audio=${stream.getAudioTracks().length} video=${stream.getVideoTracks().length}',
    );
    onLocalStreamChanged?.call();
  }

  Future<void> ensurePeerConnection({
    required bool video,
    List<Map<String, dynamic>>? iceServers,
  }) async {
    if (_pc != null) return;
    await openLocalMedia(video: video);
    final servers =
        iceServers ?? this.iceServers ?? AppConfig.publicStunServers;
    final config = <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceTransportPolicy': 'all',
      'iceCandidatePoolSize': 2,
    };
    AppLogger.call(
      'Media 创建PeerConnection iceServers=${servers.length} turn=${_hasTurnServer(servers)} video=$video',
    );
    final pc = await createPeerConnection(config, {
      'mandatory': <String, dynamic>{},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final type = _candidateType(candidate.candidate!);
      AppLogger.call(
        'Media 本地ICE candidate type=$type mid=${candidate.sdpMid} line=${candidate.sdpMLineIndex}',
      );
      final handler = onIceCandidate;
      if (handler != null) unawaited(handler(candidate));
    };
    pc.onIceConnectionState = (state) {
      AppLogger.call('Media ICE状态 $state');
      onIceConnectionState?.call(state);
    };
    pc.onIceGatheringState = (state) {
      AppLogger.call('Media ICE收集状态 $state');
    };
    pc.onConnectionState = (state) {
      AppLogger.call('Media PeerConnection状态 $state');
      onConnectionState?.call(state);
    };
    pc.onTrack = (event) {
      unawaited(_handleRemoteTrack(event));
    };
    pc.onAddStream = (stream) {
      _bindRemoteStream(stream, source: 'stream');
    };

    await _attachLocalTracks(pc);
    _pc = pc;
    await _flushRemoteCandidatesIfReady();
  }

  Future<void> _attachLocalTracks(RTCPeerConnection pc) async {
    final stream = _localStream;
    if (stream == null) {
      throw StateError('本地媒体流为空');
    }
    final tracks = stream.getTracks();
    if (tracks.isEmpty) {
      throw StateError('本地媒体轨道为空');
    }

    var added = 0;
    for (final track in tracks) {
      try {
        final sender = await pc.addTrack(track, stream);
        _senders.add(sender);
        added++;
        AppLogger.call('Media 已添加本地track kind=${track.kind} id=${track.id}');
      } catch (e) {
        AppLogger.warn(
          'CALL',
          'Media addTrack失败，跳过异常track',
          data: {'kind': track.kind, 'id': track.id, 'error': '$e'},
        );
      }
    }

    if (added > 0) return;
    try {
      await pc.addStream(stream);
      AppLogger.call('Media addTrack全部失败，已回退addStream tracks=${tracks.length}');
    } catch (e) {
      throw StateError('本地媒体轨道添加失败：$e');
    }
  }

  Future<void> _handleRemoteTrack(RTCTrackEvent event) async {
    try {
      final track = event.track;
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream =
            _remoteStream ??
            await createLocalMediaStream(
              'remote_${DateTime.now().millisecondsSinceEpoch}',
            );
        final trackKey = track.id ?? '${track.kind}_${_remoteTrackIds.length}';
        if (!_remoteTrackIds.contains(trackKey)) {
          await stream.addTrack(track);
        }
      }
      final trackKey = track.id ?? '${track.kind}_${_remoteTrackIds.length}';
      _remoteTrackIds.add(trackKey);
      AppLogger.call(
        'Media 收到远端track kind=${track.kind} id=${track.id} streams=${event.streams.length}',
      );
      _bindRemoteStream(stream, source: 'track');
    } catch (e, st) {
      AppLogger.error('CALL', 'Media 绑定远端track失败', error: e, stack: st);
    }
  }

  void _bindRemoteStream(MediaStream stream, {required String source}) {
    final previous = _remoteStream;
    _remoteStream = stream;
    if (remoteRenderer.srcObject?.id != stream.id) {
      remoteRenderer.srcObject = stream;
    }
    final audio = stream.getAudioTracks().length;
    final video = stream.getVideoTracks().length;
    AppLogger.call(
      'Media 远端媒体就绪 source=$source stream=${stream.id} audio=$audio video=$video tracks=${stream.getTracks().length}',
    );
    if (previous?.id != stream.id || previous == null) {
      onRemoteStream?.call(stream);
    }
    onRemoteMediaReady?.call(stream);
  }

  bool _hasTurnServer(List<Map<String, dynamic>> servers) {
    for (final server in servers) {
      final urls = server['urls'];
      if (urls is Iterable &&
          urls.any((url) => '$url'.trim().toLowerCase().startsWith('turn'))) {
        return true;
      }
      if ('$urls'.trim().toLowerCase().startsWith('turn')) return true;
    }
    return false;
  }

  String _candidateType(String text) {
    final match = RegExp(r'\btyp\s+([a-zA-Z0-9_-]+)').firstMatch(text);
    return match?.group(1)?.toLowerCase() ?? 'unknown';
  }

  Future<RTCSessionDescription> createOffer() async {
    final pc = _requirePc();
    AppLogger.call('Media 创建offer');
    final offer = await pc.createOffer(<String, dynamic>{});
    final fixed = _fixSdp(offer);
    await pc.setLocalDescription(fixed);
    AppLogger.call('Media offer已设置 len=${fixed.sdp?.length ?? 0}');
    return fixed;
  }

  Future<void> setRemoteOffer(Map<String, dynamic> description) async {
    if (_isDuplicateRemoteDescription('offer', description)) return;
    final pc = _requirePc();
    final sdp = '${description['sdp'] ?? ''}';
    AppLogger.call('Media 设置远端offer len=${sdp.length}');
    await pc.setRemoteDescription(
      RTCSessionDescription(sdp, '${description['type'] ?? 'offer'}'),
    );
    _rememberRemoteDescription('offer', description);
    await _flushRemoteCandidatesIfReady();
  }

  Future<RTCSessionDescription> createAnswer() async {
    final pc = _requirePc();
    AppLogger.call('Media 创建answer');
    final answer = await pc.createAnswer(<String, dynamic>{});
    final fixed = _fixSdp(answer);
    await pc.setLocalDescription(fixed);
    AppLogger.call('Media answer已设置 len=${fixed.sdp?.length ?? 0}');
    return fixed;
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> description) async {
    if (_isDuplicateRemoteDescription('answer', description)) return;
    final pc = _requirePc();
    final sdp = '${description['sdp'] ?? ''}';
    AppLogger.call('Media 设置远端answer len=${sdp.length}');
    await pc.setRemoteDescription(
      RTCSessionDescription(sdp, '${description['type'] ?? 'answer'}'),
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
      AppLogger.call(
        'Media 缓存远端ICE pending=${_pendingRemoteCandidates.length}',
      );
      return;
    }
    try {
      await pc.addCandidate(candidate);
      final type = _candidateType(candidateText);
      AppLogger.call(
        'Media 添加远端ICE成功 type=$type mid=${candidate.sdpMid} line=${candidate.sdpMLineIndex}',
      );
    } catch (e) {
      AppLogger.warn('CALL', 'Media 添加远端ICE失败', data: e);
    }
  }

  Future<void> _flushRemoteCandidatesIfReady() async {
    final pc = _pc;
    if (pc == null || _pendingRemoteCandidates.isEmpty) return;
    final remoteDescription = await pc.getRemoteDescription();
    if (remoteDescription == null) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await pc.addCandidate(candidate);
        final type = _candidateType(candidate.candidate ?? '');
        AppLogger.call(
          'Media 刷新远端ICE成功 type=$type mid=${candidate.sdpMid} line=${candidate.sdpMLineIndex}',
        );
      } catch (e) {
        AppLogger.warn('CALL', 'Media 刷新远端ICE失败', data: e);
      }
    }
  }

  Future<void> switchCamera() async {
    final videos = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (videos.isEmpty) return;
    await Helper.switchCamera(videos.first);
  }

  void toggleMic() {
    _micEnabled = !_micEnabled;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _micEnabled;
    }
  }

  void toggleCamera() {
    _cameraEnabled = !_cameraEnabled;
    for (final track
        in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _cameraEnabled;
    }
  }

  bool _isDuplicateRemoteDescription(
    String expectedType,
    Map<String, dynamic> description,
  ) {
    final sdp = '${description['sdp'] ?? ''}';
    if (sdp.isEmpty) return false;
    final type = '${description['type'] ?? expectedType}'.toLowerCase();
    return _lastRemoteDescriptions[type] == sdp;
  }

  void _rememberRemoteDescription(
    String expectedType,
    Map<String, dynamic> description,
  ) {
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
    AppLogger.call('Media 关闭');
    _pendingRemoteCandidates.clear();
    _remoteTrackIds.clear();
    _lastRemoteDescriptions.clear();
    for (final sender in _senders) {
      try {
        await _pc?.removeTrack(sender);
      } catch (_) {}
    }
    _senders.clear();
    await _pc?.close();
    _pc = null;
    if (_ownsLocalStream) {
      for (final track
          in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        try {
          track.enabled = false;
        } catch (_) {}
        try {
          await track.stop();
        } catch (e) {
          AppLogger.warn(
            'CALL',
            'Media 停止本地track失败',
            data: {'kind': track.kind, 'id': track.id, 'error': '$e'},
          );
        }
      }
      await _localStream?.dispose();
    }
    _localStream = null;
    _ownsLocalStream = true;
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
