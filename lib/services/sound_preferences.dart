import 'package:shared_preferences/shared_preferences.dart';

class SoundPreferences {
  static const String _enabledKey = 'sound_alerts_enabled';

  const SoundPreferences();

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
}
