import 'package:shared_preferences/shared_preferences.dart';

class ChatDisplayPreferences {
  static const double minChatFontSize = 13;
  static const double maxChatFontSize = 20;
  static const double defaultChatFontSize = 14;

  static const String _chatFontSizeKey = 'chat_message_font_size';

  const ChatDisplayPreferences();

  Future<double> loadChatFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeChatFontSize(prefs.getDouble(_chatFontSizeKey));
  }

  Future<void> saveChatFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_chatFontSizeKey, normalizeChatFontSize(value));
  }

  static double normalizeChatFontSize(double? value) {
    final next = value ?? defaultChatFontSize;
    return next.clamp(minChatFontSize, maxChatFontSize).toDouble();
  }
}
