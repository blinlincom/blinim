import 'dart:html' as html;
import '../models/im_models.dart';

class MessageAlertService {
  Future<void> prepare() async {}

  Future<void> notifyMessage(UnifiedMessage message) async {
    if (message.isMe) return;
    _playBell();
  }

  void _playBell() {
    try {
      final context = html.AudioContext();
      final now = context.currentTime;
      final oscillator = context.createOscillator();
      final gain = context.createGain();
      oscillator.type = 'sine';
      oscillator.frequency?.setValueAtTime(880, now);
      gain.gain?.setValueAtTime(0.0001, now);
      gain.gain?.exponentialRampToValueAtTime(0.18, now + 0.02);
      gain.gain?.exponentialRampToValueAtTime(0.0001, now + 0.42);
      oscillator.connectNode(gain);
      gain.connectNode(context.destination);
      oscillator.start(0);
      oscillator.stop(now + 0.44);
    } catch (_) {
      try {
        html.AudioElement()
          ..src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA='
          ..play();
      } catch (_) {}
    }
  }
}