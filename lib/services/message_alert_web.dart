import '../models/im_models.dart';
import 'app_sound_player.dart';

class MessageAlertService {
  Future<void> prepare() async {}
  Future<void> startKeepAlive() async {}
  Future<void> stopKeepAlive() async {}

  Future<void> notifyMessage(UnifiedMessage message) async {
    if (message.isMe) return;
    await AppSoundPlayer.instance.playMessage();
  }

  Future<void> notifyPlain({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return AppSoundPlayer.instance.playMessage();
  }

  Future<void> notifyCall({
    required String title,
    required String body,
    int? id,
    String? payload,
  }) {
    return AppSoundPlayer.instance.playMessage();
  }

  Future<String?> getLaunchPayload() async => null;
}
