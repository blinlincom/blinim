import 'package:audioplayers/audioplayers.dart';

import 'sound_preferences.dart';

class AppSoundPlayer {
  static const String _ringAsset = 'sounds/blinlin_ring.ogg';
  static final AppSoundPlayer instance = AppSoundPlayer._();

  final AudioPlayer _effectPlayer = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final SoundPreferences _preferences = const SoundPreferences();
  bool _ringing = false;

  AppSoundPlayer._();

  Future<bool> get enabled => _preferences.loadEnabled();

  Future<void> playMessage() async {
    if (!await enabled) return;
    await _playOnce(volume: 0.68);
  }

  Future<void> startRingtone() async {
    if (_ringing || !await enabled) return;
    _ringing = true;
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(0.82);
      await _ringtonePlayer.play(AssetSource(_ringAsset));
    } catch (_) {
      _ringing = false;
    }
  }

  Future<void> stopRingtone() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }

  Future<void> _playOnce({required double volume}) async {
    try {
      await _effectPlayer.stop();
      await _effectPlayer.setReleaseMode(ReleaseMode.release);
      await _effectPlayer.setVolume(volume);
      await _effectPlayer.play(AssetSource(_ringAsset));
    } catch (_) {}
  }
}
