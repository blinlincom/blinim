import 'dart:async';
import 'dart:convert';

import '../models/call_signal.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';

class CallSignalingAdapter {
  final ApiService api;
  final ImService im;
  final String token;
  final int selfId;
  final int peerId;

  int _lastSeq = 0;
  final Set<String> _seenSignalIds = <String>{};
  StreamSubscription? _sub;
  final _controller = StreamController<CallSignal>.broadcast();

  CallSignalingAdapter({
    required this.api,
    required this.im,
    required this.token,
    required this.selfId,
    required this.peerId,
  });

  Stream<CallSignal> get signals => _controller.stream;

  void start() {
    _sub ??= im.calls.listen((payload) {
      final signal = CallSignal.tryParse(payload);
      if (signal == null) return;
      _observeSeq(signal);
      if (!_isPeerSignal(signal)) return;
      _emit(signal);
    });
  }

  Future<List<CallSignal>> pull({String callId = '', int sinceId = 0}) async {
    final rows = await api.getImCallSignals(
      token: token,
      sinceId: sinceId,
      callId: callId,
      peerId: peerId,
      limit: 80,
    );
    final parsed = <CallSignal>[];
    for (final row in rows) {
      final signal = CallSignal.tryParse(row);
      if (signal == null) continue;
      _observeSeq(signal);
      if (!_isPeerSignal(signal)) continue;
      parsed.add(signal);
      _emit(signal);
    }
    return parsed;
  }

  Future<int> send({
    required String callId,
    required String action,
    required String media,
    Map<String, dynamic> content = const <String, dynamic>{},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedAction = CallSignal.normalizeAction(action);
    final candidateSeq = DateTime.now().millisecondsSinceEpoch % 2000000000;
    final seq = candidateSeq > _lastSeq ? candidateSeq : _lastSeq + 1;
    _lastSeq = seq;
    final signal = CallSignal(
      callId: callId,
      signalId: '${callId}_${selfId}_${now}_${seq}_$normalizedAction',
      action: normalizedAction,
      media: media,
      fromUserId: selfId,
      toUserId: peerId,
      fromUid: ImService.uidForUser(selfId),
      toUid: ImService.uidForUser(peerId),
      deviceId: im.currentDeviceId ?? '',
      seq: seq,
      timestamp: now,
      content: {
        ...content,
        'seq': seq,
        'from_device_id': im.currentDeviceId ?? '',
      },
      raw: const <String, dynamic>{},
    );
    return api.sendImCallSignal(
      token: token,
      toUserId: peerId,
      payload: signal.toPayload(),
    );
  }

  bool _isPeerSignal(CallSignal signal) {
    final fromPeerToMe = signal.fromUserId == peerId && signal.toUserId == selfId;
    final toPeerFromMe = signal.fromUserId == selfId && signal.toUserId == peerId;
    final legacyPeerSignal = signal.fromUserId == peerId || signal.toUserId == selfId;
    return fromPeerToMe || toPeerFromMe || legacyPeerSignal;
  }

  void _observeSeq(CallSignal signal) {
    if (signal.seq > _lastSeq) _lastSeq = signal.seq;
  }

  void _emit(CallSignal signal) {
    if (signal.signalId.isNotEmpty && !_seenSignalIds.add(signal.signalId)) {
      return;
    }
    if (!_controller.isClosed) _controller.add(signal);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}

String rtcDescriptionToJsonMap(dynamic description) => jsonEncode({
      'sdp': description.sdp,
      'type': description.type,
    });