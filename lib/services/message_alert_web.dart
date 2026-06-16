import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/im_models.dart';

class MessageAlertService {
  static final String _bellSrc = _buildBellDataUri();

  Future<void> prepare() async {}
  Future<void> startKeepAlive() async {}
  Future<void> stopKeepAlive() async {}

  Future<void> notifyMessage(UnifiedMessage message) async {
    if (message.isMe) return;
    _playBell();
  }

  Future<void> notifyPlain({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    _playBell();
  }

  Future<void> notifyCall({
    required String title,
    required String body,
    int? id,
    String? payload,
  }) async {
    _playBell();
  }

  Future<String?> getLaunchPayload() async => null;

  void _playBell() {
    try {
      final audio = html.AudioElement(_bellSrc)
        ..volume = 0.68
        ..preload = 'auto';
      audio.play();
    } catch (_) {}
  }

  static String _buildBellDataUri() {
    const sampleRate = 16000;
    const durationMs = 360;
    final sampleCount = sampleRate * durationMs ~/ 1000;
    final dataSize = sampleCount * 2;
    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(bytes);

    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes[offset + i] = text.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final fadeIn = math.min(1.0, i / (sampleRate * 0.025));
      final fadeOut = math.min(1.0, (sampleCount - i) / (sampleRate * 0.09));
      final env = fadeIn * fadeOut;
      final wave =
          math.sin(2 * math.pi * 880 * t) * 0.72 +
          math.sin(2 * math.pi * 1320 * t) * 0.22;
      final sample = (wave * env * 26000).clamp(-32767, 32767).round();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return 'data:audio/wav;base64,${base64Encode(bytes)}';
  }
}
