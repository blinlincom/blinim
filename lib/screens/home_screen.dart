import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';
import '../models/call_signal.dart';
import '../services/api_service.dart';
import '../services/app_update_installer.dart';
import '../services/auth_store.dart';
import '../services/chat_display_preferences.dart';
import '../services/conversation_preferences.dart';
import '../services/im_service.dart';
import '../services/message_alert_service.dart';
import '../services/screenshot_monitor.dart';
import '../utils/media_url.dart';
import '../widgets/blin_style.dart';
import '../widgets/gif_sticker_panel.dart';
import '../widgets/payment_password_sheet.dart';
import 'chat_list_screen.dart';
import 'call_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<UserSession> onSessionChanged;
  final VoidCallback onLogout;
  const HomeScreen({
    super.key,
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onSessionChanged,
    required this.onLogout,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _NotificationChatTarget {
  final String conversation;
  final int peerId;
  final String peerName;
  final String peerAvatar;
  final int groupId;
  final String groupNo;

  const _NotificationChatTarget({
    required this.conversation,
    this.peerId = 0,
    this.peerName = '',
    this.peerAvatar = '',
    this.groupId = 0,
    this.groupNo = '',
  });

  bool get isGroup => conversation == 'group';

  static _NotificationChatTarget? fromMap(Map<String, dynamic> map) {
    final conversation = '${map['conversation'] ?? map['chat_type'] ?? ''}'
        .trim()
        .toLowerCase();
    final payload = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'])
        : const <String, dynamic>{};
    final content = payload['content'] is Map
        ? Map<String, dynamic>.from(payload['content'])
        : const <String, dynamic>{};
    final groupId = _int([
      map['group_id'],
      payload['group_id'],
      content['group_id'],
    ]);
    final groupNo = _text([
      map['group_no'],
      payload['group_no'],
      payload['groupNo'],
      content['group_no'],
    ]);
    if (conversation == 'group' || groupId > 0 || groupNo.isNotEmpty) {
      if (groupId <= 0 && groupNo.isEmpty) return null;
      return _NotificationChatTarget(
        conversation: 'group',
        groupId: groupId,
        groupNo: groupNo,
      );
    }
    final peerId = _int([
      map['peer_id'],
      payload['from_user_id'],
      payload['sender_id'],
      content['from_user_id'],
    ]);
    if (peerId <= 0) return null;
    return _NotificationChatTarget(
      conversation: 'peer',
      peerId: peerId,
      peerName: _text([
        map['peer_name'],
        payload['from_name'],
        payload['nickname'],
        content['nickname'],
      ]),
      peerAvatar: _text([
        map['peer_avatar'],
        payload['from_avatar'],
        payload['avatar'],
        content['avatar'],
      ]),
    );
  }

  static int _int(Iterable<Object?> values) {
    for (final value in values) {
      final parsed = int.tryParse('${value ?? ''}');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  static String _text(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null' && text != '0') return text;
    }
    return '';
  }
}

int _groupUnreadFromRaw(ImGroup group) {
  int firstInt(Iterable<Object?> values) {
    for (final value in values) {
      final parsed = int.tryParse('${value ?? ''}');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  final raw = group.raw;
  final message = raw['message'] is Map
      ? Map<String, dynamic>.from(raw['message'] as Map)
      : raw['last_message'] is Map
      ? Map<String, dynamic>.from(raw['last_message'] as Map)
      : const <String, dynamic>{};
  return firstInt([
    raw['unread_quantity'],
    raw['unread_num'],
    raw['unread_count'],
    raw['message_unread_count'],
    raw['msg_unread_count'],
    raw['unread'],
    raw['badge'],
    raw['red_dot'],
    message['unread_quantity'],
    message['unread_num'],
    message['unread_count'],
    message['message_unread_count'],
    message['msg_unread_count'],
    message['unread'],
  ]);
}

class _AppUpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String content;
  final bool force;

  const _AppUpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.content,
    required this.force,
  });

  bool get hasUpdate {
    final latest = latestVersion.trim();
    if (latest.isEmpty || latest == 'null') return false;
    return _isVersionNewerOrDifferent(latest, AppConfig.appVersion);
  }

  static _AppUpdateInfo fromAppInfo(Map<String, dynamic> info) {
    final updates = info['updates_info'];
    final updateMap = updates is Map
        ? Map<String, dynamic>.from(updates)
        : info;
    return _AppUpdateInfo(
      latestVersion: _pickText(updateMap, const [
        'update_version',
        'version',
        'latest_version',
        'app_version',
        'new_version',
      ]),
      downloadUrl: resolveMediaUrl(
        _pickText(updateMap, const [
          'update_url',
          'download_url',
          'apk_url',
          'android_url',
          'url',
        ]),
      ),
      content: _pickText(updateMap, const [
        'update_content',
        'changelog',
        'change_log',
        'content',
        'description',
        'remark',
      ]),
      force: _truthySwitch(
        _pickNullable(updateMap, const [
          'force_update',
          'forced_update',
          'update_force',
          'is_force',
          'must_update',
          'mandatory_update',
          'force_upgrade',
        ]),
      ),
    );
  }

  static String _pickText(Map<String, dynamic> map, List<String> keys) {
    final value = _pickNullable(map, keys);
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return '';
    return text;
  }

  static Object? _pickNullable(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (!map.containsKey(key)) continue;
      final value = map[key];
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return value;
    }
    return null;
  }

  static bool _truthySwitch(Object? value) {
    if (value == true) return true;
    if (value == false) return false;
    final text = '${value ?? ''}'.trim().toLowerCase();
    return text == '1' ||
        text == 'true' ||
        text == 'yes' ||
        text == 'on' ||
        text == 'enabled' ||
        text == 'force' ||
        text == 'mandatory';
  }

  static bool _isVersionNewerOrDifferent(String latest, String current) {
    final latestParts = _versionParts(latest);
    final currentParts = _versionParts(current);
    if (latestParts.isNotEmpty && currentParts.isNotEmpty) {
      final length = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;
      for (var i = 0; i < length; i++) {
        final a = i < latestParts.length ? latestParts[i] : 0;
        final b = i < currentParts.length ? currentParts[i] : 0;
        if (a > b) return true;
        if (a < b) return false;
      }
      return false;
    }
    return latest.trim() != current.trim();
  }

  static List<int> _versionParts(String value) {
    final matches = RegExp(r'\d+').allMatches(value).toList();
    if (matches.isEmpty) return const <int>[];
    return matches
        .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .toList(growable: false);
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Duration _incomingCallFreshness = Duration(seconds: 90);
  static final profileEventStream =
      StreamController<Map<String, dynamic>>.broadcast();
  int index = 0;
  int chatListResetSwipeToken = 0;
  final visitedTabs = <int>{0};
  final chatListNavigator = ChatListNavigator();
  late final ImService im;
  final alerts = MessageAlertService();
  StreamSubscription? imSub;
  StreamSubscription? messageSub;
  StreamSubscription? callSub;
  StreamSubscription? friendSub;
  final Map<String, List<Map<String, dynamic>>> pendingCallSignals = {};
  Timer? unreadTimer;
  Timer? callSignalSyncTimer;
  Timer? reconnectTimer;
  Timer? healthTimer;
  bool reconnecting = false;
  bool syncingCallSignals = false;
  bool callWatermarkLoaded = false;
  bool appInForeground = true;
  bool voiceMessageEnabled = true;
  bool screenshotNoticeEnabled = false;
  DateTime? connectStartedAt;
  int unreadCount = 0;
  int lastCallSignalId = 0;
  Set<String> mutedConversationKeys = {};
  final Set<String> openingCallIds = <String>{};
  final Set<String> notifiedCallIds = <String>{};
  final Set<String> handledIncomingCallIds = <String>{};
  _NotificationChatTarget? pendingChatTarget;
  final Map<String, BuildContext> incomingCallDialogContexts =
      <String, BuildContext>{};
  DateTime? lastUnreadRefreshAt;
  DateTime? lastCallSignalSyncAt;
  DateTime? lastHealthCheckAt;
  DateTime? nextReconnectAt;
  int reconnectFailures = 0;
  int callSignalSyncFailures = 0;
  bool refreshingUnreadCount = false;
  bool updateDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    im = ImService();
    unawaited(alerts.prepare());
    unawaited(ScreenshotMonitor.prepare());
    unawaited(_loadMutedConversations());
    unawaited(_loadAppFeatureSwitches());
    HardwareKeyboard.instance.addHandler(_handleScreenshotKeyEvent);
    imSub = im.connectionChanges.listen((_) {
      if (mounted) setState(() {});
      if (!im.connected && !im.connecting) scheduleReconnect();
      if (im.connected) {
        unawaited(
          _syncCallSignalsFromBackend().then(
            (_) => _openPendingForegroundCalls(),
          ),
        );
      }
      unawaited(_refreshUnreadCount());
    });
    messageSub = im.messages.listen((message) {
      unawaited(_handleRealtimeMessage(message));
    });
    friendSub = im.friendEvents.listen((payload) {
      unawaited(_refreshUnreadCount());
      final content = normalizeFriendEventContent(payload);
      final action = '${content['action'] ?? payload['action'] ?? ''}';
      if (action == 'profile' ||
          action == 'wallet' ||
          action == 'notification' ||
          action == 'moments_feed' ||
          action == 'moments_notification' ||
          action == 'app_notice' ||
          action == 'app_update') {
        profileEventStream.add(content);
      }
      if (action == 'app_notice' || action == 'app_update') {
        unawaited(_loadAppFeatureSwitches());
      }
      if (action == 'request') {
        unawaited(
          alerts.notifyPlain(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '好友申请',
            body: '${content['nickname'] ?? '新朋友'} 请求添加你为好友',
            payload: jsonEncode(payload),
          ),
        );
      }
    });
    callSub = im.calls.listen((payload) {
      final signal = CallSignal.tryParse(payload);
      if (signal == null) {
        AppLogger.warn('HOME', '收到无法解析的通话信令', data: payload);
        return;
      }
      AppLogger.call(
        'Home 收到IM通话信令 action=${signal.action} call=${signal.callId} from=${signal.fromUserId} to=${signal.toUserId}',
      );
      if (_isGroupCallInternalSignal(signal)) {
        AppLogger.call('Home 已忽略群通话内部信令 call=${signal.callId}');
        return;
      }
      final normalized = signal.toPayload();
      if (signal.isInviteLike) {
        if (signal.callId.isEmpty ||
            signal.fromUserId == widget.session.id ||
            (signal.callId.isNotEmpty &&
                (CallRouteGuard.isClosed(signal.callId) ||
                    CallRouteGuard.isOutgoing(signal.callId)))) {
          AppLogger.call(
            'Home 已忽略无效/本机实时来电 call=${signal.callId} action=${signal.action} from=${signal.fromUserId} to=${signal.toUserId}',
          );
          return;
        }
        if (CallRouteGuard.hasActiveCall || openingCallIds.isNotEmpty) {
          if (CallRouteGuard.isActiveCall(signal.callId)) {
            AppLogger.call('Home 已忽略当前通话重复来电信令 call=${signal.callId}');
            return;
          }
          unawaited(_sendBusySignal(signal));
          return;
        }
        _queueRealtimeIncomingCall(
          normalized,
          notify: !appInForeground,
          openNow: appInForeground,
        );
      } else {
        _cacheCallSignal(normalized, terminal: signal.isTerminal);
        if (signal.isTerminal) _closeIncomingCallDialog(signal.callId);
      }
    });
    unreadTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refreshUnreadCount()),
    );
    healthTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_checkImHealth()),
    );
    _connect();
    unawaited(_refreshUnreadCount());
    unawaited(_consumeLaunchPayload());
    unawaited(_initCallSignalSync());
    _scheduleStartupCallSignalSync();
    startCallSignalSyncLoop();
  }

  Future<void> _loadAppFeatureSwitches() async {
    try {
      final info = await const ApiService().getAppInfo();
      unawaited(() async {
        final forcedUpdateShown = await _showForcedUpdateIfNeeded(info);
        if (!forcedUpdateShown) await _showAppAnnouncementIfNeeded(info);
      }());
      final imConfig = info['im_configuration'] is Map
          ? Map<String, dynamic>.from(info['im_configuration'])
          : info['message_configuration'] is Map
          ? Map<String, dynamic>.from(info['message_configuration'])
          : info;
      final raw =
          '${imConfig['voice_message_switch'] ?? imConfig['voice_switch'] ?? imConfig['audio_message_switch'] ?? ''}';
      final screenshotRaw =
          '${imConfig['screenshot_notice_switch'] ?? imConfig['screenshot_switch'] ?? imConfig['screen_capture_notice_switch'] ?? ''}';
      if (!mounted) return;
      setState(() {
        if (raw.isNotEmpty && raw != 'null') {
          voiceMessageEnabled = raw != '1' && raw != 'false';
        }
        screenshotNoticeEnabled = _adminSwitchEnabled(
          screenshotRaw,
          fallback: false,
        );
      });
    } catch (_) {
      // 配置接口失败时保持默认开启，避免影响现有 IM 功能。
    }
  }

  Future<bool> _showForcedUpdateIfNeeded(Map<String, dynamic> info) async {
    final update = _AppUpdateInfo.fromAppInfo(info);
    if (!update.force || !update.hasUpdate || updateDialogShowing) return false;
    if (!mounted) return false;
    updateDialogShowing = true;
    try {
      final accepted = await _showAppUpdateDialog(context, update);
      if (accepted == true && mounted) {
        await _downloadAndInstallUpdate(context, update);
      }
      return true;
    } finally {
      updateDialogShowing = false;
    }
  }

  Future<void> _showAppAnnouncementIfNeeded(Map<String, dynamic> info) async {
    try {
      final announcement = _extractAppAnnouncement(info);
      if (announcement.isEmpty) return;
      final signature = _announcementSignature(announcement);
      final prefs = await SharedPreferences.getInstance();
      final key = _announcementReadKey();
      if (prefs.getString(key) == signature) return;
      if (!mounted) return;
      await _showForcedAnnouncementDialog(context, announcement);
      await prefs.setString(key, signature);
    } catch (_) {}
  }

  String _announcementReadKey() =>
      'app_announcement_read_${AppConfig.appId}_${widget.session.id}';

  String _announcementSignature(String content) =>
      base64Url.encode(utf8.encode(content.trim()));

  String _extractAppAnnouncement(Map<String, dynamic> info) {
    String pickFrom(Map map) {
      for (final key in const [
        'app_announcement',
        'app_notice',
        'system_announcement',
        'system_notice',
        'client_announcement',
        'client_notice',
        'popup_announcement',
        'popup_notice',
        'notice_content',
        'announcement_content',
        'notice_text',
        'announcement_text',
        'notice',
        'announcement',
      ]) {
        final value = map[key];
        final text = _plainAnnouncementText(value);
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    for (final key in const [
      'announcement_configuration',
      'notice_configuration',
      'app_notice_configuration',
      'system_notice_configuration',
      'popup_notice_configuration',
    ]) {
      final section = info[key];
      if (section is Map) {
        final enabled = _announcementSectionEnabled(section);
        if (!enabled) continue;
        final text = pickFrom(section);
        if (text.isNotEmpty) return text;
      }
    }
    return pickFrom(info);
  }

  bool _announcementSectionEnabled(Map section) {
    final raw =
        '${section['switch'] ?? section['enabled'] ?? section['notice_switch'] ?? section['announcement_switch'] ?? ''}';
    if (raw.trim().isEmpty || raw == 'null') return true;
    return _adminSwitchEnabled(raw, fallback: true);
  }

  String _plainAnnouncementText(Object? value) {
    if (value == null) return '';
    if (value is Map) {
      for (final key in const [
        'content',
        'text',
        'body',
        'message',
        'notice',
        'announcement',
      ]) {
        final text = _plainAnnouncementText(value[key]);
        if (text.isNotEmpty) return text;
      }
      return '';
    }
    if (value is List) {
      return value
          .map(_plainAnnouncementText)
          .where((item) => item.isNotEmpty)
          .join('\n\n')
          .trim();
    }
    final text = '$value'
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    if (text.isEmpty || text == 'null' || text == '0') return '';
    return text;
  }

  bool _adminSwitchEnabled(String raw, {required bool fallback}) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty || text == 'null') return fallback;
    if (text == '0' || text == 'true' || text == 'on' || text == 'enabled') {
      return true;
    }
    if (text == '1' || text == 'false' || text == 'off' || text == 'disabled') {
      return false;
    }
    return fallback;
  }

  bool _handleScreenshotKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.printScreen) {
      ScreenshotMonitor.addLocalEvent();
    }
    return false;
  }

  Future<void> _loadMutedConversations() async {
    try {
      final keys = await ConversationPreferences.loadMuted(widget.session.id);
      if (mounted) setState(() => mutedConversationKeys = keys);
    } catch (_) {}
  }

  Future<void> _handleRealtimeMessage(UnifiedMessage message) async {
    if (_isHiddenGroupCallRoomEvent(message)) return;
    unawaited(_refreshUnreadCount());
    await _loadMutedConversations();
    if (_isMutedMessage(message)) return;
    await alerts.notifyMessage(message);
  }

  bool _isMutedMessage(UnifiedMessage message) {
    if (message.isMe) return true;
    final groupId =
        int.tryParse(
          '${message.raw['group_id'] ?? message.content['group_id'] ?? 0}',
        ) ??
        0;
    if (groupId > 0) {
      return mutedConversationKeys.contains(
        ConversationPreferences.groupKey(groupId),
      );
    }
    final peerId = message.fromUserId == widget.session.id
        ? message.toUserId
        : message.fromUserId;
    if (peerId <= 0) return false;
    return mutedConversationKeys.contains(
      ConversationPreferences.peerKey(peerId),
    );
  }

  void _scheduleStartupCallSignalSync() {
    for (final delay in const [
      Duration(milliseconds: 500),
      Duration(seconds: 2),
      Duration(seconds: 6),
    ]) {
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        unawaited(
          _syncCallSignalsFromBackend(
            sinceIdOverride: 0,
          ).then((_) => _openPendingForegroundCalls()),
        );
      });
    }
  }

  void startCallSignalSyncLoop() {
    callSignalSyncTimer?.cancel();
    callSignalSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted || !appInForeground) return;
      unawaited(
        _syncCallSignalsFromBackend().then(
          (_) => _openPendingForegroundCalls(),
        ),
      );
    });
  }

  String _callAction(Map<String, dynamic> payload) =>
      CallSignal.tryParse(payload)?.action ?? '';

  String _callIdOf(Map<String, dynamic> payload) =>
      CallSignal.tryParse(payload)?.callId ?? '';

  int _callNotificationId(String callId) => 0x3fffffff & callId.hashCode;

  String _callPayloadJson(Map<String, dynamic> payload) {
    try {
      return jsonEncode({'type': 'call', 'payload': payload});
    } catch (_) {
      return '';
    }
  }

  void _cacheCallSignal(Map<String, dynamic> payload, {bool terminal = false}) {
    final callId = _callIdOf(payload);
    if (callId.isEmpty) return;
    final signal = CallSignal.tryParse(payload);
    AppLogger.call(
      'Home 缓存通话信令 call=$callId terminal=$terminal action=${_callAction(payload)}',
    );
    if (terminal) {
      CallRouteGuard.markClosed(callId);
      notifiedCallIds.add(callId);
      openingCallIds.remove(callId);
      pendingCallSignals.remove(callId);
      handledIncomingCallIds.add(callId);
      _closeIncomingCallDialog(callId);
      return;
    }
    if (signal == null) return;
    final existing = pendingCallSignals[callId];
    if (!signal.isInviteLike && existing == null) {
      AppLogger.call('Home 跳过非来电待打开信令 call=$callId action=${signal.action}');
      return;
    }
    final bucket = pendingCallSignals.putIfAbsent(
      callId,
      () => <Map<String, dynamic>>[],
    );
    final signalId =
        '${(payload['content'] is Map ? (payload['content'] as Map)['signal_id'] : null) ?? payload['client_msg_no'] ?? ''}'
            .trim();
    if (signalId.isNotEmpty) {
      final exists = bucket.any((item) {
        final content = item['content'];
        return content is Map &&
            '${content['signal_id'] ?? item['client_msg_no'] ?? ''}'.trim() ==
                signalId;
      });
      if (exists) return;
    }
    bucket.add(Map<String, dynamic>.from(payload));
  }

  bool _isFreshIncomingCallSignal(
    CallSignal signal, {
    Map<String, dynamic>? raw,
    bool allowStale = false,
  }) {
    if (_isGroupCallInternalSignal(signal)) return false;
    if (!signal.isInviteLike) return false;
    if (signal.callId.isEmpty) return false;
    if (signal.fromUserId <= 0 || signal.fromUserId == widget.session.id) {
      return false;
    }
    final toId = signal.toUserId > 0
        ? signal.toUserId
        : (raw == null
              ? 0
              : _rawUserId(raw, const ['to_user_id', 'receiver_id']));
    if (toId != widget.session.id) return false;
    if (CallRouteGuard.isClosed(signal.callId) ||
        CallRouteGuard.isOutgoing(signal.callId)) {
      return false;
    }
    if (handledIncomingCallIds.contains(signal.callId)) return false;
    if (allowStale) return true;
    final age = DateTime.now().millisecondsSinceEpoch - signal.timestamp;
    return age >= 0 && age <= _incomingCallFreshness.inMilliseconds;
  }

  bool _hasTerminalSignal(List<CallSignal> signals) =>
      signals.any((item) => item.isTerminal);

  bool _isGroupCallInternalSignal(CallSignal signal) {
    final value =
        signal.content['group_call_internal'] ??
        signal.raw['group_call_internal'] ??
        false;
    final text = '$value'.toLowerCase();
    return value == true ||
        text == 'true' ||
        text == '1' ||
        '${signal.content['group_call_room_id'] ?? signal.content['group_call_id'] ?? ''}'
            .trim()
            .isNotEmpty ||
        signal.callId.startsWith('group_call_');
  }

  bool _isHiddenGroupCallRoomEvent(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    return type == 'group_call_join' || type == 'group_call_leave';
  }

  Future<void> _loadCallSignalWatermark() async {
    final prefs = await SharedPreferences.getInstance();
    lastCallSignalId =
        prefs.getInt('im_call_last_signal_${widget.session.id}') ?? 0;
  }

  Future<void> _saveCallSignalWatermark() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'im_call_last_signal_${widget.session.id}',
      lastCallSignalId,
    );
  }

  Future<void> _sendBusySignal(CallSignal incoming) async {
    if (incoming.callId.isEmpty || incoming.fromUserId <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final busy = CallSignal(
      callId: incoming.callId,
      signalId: '${incoming.callId}_${widget.session.id}_${now}_busy',
      action: 'busy',
      media: incoming.media,
      fromUserId: widget.session.id,
      toUserId: incoming.fromUserId,
      fromUid: ImService.uidForUser(widget.session.id),
      toUid: ImService.uidForUser(incoming.fromUserId),
      deviceId: im.currentDeviceId ?? '',
      seq: now,
      timestamp: now,
      content: {
        'reason': 'busy',
        'message': '对方正在通话中',
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
      },
      raw: const {},
    );
    try {
      await const ApiService().sendImCallSignal(
        token: widget.session.token,
        toUserId: incoming.fromUserId,
        payload: busy.toPayload(),
      );
      AppLogger.call(
        'Home 已回复占线 call=${incoming.callId} to=${incoming.fromUserId}',
      );
    } catch (e) {
      AppLogger.warn(
        'HOME',
        '回复占线失败',
        data: {'call': incoming.callId, 'error': '$e'},
      );
    }
  }

  void _queueRealtimeIncomingCall(
    Map<String, dynamic> payload, {
    required bool notify,
    required bool openNow,
  }) {
    final callId = _callIdOf(payload);
    final signal = CallSignal.tryParse(payload);
    if (signal == null ||
        callId.isEmpty ||
        signal.fromUserId == widget.session.id) {
      AppLogger.call('Home 已拒绝实时来电：基础字段无效 call=$callId');
      return;
    }
    if (CallRouteGuard.isClosed(callId) || CallRouteGuard.isOutgoing(callId)) {
      return;
    }
    if (CallRouteGuard.hasActiveCall || openingCallIds.isNotEmpty) return;
    AppLogger.call('Home 实时来电入队 call=$callId notify=$notify openNow=$openNow');
    _cacheCallSignal(payload);
    if (notify && notifiedCallIds.add(callId)) {
      final content = payload['content'];
      final name = content is Map ? '${content['nickname'] ?? '有人'}' : '有人';
      final video = content is Map && '${content['media']}' == 'video';
      unawaited(
        alerts.notifyCall(
          id: _callNotificationId(callId),
          title: '搭个话来电',
          body: '$name邀请你${video ? '视频' : '语音'}通话',
          payload: _callPayloadJson(payload),
        ),
      );
    }
    if (openNow && handledIncomingCallIds.add(callId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && appInForeground) {
          unawaited(
            _openIncomingCall(payload, allowStale: true, trustRealtime: true),
          );
        }
      });
    }
  }

  void _queueIncomingCall(
    Map<String, dynamic> payload, {
    required bool notify,
    required bool openNow,
    bool allowStale = false,
  }) {
    final callId = _callIdOf(payload);
    if (callId.isEmpty) {
      AppLogger.warn('HOME', '来电入队失败：callId为空', data: payload);
      return;
    }
    final signal = CallSignal.tryParse(payload);
    if (signal == null ||
        !_isFreshIncomingCallSignal(
          signal,
          raw: payload,
          allowStale: allowStale,
        )) {
      AppLogger.call('Home 已拒绝入队过期/无效来电 call=$callId');
      return;
    }
    if (CallRouteGuard.isClosed(callId) || CallRouteGuard.isOutgoing(callId)) {
      AppLogger.call('Home 已忽略本机发起/已结束通话来电 call=$callId');
      return;
    }
    if (CallRouteGuard.hasActiveCall || openingCallIds.isNotEmpty) return;
    AppLogger.call('Home 来电入队 call=$callId notify=$notify openNow=$openNow');
    _cacheCallSignal(payload);
    if (notify && notifiedCallIds.add(callId)) {
      final content = payload['content'];
      final name = content is Map ? '${content['nickname'] ?? '有人'}' : '有人';
      final video = content is Map && '${content['media']}' == 'video';
      unawaited(
        alerts.notifyCall(
          id: _callNotificationId(callId),
          title: '搭个话来电',
          body: '$name邀请你${video ? '视频' : '语音'}通话',
          payload: _callPayloadJson(payload),
        ),
      );
    }
    if (openNow && !handledIncomingCallIds.contains(callId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && appInForeground) {
          unawaited(_openIncomingCall(payload, allowStale: allowStale));
        }
      });
    }
  }

  Future<void> _consumeLaunchPayload() async {
    final text = await alerts.getLaunchPayload();
    if (text == null || text.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final type = '${decoded['type'] ?? ''}'.trim();
      if (type == 'call') {
        final rawPayload = decoded['payload'];
        if (rawPayload is! Map) return;
        final payload = Map<String, dynamic>.from(rawPayload);
        _queueIncomingCall(payload, notify: false, openNow: true);
        return;
      }
      if (type == 'message') {
        await _openNotificationChat(
          _NotificationChatTarget.fromMap(Map<String, dynamic>.from(decoded)),
        );
      }
    } catch (_) {}
  }

  Future<void> _openNotificationChat(_NotificationChatTarget? target) async {
    if (target == null || !mounted) return;
    setState(() {
      index = 0;
      visitedTabs.add(0);
    });
    pendingChatTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushPendingChatTarget());
    });
  }

  Future<void> _flushPendingChatTarget() async {
    final target = pendingChatTarget;
    if (target == null || !mounted) return;
    pendingChatTarget = null;
    if (target.isGroup) {
      await chatListNavigator.openGroup(
        groupId: target.groupId,
        groupNo: target.groupNo,
      );
    } else {
      await chatListNavigator.openPeer(
        userId: target.peerId,
        name: target.peerName,
        avatar: target.peerAvatar,
      );
    }
  }

  Future<void> _openIncomingCall(
    Map<String, dynamic> payload, {
    bool allowStale = false,
    bool trustRealtime = false,
  }) async {
    if (!mounted) return;
    final signal = CallSignal.tryParse(payload);
    if (signal == null) return;
    if (!trustRealtime &&
        !_isFreshIncomingCallSignal(
          signal,
          raw: payload,
          allowStale: allowStale,
        )) {
      AppLogger.call(
        'Home 已阻止打开过期/无效来电 call=${signal.callId} action=${signal.action}',
      );
      return;
    }
    final content = signal.content;
    final fromId = signal.fromUserId;
    if (fromId <= 0 || fromId == widget.session.id) return;
    final callId = signal.callId;
    if (callId.isNotEmpty &&
        (CallRouteGuard.isClosed(callId) ||
            CallRouteGuard.isOutgoing(callId))) {
      AppLogger.call('Home 已阻止打开本机发起/已结束通话 call=$callId');
      return;
    }
    final openKey = callId.isNotEmpty
        ? callId
        : '${fromId}_${content['media'] ?? ''}_${content['create_time'] ?? payload['client_msg_no'] ?? ''}';
    if (openingCallIds.contains(openKey)) return;
    if (!CallRouteGuard.tryEnter(openKey)) return;
    openingCallIds.add(openKey);
    handledIncomingCallIds.add(callId);
    final video = '${content['media']}' == 'video';
    final peerName = '${content['nickname'] ?? content['name'] ?? '用户$fromId'}';
    final peerAvatar =
        '${content['avatar'] ?? content['from_avatar'] ?? content['user_avatar'] ?? ''}'
            .trim();
    if (!mounted) return;
    try {
      final accepted = await _showIncomingCallDialog(
        callId: callId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        video: video,
      );
      if (!mounted) return;
      if (accepted == true) {
        if (CallRouteGuard.isClosed(callId)) {
          AppLogger.call('Home 来电接听前已结束 call=$callId');
          return;
        }
        AppLogger.call('Home 来电已接听，进入通话页 call=$callId');
        await _pushIncomingCallScreen(
          payload: payload,
          openKey: openKey,
          fromId: fromId,
          peerName: peerName,
          peerAvatar: peerAvatar,
          video: video,
        );
      } else if (accepted == false) {
        AppLogger.call('Home 来电已拒绝 call=$callId');
        await _rejectIncomingSignal(signal);
      } else {
        AppLogger.call('Home 来电已被远端结束 call=$callId');
      }
    } finally {
      openingCallIds.remove(openKey);
      CallRouteGuard.exit(openKey);
    }
  }

  Future<bool?> _showIncomingCallDialog({
    required String callId,
    required String peerName,
    required String peerAvatar,
    required bool video,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        incomingCallDialogContexts[callId] = dialogContext;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                color: BlinStyle.bgElevated,
                borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
                border: Border.all(color: BlinStyle.line),
                boxShadow: const [BlinStyle.cardShadow],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(imageUrl: peerAvatar, name: peerName, size: 84),
                  const SizedBox(height: 14),
                  Text(
                    peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video ? '邀请你视频通话' : '邀请你语音通话',
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _IncomingCallAction(
                        icon: Icons.call_end_rounded,
                        label: '拒绝',
                        color: Colors.redAccent,
                        onTap: () => Navigator.of(dialogContext).pop(false),
                      ),
                      _IncomingCallAction(
                        icon: Icons.call_rounded,
                        label: '接听',
                        color: BlinStyle.green,
                        onTap: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => incomingCallDialogContexts.remove(callId));
  }

  void _closeIncomingCallDialog(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    final dialogContext = incomingCallDialogContexts.remove(id);
    if (dialogContext == null) return;
    if (!dialogContext.mounted) return;
    final navigator = Navigator.of(dialogContext);
    if (navigator.canPop()) {
      navigator.pop(null);
    }
  }

  Future<void> _pushIncomingCallScreen({
    required Map<String, dynamic> payload,
    required String openKey,
    required int fromId,
    required String peerName,
    required String peerAvatar,
    required bool video,
  }) {
    return Navigator.of(context).push(
      callScreenRoute(
        CallScreen(
          session: widget.session,
          im: im,
          peerId: fromId,
          peerName: peerName,
          peerAvatar: peerAvatar,
          video: video,
          incoming: true,
          autoAccept: true,
          initialSignal: payload,
          initialSignals:
              pendingCallSignals.remove(openKey) ??
              const <Map<String, dynamic>>[],
        ),
      ),
    );
  }

  Future<void> _rejectIncomingSignal(CallSignal signal) async {
    final callId = signal.callId;
    if (callId.isEmpty || signal.fromUserId <= 0) return;
    CallRouteGuard.markClosed(callId);
    pendingCallSignals.remove(callId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final reject = CallSignal(
      callId: callId,
      signalId: '${callId}_${widget.session.id}_${now}_reject',
      action: 'reject',
      media: signal.media,
      fromUserId: widget.session.id,
      toUserId: signal.fromUserId,
      fromUid: ImService.uidForUser(widget.session.id),
      toUid: ImService.uidForUser(signal.fromUserId),
      deviceId: im.currentDeviceId ?? '',
      seq: now % 2000000000,
      timestamp: now,
      content: {
        'reason': 'user_reject',
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
      },
      raw: const <String, dynamic>{},
    );
    try {
      await const ApiService().sendImCallSignal(
        token: widget.session.token,
        toUserId: signal.fromUserId,
        payload: reject.toPayload(),
      );
    } catch (e) {
      AppLogger.warn(
        'HOME',
        '来电拒绝信令发送失败',
        data: {'call': callId, 'error': '$e'},
      );
    }
  }

  Future<void> _connect({bool force = false}) async {
    if (reconnecting || (!force && im.connecting)) return;
    final now = DateTime.now();
    if (!force && nextReconnectAt != null && now.isBefore(nextReconnectAt!)) {
      return;
    }
    reconnecting = true;
    connectStartedAt = now;
    reconnectTimer?.cancel();
    try {
      final info = await const ApiService().getImConnectInfo(
        widget.session.token,
      );
      await im.connect(
        info: info,
        myId: widget.session.id,
        waitUntilReady: true,
        readyTimeout: const Duration(seconds: 14),
      );
      reconnectFailures = 0;
      nextReconnectAt = null;
      connectStartedAt = null;
    } catch (e, st) {
      final snapshot = im.connectionSnapshot;
      AppLogger.error('HOME', 'IM连接失败', error: e, stack: st, data: snapshot);
      if (im.isConnectedForUser(widget.session.id) && !im.connecting) {
        reconnectFailures = 0;
        nextReconnectAt = null;
        im.connectionError = null;
        if (mounted) setState(() {});
        return;
      }
      try {
        await im.disconnect();
      } catch (_) {}
      im.connectionError = '网络暂不可用，正在重试';
      im.connecting = false;
      im.connected = false;
      if (mounted) setState(() {});
      scheduleReconnect();
    } finally {
      connectStartedAt = null;
      reconnecting = false;
    }
  }

  Future<void> _checkImHealth() async {
    if (!mounted || reconnecting) return;
    if (!appInForeground && im.connected) return;
    final now = DateTime.now();
    final last = lastHealthCheckAt;
    if (last != null && now.difference(last) < const Duration(seconds: 25)) {
      return;
    }
    lastHealthCheckAt = now;
    if (im.connecting) {
      final startedAt = connectStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) > const Duration(seconds: 12)) {
        try {
          await im.disconnect();
        } catch (_) {}
        await _connect(force: true);
      }
      return;
    }
    if (!im.connected || !im.isSocketConnected) {
      await _connect();
    }
  }

  void scheduleReconnect() {
    if (!mounted || reconnectTimer?.isActive == true || im.connecting) return;
    reconnectFailures = (reconnectFailures + 1).clamp(1, 6).toInt();
    final delay = Duration(seconds: 5 * reconnectFailures * reconnectFailures);
    nextReconnectAt = DateTime.now().add(delay);
    reconnectTimer = Timer(delay, () {
      if (mounted && !im.connected) unawaited(_connect());
    });
  }

  Future<void> _openPendingForegroundCalls() async {
    if (!appInForeground || pendingCallSignals.isEmpty) return;
    final entries = List<MapEntry<String, List<Map<String, dynamic>>>>.from(
      pendingCallSignals.entries,
    );
    for (final entry in entries) {
      if (!mounted || !appInForeground) return;
      final signals = entry.value;
      if (signals.isEmpty) continue;
      final parsedSignals = signals
          .map(CallSignal.tryParse)
          .whereType<CallSignal>()
          .toList();
      if (parsedSignals.isEmpty) {
        pendingCallSignals.remove(entry.key);
        handledIncomingCallIds.add(entry.key);
        continue;
      }
      if (_hasTerminalSignal(parsedSignals)) {
        CallRouteGuard.markClosed(entry.key);
        pendingCallSignals.remove(entry.key);
        handledIncomingCallIds.add(entry.key);
        continue;
      }
      final latest = parsedSignals.reversed.firstWhere(
        (item) => item.isInviteLike,
        orElse: () => parsedSignals.last,
      );
      if (!latest.isInviteLike || !_isFreshIncomingCallSignal(latest)) {
        AppLogger.call(
          'Home 跳过非来电/过期前台打开 call=${entry.key} action=${latest.action}',
        );
        pendingCallSignals.remove(entry.key);
        handledIncomingCallIds.add(entry.key);
        continue;
      }
      final latestPayload = latest.toPayload();
      if (CallRouteGuard.isClosed(entry.key) ||
          CallRouteGuard.isOutgoing(entry.key)) {
        pendingCallSignals.remove(entry.key);
        handledIncomingCallIds.add(entry.key);
        continue;
      }
      final contentRaw = latestPayload['content'];
      final content = contentRaw is Map
          ? Map<String, dynamic>.from(contentRaw)
          : <String, dynamic>{};
      final action = '${content['action'] ?? content['type'] ?? ''}'.trim();
      final terminal =
          action.contains('hangup') ||
          action.contains('reject') ||
          action.contains('busy') ||
          action.contains('timeout') ||
          action.contains('cancel') ||
          action.contains('end');
      if (terminal) {
        CallRouteGuard.markClosed(entry.key);
        pendingCallSignals.remove(entry.key);
        handledIncomingCallIds.add(entry.key);
        continue;
      }
      if (handledIncomingCallIds.contains(entry.key)) continue;
      await _openIncomingCall(latestPayload);
      break;
    }
  }

  Future<void> _recoverImOnResume() async {
    if (!mounted || reconnecting) return;
    if (!im.connected || !im.isSocketConnected) {
      await _connect();
      unawaited(_refreshUnreadCount());
      unawaited(_openPendingForegroundCalls());
    } else {
      unawaited(_refreshUnreadCount());
      unawaited(_openPendingForegroundCalls());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appInForeground = true;
      unawaited(_consumeLaunchPayload());
      unawaited(_recoverImOnResume());
      unawaited(
        _syncCallSignalsFromBackend().then(
          (_) => _openPendingForegroundCalls(),
        ),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      appInForeground = false;
      // 不在切后台时主动上报离线。后台保活由 IM 长连接/后续前台服务负责，
      // 主动置离线会让对端误判无法呼叫。
    }
  }

  int _rawUserId(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      final parsed = int.tryParse('${value ?? ''}');
      if (parsed != null && parsed > 0) return parsed;
    }
    final payload = row['payload'];
    if (payload is Map) {
      for (final key in keys) {
        final value = payload[key];
        final parsed = int.tryParse('${value ?? ''}');
        if (parsed != null && parsed > 0) return parsed;
      }
      final content = payload['content'];
      if (content is Map) {
        for (final key in keys) {
          final value = content[key];
          final parsed = int.tryParse('${value ?? ''}');
          if (parsed != null && parsed > 0) return parsed;
        }
      }
    }
    return 0;
  }

  bool _isSignalFromMe(Map<String, dynamic> row, CallSignal signal) {
    final rawFrom = _rawUserId(row, const ['from_user_id', 'sender_id']);
    return signal.fromUserId == widget.session.id ||
        rawFrom == widget.session.id ||
        signal.fromUid == ImService.uidForUser(widget.session.id) ||
        '${row['from_uid'] ?? ''}' == ImService.uidForUser(widget.session.id);
  }

  Future<void> _initCallSignalSync() async {
    if (!callWatermarkLoaded) {
      await _loadCallSignalWatermark();
      callWatermarkLoaded = true;
    }
    await _syncCallSignalsFromBackend();
  }

  Future<void> _syncCallSignalsFromBackend({
    bool openFreshIncoming = true,
    int? sinceIdOverride,
  }) async {
    if (syncingCallSignals) return;
    final now = DateTime.now();
    if (sinceIdOverride == null) {
      final last = lastCallSignalSyncAt;
      final minGap = callSignalSyncFailures > 0
          ? Duration(seconds: 30 * callSignalSyncFailures.clamp(1, 4).toInt())
          : const Duration(seconds: 20);
      if (last != null && now.difference(last) < minGap) return;
      lastCallSignalSyncAt = now;
    }
    syncingCallSignals = true;
    try {
      final sinceId = sinceIdOverride ?? lastCallSignalId;
      AppLogger.call('Home 开始后端补偿 since=$sinceId');
      final rows = await const ApiService().getImCallSignals(
        token: widget.session.token,
        sinceId: sinceId,
        limit: 50,
      );
      callSignalSyncFailures = 0;
      AppLogger.call('Home 后端补偿返回 rows=${rows.length}');
      final terminalCallIds = <String>{};
      for (final row in rows) {
        final id = int.tryParse('${row['id'] ?? 0}') ?? 0;
        if (sinceIdOverride == null && id > lastCallSignalId) {
          lastCallSignalId = id;
        }
        final signal = CallSignal.tryParse(row);
        if (signal == null) continue;
        if (_isGroupCallInternalSignal(signal)) continue;
        final callId = signal.callId;
        final terminal = signal.isTerminal;
        if (terminal && callId.isNotEmpty) {
          terminalCallIds.add(callId);
          CallRouteGuard.markClosed(callId);
        }
      }
      for (final callId in terminalCallIds) {
        notifiedCallIds.add(callId);
        openingCallIds.remove(callId);
        pendingCallSignals.remove(callId);
        handledIncomingCallIds.add(callId);
        _closeIncomingCallDialog(callId);
      }
      for (final row in rows) {
        final signal = CallSignal.tryParse(row);
        if (signal == null) continue;
        if (_isGroupCallInternalSignal(signal)) continue;
        final payload = signal.toPayload();
        final callId = signal.callId;
        if (callId.isNotEmpty &&
            (terminalCallIds.contains(callId) ||
                CallRouteGuard.isClosed(callId) ||
                CallRouteGuard.isOutgoing(callId))) {
          continue;
        }
        if (!signal.isInviteLike) continue;
        final fromId = signal.fromUserId;
        final toId = signal.toUserId > 0
            ? signal.toUserId
            : _rawUserId(row, const ['to_user_id', 'receiver_id']);
        if (fromId <= 0 || _isSignalFromMe(row, signal)) continue;
        if (toId != widget.session.id) continue;
        if (CallRouteGuard.hasActiveCall) {
          if (CallRouteGuard.isActiveCall(callId)) {
            AppLogger.call('Home 后端补偿已忽略当前通话重复来电信令 call=$callId');
            continue;
          }
          unawaited(_sendBusySignal(signal));
          continue;
        }
        if (callId.isNotEmpty && handledIncomingCallIds.contains(callId)) {
          continue;
        }
        if (!openFreshIncoming) continue;
        if (!_isFreshIncomingCallSignal(signal, raw: row)) {
          AppLogger.call(
            'Home 后端补偿忽略过期/无效来电 call=$callId action=${signal.action}',
          );
          handledIncomingCallIds.add(callId);
          continue;
        }
        _queueIncomingCall(
          payload,
          notify: !appInForeground,
          openNow: appInForeground,
        );
      }
    } catch (e, st) {
      callSignalSyncFailures = (callSignalSyncFailures + 1).clamp(1, 4).toInt();
      AppLogger.error('HOME', '后端补偿失败', error: e, stack: st);
    } finally {
      if (sinceIdOverride == null && lastCallSignalId > 0) {
        unawaited(_saveCallSignalWatermark());
      }
      syncingCallSignals = false;
    }
  }

  Future<void> _refreshUnreadCount() async {
    if (refreshingUnreadCount) return;
    final now = DateTime.now();
    final last = lastUnreadRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    refreshingUnreadCount = true;
    lastUnreadRefreshAt = now;
    try {
      final list = await const ApiService().getMessageList(
        widget.session.token,
      );
      var total = list.fold<int>(0, (sum, item) => sum + item.unread);
      try {
        final groups = await const ApiService().getImGroups(
          widget.session.token,
        );
        total += groups.fold<int>(
          0,
          (sum, group) => sum + _groupUnreadFromRaw(group),
        );
      } catch (_) {}
      try {
        final requests = await const ApiService().getFriendRequests(
          widget.session.token,
          currentUserId: widget.session.id,
        );
        total += requests.where((item) => item.pending).length;
      } catch (_) {}
      if (mounted && total != unreadCount) setState(() => unreadCount = total);
    } catch (_) {
      // 商业界面不暴露未读数量同步失败，保留上一次稳定值。
    } finally {
      refreshingUnreadCount = false;
    }
  }

  Future<void> _logout() async {
    await alerts.stopKeepAlive();
    await im.disconnect(logout: true);
    await const ApiService().reportImOffline(token: widget.session.token);
    await AuthStore().clear();
    widget.onLogout();
  }

  void _selectTab(int tabIndex) {
    final next = tabIndex.clamp(0, 2).toInt();
    setState(() {
      if (index == 0 || next == 0) chatListResetSwipeToken++;
      index = next;
      visitedTabs.add(next);
    });
  }

  @override
  void dispose() {
    imSub?.cancel();
    friendSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    reconnectTimer?.cancel();
    callSignalSyncTimer?.cancel();
    healthTimer?.cancel();
    messageSub?.cancel();
    callSub?.cancel();
    unreadTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleScreenshotKeyEvent);
    unawaited(alerts.stopKeepAlive());
    im.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (pendingChatTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_flushPendingChatTarget());
      });
    }
    final selectedIndex = index.clamp(0, 2).toInt();
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final pages = <Widget>[
      _LazyTab(
        loaded: visitedTabs.contains(0),
        child: ChatListScreen(
          session: widget.session,
          im: im,
          voiceMessageEnabled: voiceMessageEnabled,
          screenshotNoticeEnabled: screenshotNoticeEnabled,
          navigator: chatListNavigator,
          resetSwipeToken: chatListResetSwipeToken,
          onUnreadChanged: (count) {
            if (mounted && unreadCount != count) {
              setState(() => unreadCount = count);
            }
          },
        ),
      ),
      _LazyTab(
        loaded: visitedTabs.contains(1),
        child: ContactsScreen(
          session: widget.session,
          im: im,
          voiceMessageEnabled: voiceMessageEnabled,
          screenshotNoticeEnabled: screenshotNoticeEnabled,
        ),
      ),
      _LazyTab(
        loaded: visitedTabs.contains(2),
        child: _MineTab(
          session: widget.session,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onSessionChanged: widget.onSessionChanged,
          onLogout: _logout,
          active: selectedIndex == 2,
        ),
      ),
    ];
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: isWide
          ? SafeArea(
              child: Row(
                children: [
                  _DesktopNavRail(
                    selectedIndex: selectedIndex,
                    unreadCount: unreadCount,
                    onSelected: _selectTab,
                  ),
                  Expanded(
                    child: PageBackdrop(
                      child: IndexedStack(
                        index: selectedIndex,
                        children: pages,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : PageBackdrop(
              child: IndexedStack(index: selectedIndex, children: pages),
            ),
      bottomNavigationBar: isWide
          ? null
          : _MainBottomNav(
              selectedIndex: selectedIndex,
              unreadCount: unreadCount,
              onSelected: _selectTab,
            ),
    );
  }
}

class _MainNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badge;

  const _MainNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge = 0,
  });
}

class _MainBottomNav extends StatelessWidget {
  final int selectedIndex;
  final int unreadCount;
  final ValueChanged<int> onSelected;

  const _MainBottomNav({
    required this.selectedIndex,
    required this.unreadCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final items = [
      _MainNavItem(
        label: '消息',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        badge: unreadCount,
      ),
      const _MainNavItem(
        label: '联系人',
        icon: Icons.contacts_outlined,
        activeIcon: Icons.contacts_rounded,
      ),
      const _MainNavItem(
        label: '我的',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, bottom > 0 ? 8 : 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: BlinStyle.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: BlinStyle.hairline(context, .62).color),
            boxShadow: const [BlinStyle.cardShadow],
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _MainBottomNavButton(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainBottomNavButton extends StatelessWidget {
  final _MainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _MainBottomNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? BlinStyle.primary : BlinStyle.textSecondary(context);
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? BlinStyle.primary.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: item.badge > 0,
                  label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    height: 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavRail extends StatelessWidget {
  final int selectedIndex;
  final int unreadCount;
  final ValueChanged<int> onSelected;

  const _DesktopNavRail({
    required this.selectedIndex,
    required this.unreadCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _MainNavItem(
        label: '消息',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        badge: unreadCount,
      ),
      const _MainNavItem(
        label: '联系人',
        icon: Icons.contacts_outlined,
        activeIcon: Icons.contacts_rounded,
      ),
      const _MainNavItem(
        label: '我的',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
      ),
    ];
    return Container(
      width: 104,
      margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: BlinStyle.hairline(context, .62).color),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      child: Column(
        children: [
          const BrandMark(size: 46),
          const SizedBox(height: 22),
          for (var i = 0; i < items.length; i++) ...[
            _DesktopNavButton(
              item: items[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
          const Spacer(),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: BlinStyle.primary.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavButton extends StatelessWidget {
  final _MainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? BlinStyle.primary : BlinStyle.textSecondary(context);
    return Tooltip(
      message: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 70,
            width: double.infinity,
            decoration: BoxDecoration(
              color: selected
                  ? BlinStyle.primary.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: item.badge > 0,
                  label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LazyTab extends StatelessWidget {
  final bool loaded;
  final Widget child;
  const _LazyTab({required this.loaded, required this.child});

  @override
  Widget build(BuildContext context) =>
      loaded ? child : const SizedBox.expand();
}

class _MineTab extends StatefulWidget {
  final UserSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<UserSession> onSessionChanged;
  final Future<void> Function() onLogout;
  final bool active;
  const _MineTab({
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onSessionChanged,
    required this.onLogout,
    required this.active,
  });

  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> with WidgetsBindingObserver {
  final api = const ApiService();
  UserProfileSummary profile = const UserProfileSummary();
  AppUserInfoConfig userInfoConfig = const AppUserInfoConfig(
    showUserId: false,
    usernameChangeEnabled: true,
    usernameChangeIntervalDays: 30,
    profileAuditEnabled: false,
  );
  bool loadingProfile = true;
  bool hasLoadedProfile = false;
  String? profileError;
  Timer? profileSyncTimer;
  StreamSubscription? profileEventSub;
  bool syncingProfile = false;
  DateTime? lastProfileSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadUserInfoConfig());
    loadProfile();
    profileEventSub = _HomeScreenState.profileEventStream.stream.listen((
      event,
    ) {
      final action = '${event['action'] ?? event['event'] ?? ''}';
      if (!widget.active &&
          action != 'profile' &&
          action != 'wallet' &&
          action != 'notification') {
        return;
      }
      unawaited(loadProfile(silent: true));
    });
    profileSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && widget.active) unawaited(loadProfile(silent: true));
    });
  }

  Future<void> loadUserInfoConfig() async {
    try {
      final config = await api.getUserInfoConfig();
      if (mounted) setState(() => userInfoConfig = config);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _MineTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      unawaited(loadProfile(silent: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(loadProfile(silent: true));
    }
  }

  @override
  void dispose() {
    profileSyncTimer?.cancel();
    profileEventSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _sameProfile(UserProfileSummary a, UserProfileSummary b) =>
      a.username == b.username &&
      a.nickname == b.nickname &&
      a.avatar == b.avatar &&
      a.background == b.background &&
      a.fans == b.fans &&
      a.follows == b.follows &&
      a.points == b.points &&
      a.coins == b.coins &&
      a.vip == b.vip &&
      a.level == b.level &&
      a.posts == b.posts &&
      a.comments == b.comments &&
      a.likes == b.likes &&
      a.views == b.views;

  Future<void> loadProfile({bool silent = false}) async {
    if (silent && lastProfileSync != null) {
      final elapsed = DateTime.now().difference(lastProfileSync!);
      if (elapsed < const Duration(seconds: 8)) return;
    }
    if (syncingProfile) return;
    syncingProfile = true;
    if (!silent) {
      setState(() {
        loadingProfile = !hasLoadedProfile;
        profileError = null;
      });
    }
    try {
      final r = await api.getUserOtherInformation(widget.session.token);
      if (mounted) {
        final changed = !_sameProfile(profile, r);
        if (changed || !hasLoadedProfile || profileError != null) {
          setState(() {
            profile = r;
            hasLoadedProfile = true;
            profileError = null;
            lastProfileSync = DateTime.now();
          });
        } else {
          lastProfileSync = DateTime.now();
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => profileError = '$e');
    } finally {
      syncingProfile = false;
      if (mounted && !silent) setState(() => loadingProfile = false);
    }
  }

  Future<void> signIn() async {
    try {
      final msg = await api.userSignIn(widget.session.token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: (_) =>
            _SignInRewardDialog(message: msg.isEmpty ? '今日奖励已到账' : msg),
      );
      await loadProfile();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException && e.message.trim().isNotEmpty
          ? e.message.trim()
          : '今日已签到';
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: (_) => _SignInRewardDialog(message: message),
      );
      await loadProfile();
    }
  }

  void openFeature(_ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ApiFeatureScreen(session: widget.session, feature: feature),
      ),
    );
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsScreen(
          session: widget.session,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLogout: widget.onLogout,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(loadProfile(silent: true));
    });
  }

  void openWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _WalletScreen(session: widget.session, initialProfile: profile),
      ),
    ).then((_) {
      if (mounted) unawaited(loadProfile(silent: true));
    });
  }

  void openMyProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MyProfileScreen(
          session: widget.session,
          initialProfile: profile,
          showUserId: userInfoConfig.showUserId,
          userInfoConfig: userInfoConfig,
          onSessionChanged: widget.onSessionChanged,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(loadProfile(silent: true));
    });
  }

  void openMyQr() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _MyQrScreen(session: widget.session)),
    );
  }

  Future<void> openEmojiStore() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EmojiStoreScreen(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isNotEmpty
        ? profile.nickname
        : (widget.session.nickname ?? '');
    final displayName = nickname.isNotEmpty
        ? nickname
        : widget.session.username;
    final avatar = profile.avatar.isNotEmpty
        ? profile.avatar
        : widget.session.avatar;
    final menuItems = <_MineMenuItem>[
      _MineMenuItem('签到', Icons.task_alt_rounded, () => unawaited(signIn())),
      _MineMenuItem('钱包', Icons.account_balance_wallet_outlined, openWallet),
      _MineMenuItem(
        '账单',
        Icons.receipt_long_rounded,
        () => openFeature(
          const _ApiFeature(
            '账单明细',
            Icons.receipt_long_rounded,
            '/get_user_billing',
          ),
        ),
      ),
      _MineMenuItem(
        '订单',
        Icons.shopping_bag_outlined,
        () => openFeature(
          const _ApiFeature(
            '订单记录',
            Icons.shopping_bag_outlined,
            '/get_order_record',
          ),
        ),
      ),
      _MineMenuItem(
        '商品中心',
        Icons.storefront_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ProductCenterScreen(session: widget.session),
          ),
        ),
      ),
      _MineMenuItem(
        '表情商店',
        Icons.emoji_emotions_outlined,
        () => unawaited(openEmojiStore()),
      ),
      _MineMenuItem('设置', Icons.settings_outlined, openSettings),
    ];
    return Column(
      children: [
        Expanded(
          child: BlinRefresh(
            onRefresh: () => loadProfile(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
              children: [
                _MineNativeHeader(
                  displayName: displayName,
                  avatar: avatar,
                  session: widget.session,
                  profile: profile,
                  showUserId: userInfoConfig.showUserId,
                  loading: loadingProfile && !hasLoadedProfile,
                  onProfile: openMyProfile,
                  onQr: openMyQr,
                ),
                if (profileError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      '个人资料暂时无法更新，请稍后再试',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _MineQuickActionGrid(items: menuItems.take(4).toList()),
                const SizedBox(height: 16),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final item in menuItems.skip(4))
                        _MineNativeMenuRow(item: item),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MineMenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  const _MineMenuItem(this.title, this.icon, this.onTap);
}

class _MineNativeHeader extends StatelessWidget {
  final String displayName;
  final String avatar;
  final UserSession session;
  final UserProfileSummary profile;
  final bool showUserId;
  final bool loading;
  final VoidCallback onProfile;
  final VoidCallback onQr;
  const _MineNativeHeader({
    required this.displayName,
    required this.avatar,
    required this.session,
    required this.profile,
    required this.showUserId,
    required this.loading,
    required this.onProfile,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
                child: Row(
                  children: [
                    AppAvatar(imageUrl: avatar, name: displayName, size: 70),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loading ? '加载中' : displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            showUserId
                                ? 'ID ${session.id}'
                                : '@${profile.username.isNotEmpty ? profile.username : session.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _MiniMetric(label: '动态', value: profile.posts),
                              const SizedBox(width: 14),
                              _MiniMetric(label: '获赞', value: profile.likes),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ShellAction(
              icon: Icons.qr_code_2_rounded,
              onTap: onQr,
              tooltip: '我的二维码',
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(
          color: BlinStyle.textPrimary(context),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _MineQuickActionGrid extends StatelessWidget {
  final List<_MineMenuItem> items;
  const _MineQuickActionGrid({required this.items});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: _MineQuickAction(item: item),
            ),
        ],
      );
    },
  );
}

class _MineQuickAction extends StatelessWidget {
  final _MineMenuItem item;
  const _MineQuickAction({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 86),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: BlinStyle.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BlinStyle.hairline(context, .58).color),
            boxShadow: const [BlinStyle.flatShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NativeIconBox(
                icon: item.icon,
                color: BlinStyle.primary,
                size: 40,
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineNativeMenuRow extends StatelessWidget {
  final _MineMenuItem item;
  const _MineNativeMenuRow({required this.item});

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: NativeIconBox(icon: item.icon, color: BlinStyle.primary, size: 38),
    title: item.title,
    onTap: item.onTap,
    minHeight: 60,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    trailing: const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
  );
}

class _MyProfileScreen extends StatefulWidget {
  final UserSession session;
  final UserProfileSummary initialProfile;
  final bool showUserId;
  final AppUserInfoConfig userInfoConfig;
  final ValueChanged<UserSession> onSessionChanged;
  const _MyProfileScreen({
    required this.session,
    required this.initialProfile,
    required this.showUserId,
    required this.userInfoConfig,
    required this.onSessionChanged,
  });

  @override
  State<_MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<_MyProfileScreen> {
  final api = const ApiService();
  late UserProfileSummary profile = widget.initialProfile;
  late UserSession session = widget.session;
  MomentProfileStats momentStats = const MomentProfileStats();
  bool loading = false;
  bool uploadingAvatar = false;
  bool uploadingBackground = false;
  bool savingProfile = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait<Object>([
        api.getUserOtherInformation(session.token),
        api
            .getMyMomentStats(token: session.token, userId: session.id)
            .catchError((_) => const MomentProfileStats()),
      ]);
      if (mounted) {
        setState(() {
          profile = result[0] as UserProfileSummary;
          momentStats = result[1] as MomentProfileStats;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get _displayName {
    if (profile.nickname.trim().isNotEmpty) return profile.nickname.trim();
    if (session.nickname?.trim().isNotEmpty ?? false) {
      return session.nickname!.trim();
    }
    return session.username;
  }

  String get _username {
    if (profile.username.trim().isNotEmpty) return profile.username.trim();
    return session.username;
  }

  String get _avatar {
    if (profile.avatar.trim().isNotEmpty) return profile.avatar.trim();
    return session.avatar;
  }

  String _uploadedUrl(Map<String, dynamic> data) {
    for (final key in const [
      'url',
      'path',
      'file_url',
      'image_url',
      'image',
      'avatar',
      'background',
      'src',
      'oss_path',
    ]) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return '';
  }

  bool _textIndicatesProfileReview(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty || text == 'null') return false;
    return text.contains('等待审核') ||
        text.contains('提交审核') ||
        text.contains('已提交审核') ||
        text.contains('待审核') ||
        text.contains('待审') ||
        text.contains('审核中') ||
        text.contains('pending') ||
        text.contains('review');
  }

  bool _profileResultNeedsReview(Object? value) {
    if (value == null) return false;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = '${entry.key}'.toLowerCase();
        final item = entry.value;
        if (item is bool &&
            item &&
            (key.contains('need_review') ||
                key.contains('pending_review') ||
                key.contains('require_review'))) {
          return true;
        }
        if (_profileResultNeedsReview(item)) {
          return true;
        }
      }
      return false;
    }
    if (value is Iterable) {
      return value.any(_profileResultNeedsReview);
    }
    return _textIndicatesProfileReview('$value');
  }

  Future<List<int>> _readPickedImageBytes(PlatformFile file) async {
    final memoryBytes = file.bytes;
    if (memoryBytes != null && memoryBytes.isNotEmpty) return memoryBytes;
    final stream = file.readStream;
    if (stream != null) {
      final chunks = await stream.toList();
      final size = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
      if (size > 0) {
        final bytes = Uint8List(size);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        return bytes;
      }
    }
    throw ApiException('图片文件为空，请重新选择');
  }

  Future<void> _pickAndUploadProfileImage({
    required String title,
    required String path,
    required bool avatar,
  }) async {
    if (uploadingAvatar || uploadingBackground) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
      withReadStream: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file == null) return;
    setState(() {
      if (avatar) {
        uploadingAvatar = true;
      } else {
        uploadingBackground = true;
      }
    });
    try {
      final bytes = await _readPickedImageBytes(file);
      final uploaded = await api.uploadProfileImage(
        token: session.token,
        path: path,
        bytes: bytes,
        filename: file.name,
      );
      final url = _uploadedUrl(uploaded);
      final needsReview =
          widget.userInfoConfig.profileAuditEnabled ||
          _profileResultNeedsReview(uploaded);
      await load();
      if (!needsReview && avatar && url.isNotEmpty) {
        final next = session.copyWith(avatar: url);
        session = next;
        widget.onSessionChanged(next);
        unawaited(AuthStore().save(next));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(needsReview ? '$title已提交审核，通过后展示' : '$title已更新'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          if (avatar) {
            uploadingAvatar = false;
          } else {
            uploadingBackground = false;
          }
        });
      }
    }
  }

  Future<void> _openProfileImageAction({
    required String title,
    required IconData icon,
    required String path,
    required bool avatar,
  }) async {
    final busy = avatar ? uploadingAvatar : uploadingBackground;
    final action = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeListRow(
              leading: NativeIconBox(
                icon: icon,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '从本机选择图片',
              subtitle: busy ? '正在上传图片' : '选择图片后自动上传并保存',
              minHeight: 64,
              onTap: busy ? null : () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action != true) return;
    await _pickAndUploadProfileImage(title: title, path: path, avatar: avatar);
  }

  Future<void> _openEditProfileSheet() async {
    final nicknameController = TextEditingController(text: _displayName);
    final usernameController = TextEditingController(text: _username);
    String? validationText;
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) {
        final bottom = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('编辑个人资料', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text(
                    '用户名只能使用 4-8 位英文或数字。',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    enabled: widget.userInfoConfig.usernameChangeEnabled,
                    maxLength: 8,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '用户名',
                      hintText: '4-8 位英文或数字',
                      helperText: widget.userInfoConfig.usernameChangeEnabled
                          ? '保存后将用于登录和个人展示'
                          : '暂时不能修改用户名',
                      errorText: validationText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nicknameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '输入新的昵称',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: savingProfile
                              ? null
                              : () {
                                  final username = usernameController.text
                                      .trim();
                                  final nickname = nicknameController.text
                                      .trim();
                                  final usernameChanged = username != _username;
                                  if (usernameChanged) {
                                    if (!widget
                                        .userInfoConfig
                                        .usernameChangeEnabled) {
                                      setSheetState(() {
                                        validationText = '暂时不能修改用户名';
                                      });
                                      return;
                                    }
                                    if (!RegExp(
                                      r'^[A-Za-z0-9]{4,8}$',
                                    ).hasMatch(username)) {
                                      setSheetState(() {
                                        validationText = '用户名只能使用 4-8 位英文或数字';
                                      });
                                      return;
                                    }
                                  }
                                  if (nickname.isEmpty) {
                                    setSheetState(() {
                                      validationText = '昵称不能为空';
                                    });
                                    return;
                                  }
                                  Navigator.pop(sheetContext, {
                                    'username': username,
                                    'nickname': nickname,
                                  });
                                },
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    nicknameController.dispose();
    usernameController.dispose();
    if (result == null || !mounted) return;
    await _saveProfileText(
      username: result['username'] ?? '',
      nickname: result['nickname'] ?? '',
    );
  }

  Future<void> _saveProfileText({
    required String username,
    required String nickname,
  }) async {
    if (savingProfile) return;
    setState(() => savingProfile = true);
    try {
      var nextSession = session;
      if (username != _username) {
        nextSession = await api.changeUsername(
          session: session,
          username: username,
        );
      }
      Object? nicknameResult;
      final nicknameChanged = nickname != _displayName;
      if (nickname != _displayName) {
        nicknameResult = await api.getApiData(
          session.token,
          '/modify_user_information',
          extra: {'nickname': nickname},
        );
        final needsReview =
            widget.userInfoConfig.profileAuditEnabled ||
            _profileResultNeedsReview(nicknameResult);
        if (!needsReview) {
          nextSession = nextSession.copyWith(nickname: nickname);
        }
      }
      session = nextSession;
      widget.onSessionChanged(nextSession);
      unawaited(AuthStore().save(nextSession));
      await load();
      if (!mounted) return;
      final needsReview =
          nicknameChanged &&
          (widget.userInfoConfig.profileAuditEnabled ||
              _profileResultNeedsReview(nicknameResult));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(needsReview ? '资料已提交审核，通过后展示' : '个人资料已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('资料保存失败：$e')));
    } finally {
      if (mounted) setState(() => savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '我的主页',
            subtitle: '个人资料、资产和账号信息',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              ShellAction(
                icon: Icons.refresh_rounded,
                onTap: loading ? null : () => unawaited(load()),
                tooltip: '刷新',
              ),
            ],
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: load,
              child: ModuleContent(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _MyProfileHero(
                      name: _displayName,
                      username: _username,
                      avatar: _avatar,
                      background: profile.background,
                      showUserId: widget.showUserId,
                      userId: session.id,
                      vip: profile.vip,
                      level: profile.level,
                      loading: loading,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      SoftCard(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: .08),
                        child: Text(
                          '资料暂时无法更新：$error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: BlinStyle.moduleGap),
                    _MyProfileStats(profile: profile, momentStats: momentStats),
                    const SizedBox(height: BlinStyle.moduleGap),
                    _ProfileSection(
                      title: '账号资料',
                      children: [
                        NativeListRow(
                          leading: const NativeIconBox(
                            icon: Icons.alternate_email_rounded,
                            color: BlinStyle.primary,
                            size: 40,
                          ),
                          title: '用户名',
                          subtitle: '@$_username',
                          minHeight: 64,
                        ),
                        if (widget.showUserId)
                          NativeListRow(
                            leading: const NativeIconBox(
                              icon: Icons.tag_rounded,
                              color: BlinStyle.subtle,
                              size: 40,
                            ),
                            title: '用户 ID',
                            subtitle: '${widget.session.id}',
                            minHeight: 64,
                          ),
                        NativeListRow(
                          leading: const NativeIconBox(
                            icon: Icons.workspace_premium_outlined,
                            color: BlinStyle.warning,
                            size: 40,
                          ),
                          title: '会员与等级',
                          subtitle:
                              '${profile.isVip ? profile.vip : '普通用户'} · Lv ${profile.level}',
                          minHeight: 64,
                        ),
                      ],
                    ),
                    const SizedBox(height: BlinStyle.moduleGap),
                    _ProfileSection(
                      title: '主页操作',
                      children: [
                        NativeListRow(
                          leading: const NativeIconBox(
                            icon: Icons.edit_note_rounded,
                            color: BlinStyle.primary,
                            size: 40,
                          ),
                          title: '编辑个人资料',
                          subtitle: '用户名和昵称',
                          minHeight: 68,
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: BlinStyle.subtle,
                          ),
                          onTap: savingProfile
                              ? null
                              : () => unawaited(_openEditProfileSheet()),
                        ),
                        NativeListRow(
                          leading: const NativeIconBox(
                            icon: Icons.add_a_photo_outlined,
                            color: BlinStyle.primary,
                            size: 40,
                          ),
                          title: '更换头像',
                          subtitle: uploadingAvatar ? '头像上传中' : '选择本机图片上传',
                          minHeight: 68,
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: BlinStyle.subtle,
                          ),
                          onTap: () => _openProfileImageAction(
                            title: '上传头像',
                            icon: Icons.add_a_photo_outlined,
                            path: '/upload_avatar',
                            avatar: true,
                          ),
                        ),
                        NativeListRow(
                          leading: const NativeIconBox(
                            icon: Icons.image_outlined,
                            color: BlinStyle.primary,
                            size: 40,
                          ),
                          title: '主页背景',
                          subtitle: uploadingBackground
                              ? '背景上传中'
                              : profile.background.trim().isEmpty
                              ? '未设置背景图'
                              : '已设置背景图',
                          minHeight: 68,
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: BlinStyle.subtle,
                          ),
                          onTap: () => _openProfileImageAction(
                            title: '上传背景',
                            icon: Icons.image_outlined,
                            path: '/upload_background',
                            avatar: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MyProfileHero extends StatelessWidget {
  final String name;
  final String username;
  final String avatar;
  final String background;
  final bool showUserId;
  final int userId;
  final String vip;
  final String level;
  final bool loading;
  const _MyProfileHero({
    required this.name,
    required this.username,
    required this.avatar,
    required this.background,
    required this.showUserId,
    required this.userId,
    required this.vip,
    required this.level,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBackground = resolveMediaUrl(background);
    final hasBackground = resolvedBackground.isNotEmpty;
    return SoftCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 132,
            width: double.infinity,
            child: hasBackground
                ? Image.network(
                    resolvedBackground,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (_, _, _) => const _ProfileCoverFallback(),
                  )
                : const _ProfileCoverFallback(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: BlinStyle.surface(context),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: BlinStyle.surface(context),
                            width: 4,
                          ),
                        ),
                        child: AppAvatar(
                          imageUrl: avatar,
                          name: name,
                          size: 80,
                        ),
                      ),
                      const Spacer(),
                      if (loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        showUserId ? 'ID $userId · @$username' : '@$username',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ProfileBadge(
                            icon: Icons.workspace_premium_outlined,
                            label: vip.trim().isEmpty ? '普通用户' : vip,
                          ),
                          _ProfileBadge(
                            icon: Icons.bolt_outlined,
                            label: 'Lv $level',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCoverFallback extends StatelessWidget {
  const _ProfileCoverFallback();

  @override
  Widget build(BuildContext context) => Container(
    color: BlinStyle.primarySoft,
    child: Stack(
      children: [
        Positioned(
          left: 18,
          top: 18,
          child: NativeIconBox(
            icon: Icons.person_pin_circle_outlined,
            color: BlinStyle.primary,
            size: 52,
          ),
        ),
        Positioned(
          right: 18,
          bottom: 16,
          child: Text(
            'BLINLIN',
            style: TextStyle(
              color: BlinStyle.primary.withValues(alpha: .38),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ProfileBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: BlinStyle.iconSurface(context),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: BlinStyle.hairline(context, .62).color),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: BlinStyle.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: BlinStyle.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _MyProfileStats extends StatelessWidget {
  final UserProfileSummary profile;
  final MomentProfileStats momentStats;
  const _MyProfileStats({required this.profile, required this.momentStats});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ProfileMetric(width: itemWidth, label: '余额', value: profile.coins),
            _ProfileMetric(
              width: itemWidth,
              label: '积分',
              value: profile.points,
            ),
            _ProfileMetric(
              width: itemWidth,
              label: '动态',
              value: '${momentStats.posts}',
            ),
            _ProfileMetric(
              width: itemWidth,
              label: '点赞',
              value: '${momentStats.likes}',
            ),
          ],
        );
      },
    ),
  );
}

class _ProfileMetric extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  const _ProfileMetric({
    required this.width,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        border: Border.all(color: BlinStyle.hairline(context, .62).color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.trim().isEmpty ? '0' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: BlinStyle.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ProfileSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...children,
      ],
    ),
  );
}

class _WalletScreen extends StatefulWidget {
  final UserSession session;
  final UserProfileSummary initialProfile;
  const _WalletScreen({required this.session, required this.initialProfile});

  @override
  State<_WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<_WalletScreen> {
  final api = const ApiService();
  late UserProfileSummary profile = widget.initialProfile;
  PaymentPasswordStatus? payStatus;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final next = await api.getUserOtherInformation(widget.session.token);
      PaymentPasswordStatus? nextPayStatus;
      try {
        nextPayStatus = await api.getPaymentPasswordStatus(
          widget.session.token,
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          profile = next;
          payStatus = nextPayStatus ?? payStatus;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void openBilling() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ApiFeatureScreen(
          session: widget.session,
          feature: const _ApiFeature(
            '账单明细',
            Icons.receipt_long_rounded,
            '/get_user_billing',
          ),
        ),
      ),
    );
  }

  Future<void> openPaymentPassword() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentPasswordScreen(token: widget.session.token),
      ),
    );
    if (mounted) unawaited(load());
  }

  Future<void> openCardRedeem() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CardRedeemScreen(session: widget.session),
      ),
    );
    if (changed == true && mounted) unawaited(load());
  }

  Widget _walletMetric({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          NativeIconBox(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: BlinStyle.subtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BlinStyle.textPrimary(context),
                    fontSize: 19,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletLocked = payStatus?.walletLocked == true;
    final lockSubtitle = walletLocked
        ? '钱包已锁定，请找回支付密码'
        : payStatus?.hasPassword == true
        ? '已开启支付保护'
        : '发红包和转账前需要设置';
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '钱包',
              subtitle: loading ? '正在同步资产' : '资产、交易与支付安全',
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              actions: [
                IconButton(
                  onPressed: loading ? null : load,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: '刷新',
                ),
              ],
            ),
            Expanded(
              child: ModuleContent(
                child: BlinRefresh(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
                    children: [
                      _CommerceHeroCard(
                        icon: Icons.account_balance_wallet_rounded,
                        accent: BlinStyle.primary,
                        label: '可用余额',
                        title: '¥${profile.coins}',
                        subtitle: '转账、红包、购物和退款都会同步到账单',
                        chips: [
                          _ProductMetaChip(
                            label: '积分 ${profile.points}',
                            color: BlinStyle.warning,
                            icon: Icons.stars_rounded,
                          ),
                          _ProductMetaChip(
                            label: walletLocked ? '钱包锁定' : '支付保护',
                            color: walletLocked
                                ? BlinStyle.danger
                                : BlinStyle.success,
                            icon: walletLocked
                                ? Icons.lock_rounded
                                : Icons.verified_user_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoColumns = constraints.maxWidth >= 620;
                          final width = twoColumns
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: width,
                                child: _walletMetric(
                                  icon: Icons.stars_rounded,
                                  color: BlinStyle.warning,
                                  label: '积分',
                                  value: profile.points,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _walletMetric(
                                  icon: walletLocked
                                      ? Icons.lock_rounded
                                      : Icons.verified_outlined,
                                  color: walletLocked
                                      ? BlinStyle.danger
                                      : BlinStyle.success,
                                  label: '账户状态',
                                  value: walletLocked ? '已锁定' : '正常',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SlimSectionHeader(title: '常用操作'),
                      const SizedBox(height: 10),
                      SoftCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            NativeListRow(
                              leading: const NativeIconBox(
                                icon: Icons.receipt_long_rounded,
                                color: BlinStyle.primary,
                                size: 42,
                              ),
                              title: '账单明细',
                              subtitle: '查看余额和积分变动',
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: BlinStyle.subtle,
                              ),
                              onTap: openBilling,
                            ),
                            const Divider(height: 1),
                            NativeListRow(
                              leading: const NativeIconBox(
                                icon: Icons.card_giftcard_rounded,
                                color: BlinStyle.success,
                                size: 42,
                              ),
                              title: '卡密兑换',
                              subtitle: '兑换金币、积分或会员权益',
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: BlinStyle.subtle,
                              ),
                              onTap: openCardRedeem,
                            ),
                            const Divider(height: 1),
                            NativeListRow(
                              leading: NativeIconBox(
                                icon: walletLocked
                                    ? Icons.lock_rounded
                                    : Icons.lock_outline_rounded,
                                color: walletLocked
                                    ? BlinStyle.danger
                                    : BlinStyle.primary,
                                size: 42,
                              ),
                              title: '支付密码',
                              subtitle: lockSubtitle,
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: BlinStyle.subtle,
                              ),
                              onTap: openPaymentPassword,
                            ),
                            const Divider(height: 1),
                            NativeListRow(
                              leading: const NativeIconBox(
                                icon: Icons.swap_horiz_rounded,
                                color: BlinStyle.commerce,
                                size: 42,
                              ),
                              title: '好友转账',
                              subtitle: '进入好友聊天页发起',
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: BlinStyle.subtle,
                              ),
                              onTap: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('请进入好友聊天页发起转账'),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardRedeemScreen extends StatefulWidget {
  final UserSession session;
  const _CardRedeemScreen({required this.session});

  @override
  State<_CardRedeemScreen> createState() => _CardRedeemScreenState();
}

class _CardRedeemScreenState extends State<_CardRedeemScreen> {
  final api = const ApiService();
  final controller = TextEditingController();
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting) return;
    final code = controller.text.trim();
    if (code.isEmpty) {
      setState(() => error = '请输入卡密');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final msg = await api.redeemDirectChargeCard(
        token: widget.session.token,
        cardCode: code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '卡密兑换',
            subtitle: '兑换金币、积分或会员权益',
            leading: IconButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                children: [
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const NativeIconBox(
                          icon: Icons.card_giftcard_rounded,
                          color: BlinStyle.success,
                          size: 50,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '输入卡密兑换权益',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '兑换成功后，到账记录会显示在账单明细中。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: controller,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: '卡密',
                            hintText: '请输入卡密',
                          ),
                          onSubmitted: (_) => unawaited(submit()),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: submitting ? null : submit,
                            child: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('立即兑换'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MyQrScreen extends StatefulWidget {
  final UserSession session;
  const _MyQrScreen({required this.session});

  @override
  State<_MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends State<_MyQrScreen> {
  final api = const ApiService();
  UserQrInfo? info;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final next = await api.getUserQr(widget.session.token);
      if (mounted) setState(() => info = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '我的二维码',
            subtitle: '扫码添加好友',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: BlinStyle.surface(context),
                  borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
                  boxShadow: [BlinStyle.softShadow(.12)],
                ),
                child: info == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (error == null)
                            const CircularProgressIndicator()
                          else ...[
                            Text(
                              '二维码读取失败',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: BlinStyle.subtle,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: load,
                              child: const Text('重试'),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppAvatar(
                            imageUrl: info!.user.avatar,
                            name: info!.user.nickname,
                            size: 64,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            info!.user.nickname,
                            style: const TextStyle(
                              color: BlinStyle.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 18),
                          QrImageView(
                            data: info!.qrData,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '扫一扫，加我为好友',
                            style: TextStyle(
                              color: BlinStyle.subtle,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SignInRewardDialog extends StatelessWidget {
  final String message;
  const _SignInRewardDialog({required this.message});

  bool get alreadySigned => message.contains('已') && message.contains('签');
  bool get syncIssue =>
      message.contains('暂时') ||
      message.contains('网络') ||
      message.contains('稍后') ||
      message.contains('未完成');
  String get title => syncIssue ? '签到提醒' : (alreadySigned ? '今日已签到' : '签到成功');
  String get buttonText => alreadySigned || syncIssue ? '知道了' : '开心收下';
  bool get success => !alreadySigned && !syncIssue;

  static const _dailyQuotes = [
    '把每一次打开，都变成离朋友更近一点。',
    '今天也保持联系，重要的话慢慢说。',
    '认真生活的人，总会收到新的回应。',
    '一条消息，可以让距离变得很短。',
    '把日常整理好，奖励会自然靠近。',
    '稳定地向前，比突然的热闹更可靠。',
    '愿今天的你，有消息可回，也有人惦记。',
  ];

  String get quote {
    final now = DateTime.now();
    final index =
        (now.year * 10000 + now.month * 100 + now.day) % _dailyQuotes.length;
    return _dailyQuotes[index];
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    backgroundColor: Colors.transparent,
    child: SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NativeIconBox(
                icon: syncIssue
                    ? Icons.info_outline_rounded
                    : alreadySigned
                    ? Icons.event_available_rounded
                    : Icons.check_circle_outline_rounded,
                color: syncIssue ? BlinStyle.warning : BlinStyle.success,
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      success ? '今天的奖励和一句话已为你准备好' : message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (success) ...[
            const _SignInIllustrationCard(),
            const SizedBox(height: 12),
            _DailyQuoteCard(quote: quote, message: message),
          ] else
            _SignInMessageCard(
              icon: alreadySigned
                  ? Icons.event_available_rounded
                  : Icons.info_outline_rounded,
              message: message,
              color: syncIssue ? BlinStyle.warning : BlinStyle.primary,
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    ),
  );
}

class _SignInIllustrationCard extends StatelessWidget {
  const _SignInIllustrationCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 128,
    decoration: BoxDecoration(
      color: BlinStyle.primarySoft,
      borderRadius: BorderRadius.circular(18),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned(
          right: -22,
          top: -28,
          child: Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              color: BlinStyle.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 18,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: BlinStyle.surface(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BlinStyle.softShadow(.08)],
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: BlinStyle.primary,
              size: 26,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 96,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日签到完成',
                style: TextStyle(
                  color: BlinStyle.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '奖励已同步到你的账户',
                style: TextStyle(
                  color: BlinStyle.textSecondary(context),
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: BlinStyle.success.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.redeem_rounded,
              color: BlinStyle.success,
              size: 28,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DailyQuoteCard extends StatelessWidget {
  final String quote;
  final String message;

  const _DailyQuoteCard({required this.quote, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: BlinStyle.iconSurface(context),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.format_quote_rounded,
              color: BlinStyle.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '每日一言',
              style: TextStyle(
                color: BlinStyle.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          quote,
          style: TextStyle(
            color: BlinStyle.textPrimary(context),
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (message.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              color: BlinStyle.textSecondary(context),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SignInMessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _SignInMessageCard({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: BlinStyle.textPrimary(context),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showPrettyDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.auto_awesome_rounded,
  String action = '知道了',
  Map<String, dynamic>? detail,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NativeIconBox(icon: icon, color: BlinStyle.primary, size: 58),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: BlinStyle.muted,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: _ApiDetailCard(data: detail),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(action),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showForcedAnnouncementDialog(
  BuildContext context,
  String announcement,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .42),
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SoftCard(
            radius: 28,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(
                    color: BlinStyle.primary.withValues(alpha: .08),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: BlinStyle.primary,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BlinStyle.glowShadow(BlinStyle.primary)],
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '系统公告',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BlinStyle.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '请阅读后确认，确认后不再重复提醒',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BlinStyle.textSecondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: BlinStyle.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: BlinStyle.line.withValues(alpha: .82),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: SelectableText(
                          announcement,
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 15,
                            height: 1.58,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('我已阅读并确认'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool?> _showAppUpdateDialog(
  BuildContext context,
  _AppUpdateInfo update,
) async {
  if (!context.mounted) return false;
  return showDialog<bool>(
    context: context,
    barrierDismissible: !update.force,
    barrierColor: Colors.black.withValues(alpha: .45),
    builder: (_) => PopScope(
      canPop: !update.force,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SoftCard(
            radius: 30,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  color: update.force
                      ? BlinStyle.danger.withValues(alpha: .08)
                      : BlinStyle.primary.withValues(alpha: .08),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: update.force
                              ? BlinStyle.danger
                              : BlinStyle.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BlinStyle.glowShadow(
                              update.force
                                  ? BlinStyle.danger
                                  : BlinStyle.primary,
                              .13,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.system_update_alt_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              update.force ? '必须更新后继续使用' : '发现新版本',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: BlinStyle.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '当前 ${AppConfig.appVersion}  ·  最新 ${update.latestVersion}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BlinStyle.textSecondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (update.force)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: BlinStyle.danger.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: BlinStyle.danger.withValues(alpha: .18),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.lock_clock_rounded,
                                color: BlinStyle.danger,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '本次更新需要立即完成，暂时不能跳过。',
                                  style: TextStyle(
                                    color: BlinStyle.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: BlinStyle.bg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: BlinStyle.line.withValues(alpha: .82),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Text(
                              update.content.isEmpty
                                  ? '新版本已经准备好，点击更新后将下载安装包并打开系统安装器。'
                                  : update.content,
                              style: const TextStyle(
                                color: BlinStyle.ink,
                                fontSize: 15,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: Row(
                    children: [
                      if (!update.force) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('稍后'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(update.force ? '立即更新' : '更新'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: update.force
                                ? BlinStyle.danger
                                : BlinStyle.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _downloadAndInstallUpdate(
  BuildContext context,
  _AppUpdateInfo update,
) async {
  final url = update.downloadUrl.trim();
  if (url.isEmpty) {
    await _showPrettyDialog(
      context,
      title: '暂时无法更新',
      message: '更新包暂时不可用，请稍后再试。',
      icon: Icons.link_off_rounded,
    );
    return;
  }
  final installer = AppUpdateInstaller();
  if (!installer.canInstallApk) {
    await _showPrettyDialog(
      context,
      title: '请前往下载更新',
      message: '当前平台不支持自动安装 APK，请使用浏览器打开更新地址：\n$url',
      icon: Icons.open_in_browser_rounded,
    );
    return;
  }
  await _showUpdateDownloadDialog(context, update, installer);
}

Future<void> _showUpdateDownloadDialog(
  BuildContext context,
  _AppUpdateInfo update,
  AppUpdateInstaller installer,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .45),
    builder: (dialogContext) {
      var started = false;
      var failed = false;
      var status = '准备下载更新包';
      var progress = 0.0;
      var receivedBytes = 0;
      int? totalBytes;

      void start(StateSetter setDialogState) {
        if (started) return;
        started = true;
        failed = false;
        unawaited(() async {
          try {
            final path = await installer.downloadApk(
              url: update.downloadUrl,
              version: update.latestVersion,
              onProgress: (received, total) {
                receivedBytes = received;
                totalBytes = total;
                if (total != null && total > 0) {
                  progress = (received / total).clamp(0.0, 1.0);
                  status = '正在下载 ${((progress) * 100).toStringAsFixed(0)}%';
                } else {
                  status = '正在下载 ${_formatBytes(received)}';
                }
                if (dialogContext.mounted) setDialogState(() {});
              },
            );
            status = '下载完成，正在打开安装程序';
            progress = 1;
            if (dialogContext.mounted) setDialogState(() {});
            await installer.installApk(path);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } on PlatformException catch (e) {
            failed = true;
            started = false;
            status = e.message ?? e.code;
            if (dialogContext.mounted) setDialogState(() {});
          } catch (e) {
            failed = true;
            started = false;
            status = '$e'.replaceFirst('Exception: ', '');
            if (dialogContext.mounted) setDialogState(() {});
          }
        }());
      }

      return StatefulBuilder(
        builder: (context, setDialogState) {
          start(setDialogState);
          final detail = totalBytes != null && totalBytes! > 0
              ? '${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes!)}'
              : _formatBytes(receivedBytes);
          return PopScope(
            canPop: false,
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SoftCard(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: failed
                                  ? BlinStyle.danger
                                  : BlinStyle.primary,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BlinStyle.glowShadow(
                                  failed ? BlinStyle.danger : BlinStyle.primary,
                                  .12,
                                ),
                              ],
                            ),
                            child: Icon(
                              failed
                                  ? Icons.error_outline_rounded
                                  : Icons.downloading_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  failed ? '更新失败' : '正在更新',
                                  style: const TextStyle(
                                    color: BlinStyle.ink,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '版本 ${update.latestVersion}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: BlinStyle.textSecondary(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        status,
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: totalBytes != null && totalBytes! > 0
                              ? progress
                              : null,
                          minHeight: 9,
                          color: failed ? BlinStyle.danger : BlinStyle.primary,
                          backgroundColor: BlinStyle.primary.withValues(
                            alpha: .12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        failed ? '请检查下载地址或网络后重试。' : detail,
                        style: TextStyle(
                          color: BlinStyle.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (failed) ...[
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: update.force
                              ? () {
                                  progress = 0;
                                  receivedBytes = 0;
                                  totalBytes = null;
                                  status = '准备重新下载更新包';
                                  setDialogState(() {});
                                  start(setDialogState);
                                }
                              : () => Navigator.pop(dialogContext),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(update.force ? '重新下载' : '知道了'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)}MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)}GB';
}

Future<bool> _showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.info_outline_rounded,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NativeIconBox(
              icon: icon,
              color: danger ? BlinStyle.danger : BlinStyle.primary,
              size: 58,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: danger
                        ? FilledButton.styleFrom(
                            backgroundColor: BlinStyle.danger,
                          )
                        : null,
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result == true;
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkeletonBox({this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: BlinStyle.softFill,
      border: Border.all(color: BlinStyle.line),
    ),
  );
}

class _ApiFeature {
  final String title;
  final IconData icon;
  final String path;
  final bool list;
  final List<_ApiFormField> fields;
  // ignore: unused_element_parameter
  const _ApiFeature(
    this.title,
    this.icon,
    this.path, {
    // ignore: unused_element_parameter
    this.list = true,
    // ignore: unused_element_parameter
    this.fields = const [],
  });
}

class _ApiFormField {
  final String key;
  final String label;
  final String hint;
  final bool required;
  // ignore: unused_element_parameter
  const _ApiFormField(
    this.key,
    this.label, {
    // ignore: unused_element_parameter
    this.hint = '',
    // ignore: unused_element_parameter
    this.required = false,
  });
}

class _SettingsScreen extends StatefulWidget {
  final UserSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  const _SettingsScreen({
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late ThemeMode themeMode;
  double chatFontSize = ChatDisplayPreferences.defaultChatFontSize;
  final chatDisplayPreferences = const ChatDisplayPreferences();

  @override
  void initState() {
    super.initState();
    themeMode = widget.themeMode;
    unawaited(_loadChatFontSize());
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  Future<void> _loadChatFontSize() async {
    final value = await chatDisplayPreferences.loadChatFontSize();
    if (!mounted) return;
    setState(() => chatFontSize = value);
  }

  Future<void> _setChatFontSize(double value) async {
    final next = ChatDisplayPreferences.normalizeChatFontSize(value);
    setState(() => chatFontSize = next);
    await chatDisplayPreferences.saveChatFontSize(next);
  }

  String get _themeLabel => switch (themeMode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '夜间',
    ThemeMode.system => '跟随系统',
  };

  Future<void> _checkUpdate(BuildContext context) async {
    try {
      final info = await const ApiService().getAppInfo();
      final update = _AppUpdateInfo.fromAppInfo(info);
      if (!context.mounted) return;
      if (update.hasUpdate) {
        final accepted = await _showAppUpdateDialog(context, update);
        if (accepted == true && context.mounted) {
          await _downloadAndInstallUpdate(context, update);
        }
      } else {
        await _showPrettyDialog(
          context,
          title: '已是最新版本',
          message: '当前已是最新版本。',
          icon: Icons.verified_rounded,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      await _showPrettyDialog(
        context,
        title: '检测未完成',
        message: '暂时无法获取版本信息，请稍后再试。',
        icon: Icons.info_rounded,
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await _showAppConfirmDialog(
      context,
      title: '退出登录',
      message: '确认退出当前账号吗？',
      icon: Icons.logout_rounded,
      confirmLabel: '退出',
      danger: true,
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    await widget.onLogout();
  }

  Future<void> _openPaymentPassword(BuildContext context) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentPasswordScreen(token: widget.session.token),
      ),
    );
  }

  Future<void> _openAccountDetail(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _AccountDetailScreen(session: widget.session),
      ),
    );
  }

  Future<void> _openRetrieveLoginPassword(BuildContext context) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RetrievePasswordScreen(initialUsername: widget.session.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '设置',
            subtitle: '显示和版本',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                children: [
                  const _SlimSectionHeader(title: '显示', subtitle: '主题模式和系统外观'),
                  const SizedBox(height: 10),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      children: [
                        _SettingTile(
                          icon: Icons.dark_mode_rounded,
                          title: '夜间模式',
                          subtitle: _themeLabel,
                          trailing: Switch(
                            value: themeMode == ThemeMode.dark,
                            onChanged: (v) => setThemeMode(
                              v ? ThemeMode.dark : ThemeMode.light,
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.auto_mode_rounded,
                          title: '跟随系统',
                          subtitle: '自动适配系统深浅色',
                          trailing: RadioGroup<ThemeMode>(
                            groupValue: themeMode,
                            onChanged: (v) {
                              if (v != null) setThemeMode(v);
                            },
                            child: const Radio<ThemeMode>(
                              value: ThemeMode.system,
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _ChatFontSizeSetting(
                          value: chatFontSize,
                          onChanged: (value) =>
                              unawaited(_setChatFontSize(value)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SlimSectionHeader(title: '安全', subtitle: '支付和账号保护'),
                  const SizedBox(height: 10),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      children: [
                        _SettingTile(
                          icon: Icons.manage_accounts_outlined,
                          title: '账户详情',
                          subtitle: '邮箱、手机号和账号绑定',
                          onTap: () => _openAccountDetail(context),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.lock_outline_rounded,
                          title: '支付密码',
                          subtitle: '设置或找回6位数字支付密码',
                          onTap: () => _openPaymentPassword(context),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.password_rounded,
                          title: '找回登录密码',
                          subtitle: '通过邮箱或手机号验证后重置',
                          onTap: () => _openRetrieveLoginPassword(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SlimSectionHeader(title: '关于', subtitle: '版本信息和更新检测'),
                  const SizedBox(height: 10),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      children: [
                        _SettingTile(
                          icon: Icons.info_rounded,
                          title: '版本',
                          subtitle: AppConfig.appVersion,
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.system_update_alt_rounded,
                          title: '检测更新',
                          subtitle: '检查是否有新版本可用',
                          onTap: () => _checkUpdate(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(6),
                    child: _SettingTile(
                      icon: Icons.logout_rounded,
                      title: '退出登录',
                      subtitle: '退出当前账号并返回登录页',
                      danger: true,
                      onTap: () => _confirmLogout(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool danger;
  final VoidCallback? onTap;
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? BlinStyle.danger : BlinStyle.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: .12)),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: danger
                            ? BlinStyle.danger
                            : BlinStyle.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: BlinStyle.subtle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDetailScreen extends StatefulWidget {
  final UserSession session;
  const _AccountDetailScreen({required this.session});

  @override
  State<_AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<_AccountDetailScreen> {
  final api = const ApiService();
  UserProfileSummary profile = const UserProfileSummary();
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await api.getUserOtherInformation(widget.session.token);
      if (mounted) setState(() => profile = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _valueOrUnbound(String value) =>
      value.trim().isEmpty ? '未绑定' : value.trim();

  Future<void> _openBinding(_AccountBindingType type) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AccountBindingScreen(
          session: widget.session,
          type: type,
          currentValue: type == _AccountBindingType.email
              ? profile.email
              : profile.mobile,
        ),
      ),
    );
    if (changed == true && mounted) unawaited(load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '账户详情',
            subtitle: '账号绑定和安全验证',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: BlinRefresh(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: Text(
                          '账户信息暂时无法更新，请稍后再试',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SoftCard(
                      radius: BlinStyle.cardRadius,
                      padding: const EdgeInsets.all(BlinStyle.cardPadding),
                      child: Column(
                        children: [
                          _SettingTile(
                            icon: Icons.alternate_email_rounded,
                            title: '账号',
                            subtitle: loading
                                ? '正在加载'
                                : (profile.username.isNotEmpty
                                      ? profile.username
                                      : widget.session.username),
                          ),
                          const Divider(height: 22),
                          _SettingTile(
                            icon: Icons.email_outlined,
                            title: '邮箱',
                            subtitle: loading
                                ? '正在加载'
                                : _valueOrUnbound(profile.email),
                            onTap: loading
                                ? null
                                : () => _openBinding(_AccountBindingType.email),
                          ),
                          const Divider(height: 22),
                          _SettingTile(
                            icon: Icons.phone_iphone_rounded,
                            title: '手机号',
                            subtitle: loading
                                ? '正在加载'
                                : _valueOrUnbound(profile.mobile),
                            onTap: loading
                                ? null
                                : () => _openBinding(_AccountBindingType.phone),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '更改邮箱或手机号时，需要先接收验证码完成验证。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

enum _AccountBindingType { email, phone }

extension on _AccountBindingType {
  String get title => switch (this) {
    _AccountBindingType.email => '邮箱',
    _AccountBindingType.phone => '手机号',
  };

  IconData get icon => switch (this) {
    _AccountBindingType.email => Icons.email_outlined,
    _AccountBindingType.phone => Icons.phone_iphone_rounded,
  };

  TextInputType get keyboardType => switch (this) {
    _AccountBindingType.email => TextInputType.emailAddress,
    _AccountBindingType.phone => TextInputType.phone,
  };
}

class _AccountBindingScreen extends StatefulWidget {
  final UserSession session;
  final _AccountBindingType type;
  final String currentValue;
  const _AccountBindingScreen({
    required this.session,
    required this.type,
    required this.currentValue,
  });

  @override
  State<_AccountBindingScreen> createState() => _AccountBindingScreenState();
}

class _AccountBindingScreenState extends State<_AccountBindingScreen> {
  final api = const ApiService();
  final valueController = TextEditingController();
  final codeController = TextEditingController();
  final imageCaptchaController = TextEditingController();
  bool sending = false;
  bool saving = false;
  int codeCountdown = 0;
  int captchaRefresh = 0;
  late String captchaKey;
  late Future<Uri> imageCaptchaUriFuture;
  Timer? codeTimer;
  String? error;

  @override
  void initState() {
    super.initState();
    captchaKey = _newAccountBindingCaptchaKey();
    imageCaptchaUriFuture = _buildImageCaptchaUri();
  }

  @override
  void dispose() {
    valueController.dispose();
    codeController.dispose();
    imageCaptchaController.dispose();
    codeTimer?.cancel();
    super.dispose();
  }

  bool get isEmail => widget.type == _AccountBindingType.email;

  String get _valueLabel => widget.type.title;

  String _newAccountBindingCaptchaKey() =>
      'bind_${DateTime.now().microsecondsSinceEpoch}';

  Future<Uri> _buildImageCaptchaUri() {
    return api.imageVerificationCodeUri(
      type: 3,
      refresh: captchaRefresh,
      captchaKey: captchaKey,
    );
  }

  void refreshCaptchaState() {
    captchaRefresh++;
    captchaKey = _newAccountBindingCaptchaKey();
    imageCaptchaUriFuture = _buildImageCaptchaUri();
    imageCaptchaController.clear();
  }

  String? _validateValue(String value) {
    if (isEmail) {
      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
      return ok ? null : '请输入正确的邮箱';
    }
    final ok = RegExp(r'^1\d{10}$').hasMatch(value);
    return ok ? null : '请输入正确的手机号';
  }

  Future<void> sendCode() async {
    if (sending || codeCountdown > 0) return;
    final value = valueController.text.trim();
    final validation = _validateValue(value);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final imageCaptcha = imageCaptchaController.text.trim();
    if (imageCaptcha.isEmpty) {
      setState(() => error = '请输入图片验证码');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final msg = isEmail
          ? await api.sendEmailVerificationCode(
              email: value,
              type: 3,
              captcha: imageCaptcha,
              captchaKey: captchaKey,
            )
          : await api.sendMobileVerificationCode(
              mobile: value,
              type: 4,
              captcha: imageCaptcha,
              captchaKey: captchaKey,
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      startCodeCountdown();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          refreshCaptchaState();
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void startCodeCountdown() {
    codeTimer?.cancel();
    setState(() => codeCountdown = 60);
    codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (codeCountdown <= 1) {
        timer.cancel();
        setState(() => codeCountdown = 0);
      } else {
        setState(() => codeCountdown--);
      }
    });
  }

  Future<void> submit() async {
    if (saving) return;
    final value = valueController.text.trim();
    final code = codeController.text.trim();
    final validation = _validateValue(value);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    if (code.isEmpty) {
      setState(() => error = '请输入验证码');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final msg = isEmail
          ? await api.updateUserEmail(
              token: widget.session.token,
              email: value,
              code: code,
            )
          : await api.updateUserPhone(
              token: widget.session.token,
              phone: value,
              code: code,
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.currentValue.trim();
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: current.isEmpty ? '绑定$_valueLabel' : '更改$_valueLabel',
              subtitle: current.isEmpty ? '当前未绑定' : '当前：$current',
              leading: IconButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                  children: [
                    SoftCard(
                      radius: BlinStyle.cardRadius,
                      padding: const EdgeInsets.all(BlinStyle.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NativeIconBox(
                            icon: widget.type.icon,
                            color: BlinStyle.primary,
                            size: 48,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            current.isEmpty
                                ? '绑定$_valueLabel'
                                : '更改$_valueLabel',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '验证码会发送到新的$_valueLabel，用于确认本次操作。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: valueController,
                            keyboardType: widget.type.keyboardType,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: '新的$_valueLabel',
                              hintText: isEmail ? '输入邮箱地址' : '输入手机号',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InlineImageCaptchaBox(
                            uriFuture: imageCaptchaUriFuture,
                            onRefresh: () {
                              setState(refreshCaptchaState);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: imageCaptchaController,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '图片验证码',
                              hintText: '输入图片中的字符',
                              prefixIcon: Icon(Icons.image_search_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: codeController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: '验证码',
                                    hintText: '输入验证码',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 54,
                                child: OutlinedButton(
                                  onPressed: (sending || codeCountdown > 0)
                                      ? null
                                      : sendCode,
                                  child: sending
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          codeCountdown > 0
                                              ? '$codeCountdown秒后重发'
                                              : '获取验证码',
                                        ),
                                ),
                              ),
                            ],
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: saving ? null : submit,
                              child: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(current.isEmpty ? '确认绑定' : '确认更改'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineImageCaptchaBox extends StatelessWidget {
  final Future<Uri> uriFuture;
  final VoidCallback onRefresh;

  const _InlineImageCaptchaBox({
    required this.uriFuture,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BlinStyle.hairline(context, .7).color),
      ),
      child: Row(
        children: [
          const NativeIconBox(
            icon: Icons.image_search_outlined,
            color: BlinStyle.primary,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<Uri>(
              future: uriFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(
                    height: 46,
                    alignment: Alignment.center,
                    color: BlinStyle.surface(context),
                    child: snapshot.hasError
                        ? Text(
                            '验证码加载失败',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  );
                }
                final uri = snapshot.data!;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    key: ValueKey(uri.toString()),
                    uri.toString(),
                    height: 46,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 46,
                      alignment: Alignment.center,
                      color: BlinStyle.surface(context),
                      child: Text(
                        '验证码加载失败',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新验证码',
          ),
        ],
      ),
    );
  }
}

class _ChatFontSizeSetting extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ChatFontSizeSetting({required this.value, required this.onChanged});

  String get _label => '${value.round()}px';

  @override
  Widget build(BuildContext context) {
    final normalized = ChatDisplayPreferences.normalizeChatFontSize(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 11, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: BlinStyle.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: BlinStyle.primary.withValues(alpha: .12),
                  ),
                ),
                child: const Icon(
                  Icons.format_size_rounded,
                  color: BlinStyle.primary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '聊天字体大小',
                      style: TextStyle(
                        color: BlinStyle.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '主要影响个人聊天和群聊的消息文字',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: BlinStyle.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _label,
                  style: const TextStyle(
                    color: BlinStyle.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '小',
                style: TextStyle(
                  color: BlinStyle.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: Slider(
                  value: normalized,
                  min: ChatDisplayPreferences.minChatFontSize,
                  max: ChatDisplayPreferences.maxChatFontSize,
                  divisions:
                      (ChatDisplayPreferences.maxChatFontSize -
                              ChatDisplayPreferences.minChatFontSize)
                          .round(),
                  label: _label,
                  onChanged: onChanged,
                ),
              ),
              const Text(
                '大',
                style: TextStyle(
                  color: BlinStyle.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: BlinStyle.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: BlinStyle.primary.withValues(alpha: .12),
              ),
            ),
            child: Text(
              '这是一条聊天消息预览',
              style: TextStyle(
                color: BlinStyle.textPrimary(context),
                fontSize: normalized,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlimSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SlimSectionHeader({required this.title, this.subtitle = ''});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: BlinStyle.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ProductCenterScreen extends StatefulWidget {
  final UserSession session;
  const _ProductCenterScreen({required this.session});

  @override
  State<_ProductCenterScreen> createState() => _ProductCenterScreenState();
}

class _EmojiStoreScreen extends StatefulWidget {
  final UserSession session;
  const _EmojiStoreScreen({required this.session});

  @override
  State<_EmojiStoreScreen> createState() => _EmojiStoreScreenState();
}

class _EmojiStoreScreenState extends State<_EmojiStoreScreen> {
  final api = const ApiService();
  bool loading = true;
  String error = '';
  List<GifStickerPack> packs = const [];
  Set<String> addedPackIds = const {};

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final loaded = await api.getEmojiStorePacks(limit: 240);
      final myPacks = await api.getMyEmojiPacks(widget.session.token);
      final added = myPacks.map((pack) => pack.id).toSet();
      if (!mounted) return;
      setState(() {
        packs = loaded;
        addedPackIds = added;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
      AppLogger.warn('STORE', '表情商店加载失败', data: e);
    }
  }

  Future<void> addPack(GifStickerPack pack) async {
    await api.addMyEmojiPack(widget.session.token, pack.id);
    if (!mounted) return;
    setState(() => addedPackIds = {...addedPackIds, pack.id});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已添加「${pack.name}」')));
  }

  Future<void> removePack(GifStickerPack pack) async {
    await api.removeMyEmojiPack(widget.session.token, pack.id);
    if (!mounted) return;
    setState(() => addedPackIds = {...addedPackIds}..remove(pack.id));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已取消「${pack.name}」')));
  }

  Future<void> openPack(GifStickerPack pack) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EmojiPackDetailScreen(
          session: widget.session,
          pack: pack,
          added: addedPackIds.contains(pack.id),
        ),
      ),
    );
    if (!mounted) return;
    final added = (await api.getMyEmojiPacks(
      widget.session.token,
    )).map((pack) => pack.id).toSet();
    if (mounted) setState(() => addedPackIds = added);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.bg,
    appBar: AppBar(
      title: const Text('表情商店'),
      backgroundColor: BlinStyle.bg,
      surfaceTintColor: Colors.transparent,
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: BlinStyle.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: BlinStyle.hairline(context, .55).color,
                  ),
                  boxShadow: [BlinStyle.softShadow(.06)],
                ),
                child: const Row(
                  children: [
                    NativeIconBox(
                      icon: Icons.emoji_emotions_outlined,
                      color: BlinStyle.primary,
                      size: 44,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '表情包',
                            style: TextStyle(
                              color: BlinStyle.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '添加后会出现在私聊和群聊输入面板',
                            style: TextStyle(
                              color: BlinStyle.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (error.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _StoreStateView(
                icon: Icons.cloud_off_outlined,
                title: '表情商店加载失败',
                message: error,
                actionText: '重试',
                onAction: () => unawaited(load()),
              ),
            )
          else if (packs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _StoreStateView(
                icon: Icons.emoji_emotions_outlined,
                title: '暂无表情包',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                itemCount: packs.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 184,
                ),
                itemBuilder: (context, index) {
                  final pack = packs[index];
                  return _EmojiPackStoreTile(
                    pack: pack,
                    added: addedPackIds.contains(pack.id),
                    onOpen: () => unawaited(openPack(pack)),
                    onToggle: () => unawaited(
                      addedPackIds.contains(pack.id)
                          ? removePack(pack)
                          : addPack(pack),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _EmojiPackStoreTile extends StatelessWidget {
  final GifStickerPack pack;
  final bool added;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  const _EmojiPackStoreTile({
    required this.pack,
    required this.added,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(20),
    child: Ink(
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BlinStyle.hairline(context, .58).color),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Image.network(
                  pack.displayUrl,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: BlinStyle.subtle,
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pack.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${pack.stickers.length} 个表情',
                  style: const TextStyle(
                    color: BlinStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                _EmojiAddButton(added: added, onTap: onToggle),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmojiPackDetailScreen extends StatefulWidget {
  final UserSession session;
  final GifStickerPack pack;
  final bool added;
  const _EmojiPackDetailScreen({
    required this.session,
    required this.pack,
    required this.added,
  });

  @override
  State<_EmojiPackDetailScreen> createState() => _EmojiPackDetailScreenState();
}

class _EmojiPackDetailScreenState extends State<_EmojiPackDetailScreen> {
  final api = const ApiService();
  late bool added = widget.added;

  Future<void> addPack() async {
    await api.addMyEmojiPack(widget.session.token, widget.pack.id);
    if (!mounted) return;
    setState(() => added = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已添加「${widget.pack.name}」')));
  }

  Future<void> removePack() async {
    await api.removeMyEmojiPack(widget.session.token, widget.pack.id);
    if (!mounted) return;
    setState(() => added = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已取消「${widget.pack.name}」')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.bg,
    appBar: AppBar(
      title: Text(widget.pack.name),
      backgroundColor: BlinStyle.bg,
      surfaceTintColor: Colors.transparent,
    ),
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BlinStyle.surface(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: BlinStyle.hairline(context, .55).color,
                ),
                boxShadow: [BlinStyle.softShadow(.06)],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.network(
                      widget.pack.displayUrl,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: BlinStyle.subtle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.pack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.pack.stickers.length} 个表情',
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _EmojiAddButton(
                    added: added,
                    onTap: added ? removePack : addPack,
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid.builder(
            itemCount: widget.pack.stickers.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 82,
            ),
            itemBuilder: (context, index) {
              final sticker = widget.pack.stickers[index];
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BlinStyle.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: BlinStyle.hairline(context, .55).color,
                  ),
                ),
                child: Image.network(
                  sticker.displayUrl,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: BlinStyle.subtle,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _EmojiAddButton extends StatelessWidget {
  final bool added;
  final VoidCallback onTap;
  const _EmojiAddButton({required this.added, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: added
            ? BlinStyle.warning.withValues(alpha: .10)
            : BlinStyle.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: added
              ? BlinStyle.warning.withValues(alpha: .22)
              : BlinStyle.primary,
        ),
      ),
      child: Text(
        added ? '取消' : '添加',
        style: TextStyle(
          color: added ? BlinStyle.warning : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _StoreStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionText;
  final VoidCallback? onAction;
  const _StoreStateView({
    required this.icon,
    required this.title,
    this.message = '',
    this.actionText = '',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        NativeIconBox(icon: icon, color: BlinStyle.subtle, size: 56),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            color: BlinStyle.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (message.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: BlinStyle.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        if (onAction != null && actionText.isNotEmpty) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(actionText)),
        ],
      ],
    ),
  );
}

class _ProductMetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  const _ProductMetaChip({required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final tone = color ?? BlinStyle.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommerceHeroCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String title;
  final String subtitle;
  final Widget? media;
  final List<Widget> chips;

  const _CommerceHeroCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.title,
    this.subtitle = '',
    this.media,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final heroMedia =
        media ??
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: accent, size: 28),
        );
    return SoftCard(
      padding: const EdgeInsets.all(18),
      color: Color.alphaBlend(
        accent.withValues(alpha: .035),
        BlinStyle.surface(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heroMedia,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BlinStyle.textPrimary(context),
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: BlinStyle.textSecondary(context),
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommerceFieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool showDivider;

  const _CommerceFieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = BlinStyle.primary,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NativeIconBox(icon: icon, color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: BlinStyle.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: BlinStyle.textPrimary(context),
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (showDivider)
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Divider(
            height: 1,
            thickness: 1,
            color: BlinStyle.hairline(context, .48).color,
          ),
        ),
    ],
  );
}

class _CommerceEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onAction;
  final String actionText;

  const _CommerceEmptyState({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.onAction,
    this.actionText = '',
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NativeIconBox(icon: icon, color: BlinStyle.primary, size: 64),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BlinStyle.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BlinStyle.textSecondary(context),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (onAction != null && actionText.isNotEmpty) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionText)),
          ],
        ],
      ),
    ),
  );
}

typedef _ProductPicker =
    String Function(Map<String, dynamic>, List<String>, [String]);

class _ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool canBuy;
  final Future<void> Function(BuildContext context)? onBuy;
  final _ProductPicker pick;

  const _ProductDetailScreen({
    required this.product,
    required this.canBuy,
    required this.onBuy,
    required this.pick,
  });

  String _priceText(String price) {
    if (price.isEmpty) return '价格待确认';
    return price.startsWith('¥') ? price : '¥$price';
  }

  String _mappedScalar(String key, String text) {
    if (text.isEmpty) return '';
    if (key == 'type') {
      return const {'0': '金币兑换', '1': '积分商品', '2': '金币商品', '3': '会员商品'}[text] ??
          text;
    }
    if (key == 'payment_method') {
      return const {
            '0': '金币支付',
            '1': '积分支付',
            '2': '支付宝当面付',
            '3': '易支付',
            '4': '源支付',
          }[text] ??
          text;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final name = pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '商品详情');
    final desc = pick(product, const [
      'commodity_details',
      'desc',
      'description',
      'content',
      'remark',
      'summary',
    ]);
    final price = pick(product, const [
      'commodity_price',
      'price',
      'money',
      'amount',
      'coin',
      'coins',
      'integral',
    ]);
    final stock = pick(product, const [
      'commodity_inventory',
      'stock',
      'num',
      'number',
      'inventory',
      'surplus',
    ]);
    final image = pick(product, const [
      'product_picture',
      'picture',
      'image',
      'img',
      'cover',
    ]);
    final id = pick(product, const ['id', 'shopid']);
    final type = _mappedScalar(
      'type',
      pick(product, const ['type', 'product_type']),
    );
    final payment = _mappedScalar(
      'payment_method',
      pick(product, const ['payment_method', 'payment_type']),
    );
    final priceLabel = _priceText(price);
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '商品详情',
              subtitle: canBuy ? '确认后生成订单记录' : '商品信息',
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SoftCard(
                            padding: const EdgeInsets.all(14),
                            clipBehavior: Clip.antiAlias,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 620;
                                final media = SizedBox(
                                  width: wide ? 250 : double.infinity,
                                  child: _ProductMediaPreview(
                                    imageUrl: image,
                                    name: name,
                                  ),
                                );
                                final info = Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    wide ? 18 : 2,
                                    wide ? 4 : 16,
                                    2,
                                    wide ? 4 : 2,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: BlinStyle.textPrimary(context),
                                          fontSize: 22,
                                          height: 1.16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        priceLabel,
                                        style: const TextStyle(
                                          color: BlinStyle.success,
                                          fontSize: 28,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _ProductMetaChip(
                                            label: canBuy ? '可购买' : '仅展示',
                                            color: canBuy
                                                ? BlinStyle.success
                                                : BlinStyle.subtle,
                                            icon: canBuy
                                                ? Icons.check_circle_outline
                                                : Icons.remove_red_eye_outlined,
                                          ),
                                          if (payment.isNotEmpty)
                                            _ProductMetaChip(
                                              label: payment,
                                              color: BlinStyle.primary,
                                              icon: Icons.wallet_outlined,
                                            ),
                                          if (stock.isNotEmpty)
                                            _ProductMetaChip(
                                              label: '库存 $stock',
                                              color: BlinStyle.warning,
                                              icon: Icons.inventory_2_outlined,
                                            ),
                                        ],
                                      ),
                                      if (desc.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        Text(
                                          desc,
                                          maxLines: 5,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: BlinStyle.textSecondary(
                                              context,
                                            ),
                                            fontSize: 14,
                                            height: 1.55,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                                if (wide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      media,
                                      Expanded(child: info),
                                    ],
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [media, info],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SoftCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                if (id.isNotEmpty)
                                  _CommerceFieldRow(
                                    icon: Icons.tag_rounded,
                                    label: '商品编号',
                                    value: id,
                                  ),
                                if (type.isNotEmpty)
                                  _CommerceFieldRow(
                                    icon: Icons.category_outlined,
                                    label: '商品类型',
                                    value: type,
                                  ),
                                if (payment.isNotEmpty)
                                  _CommerceFieldRow(
                                    icon: Icons.account_balance_wallet_outlined,
                                    label: '支付方式',
                                    value: payment,
                                  ),
                                if (stock.isNotEmpty)
                                  _CommerceFieldRow(
                                    icon: Icons.inventory_2_outlined,
                                    label: '库存状态',
                                    value: stock,
                                    showDivider: false,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: BlinStyle.surface(context),
                  border: Border(
                    top: BorderSide(
                      color: BlinStyle.hairline(context, .70).color,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '应付',
                                  style: TextStyle(
                                    color: BlinStyle.subtle,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  priceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: BlinStyle.success,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 164,
                            child: FilledButton.icon(
                              onPressed: canBuy && onBuy != null
                                  ? () => onBuy!(context)
                                  : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                              ),
                              icon: Icon(
                                canBuy
                                    ? Icons.shopping_cart_checkout_rounded
                                    : Icons.remove_red_eye_outlined,
                              ),
                              label: Text(canBuy ? '立即购买' : '仅展示'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductMediaPreview extends StatelessWidget {
  final String imageUrl;
  final String name;

  const _ProductMediaPreview({required this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(imageUrl);
    final fallback = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NativeIconBox(
            icon: Icons.local_mall_outlined,
            color: BlinStyle.primary,
            size: 56,
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BlinStyle.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: BlinStyle.iconSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BlinStyle.hairline(context, .70).color),
        ),
        clipBehavior: Clip.antiAlias,
        child: resolved.isEmpty
            ? fallback
            : Image.network(
                resolved,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _ProductPurchaseConfirmDialog extends StatelessWidget {
  final Map<String, dynamic> product;
  final _ProductPicker pick;

  const _ProductPurchaseConfirmDialog({
    required this.product,
    required this.pick,
  });

  String _priceText(String price, String payment) {
    if (price.isEmpty) return '价格待确认';
    if (price.startsWith('¥')) return price;
    if (payment.contains('金币')) return '$price 金币';
    if (payment.contains('积分')) return '$price 积分';
    return '¥$price';
  }

  String _mappedPayment(String value) =>
      const {
        '0': '金币支付',
        '1': '积分支付',
        '2': '支付宝当面付',
        '3': '易支付',
        '4': '源支付',
      }[value] ??
      value;

  @override
  Widget build(BuildContext context) {
    final name = pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '该商品');
    final price = pick(product, const [
      'commodity_price',
      'price',
      'money',
      'amount',
      'coin',
      'coins',
      'integral',
    ]);
    final stock = pick(product, const [
      'commodity_inventory',
      'stock',
      'num',
      'number',
      'inventory',
      'surplus',
    ]);
    final payment = _mappedPayment(
      pick(product, const ['payment_method', 'payment_type']),
    );
    final image = resolveMediaUrl(
      pick(product, const [
        'product_picture',
        'picture',
        'image',
        'img',
        'cover',
      ]),
    );
    final priceLabel = _priceText(price, payment);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SoftCard(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                child: Row(
                  children: [
                    const NativeIconBox(
                      icon: Icons.shopping_bag_outlined,
                      color: BlinStyle.commerce,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '确认订单',
                            style: TextStyle(
                              color: BlinStyle.textPrimary(context),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '确认后将进入订单详情',
                            style: TextStyle(
                              color: BlinStyle.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BlinStyle.softFill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: BlinStyle.surface(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: BlinStyle.hairline(context, .55).color,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: image.isEmpty
                            ? const Icon(
                                Icons.local_mall_outlined,
                                color: BlinStyle.primary,
                                size: 30,
                              )
                            : Image.network(
                                image,
                                fit: BoxFit.cover,
                                webHtmlElementStrategy:
                                    WebHtmlElementStrategy.fallback,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.local_mall_outlined,
                                  color: BlinStyle.primary,
                                  size: 30,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BlinStyle.textPrimary(context),
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              priceLabel,
                              style: const TextStyle(
                                color: BlinStyle.success,
                                fontSize: 22,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (payment.isNotEmpty)
                                  _ProductMetaChip(
                                    label: payment,
                                    color: BlinStyle.primary,
                                    icon: Icons.wallet_outlined,
                                  ),
                                if (stock.isNotEmpty)
                                  _ProductMetaChip(
                                    label: '库存 $stock',
                                    color: BlinStyle.warning,
                                    icon: Icons.inventory_2_outlined,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('再看看'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确认购买'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCenterScreenState extends State<_ProductCenterScreen> {
  final api = const ApiService();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return fallback;
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await api.getProductList(page: 1, limit: 10);
      if (!mounted) return;
      setState(() {
        products = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        products = [];
        error = '商品正在加载，请稍后下拉刷新';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showProductDetail(Map<String, dynamic> product) async {
    final id = _pick(product, const ['id']);
    final canBuy = id.isNotEmpty && id != '0';
    var detail = product;
    if (canBuy) {
      try {
        final r = await api.getProductInformation(id);
        detail = {...product, ...r};
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ProductDetailScreen(
          product: detail,
          canBuy: canBuy,
          pick: _pick,
          onBuy: canBuy
              ? (flowContext) => buy(detail, flowContext: flowContext)
              : null,
        ),
      ),
    );
  }

  void _fillOrderValue(Map<String, dynamic> row, String key, String value) {
    final current = '${row[key] ?? ''}'.trim();
    if (current.isEmpty || current == 'null') row[key] = value;
  }

  Map<String, dynamic> _buildOrderDetailRow(
    Map<String, dynamic> product,
    Map<String, dynamic> result,
  ) {
    final row = <String, dynamic>{...product, ...result};
    final payAmount = _pick(product, const [
      'pay_amount',
      'actual_amount',
      'payment_amount',
      'paid_amount',
      'pay_money',
      'real_money',
      'commodity_price',
      'price',
      'goods_price',
      'product_price',
      'money',
    ]);
    _fillOrderValue(
      row,
      'product_name',
      _pick(product, const ['product_name', 'name', 'title', 'goods_name']),
    );
    _fillOrderValue(row, 'commodity_price', payAmount);
    _fillOrderValue(row, 'pay_amount', payAmount);
    _fillOrderValue(row, 'actual_amount', payAmount);
    _fillOrderValue(row, 'payment_amount', payAmount);
    _fillOrderValue(
      row,
      'product_picture',
      _pick(product, const [
        'product_picture',
        'picture',
        'image',
        'img',
        'cover',
      ]),
    );
    _fillOrderValue(row, 'shopid', _pick(product, const ['id', 'shopid']));
    _fillOrderValue(row, 'status_text', '已提交');
    _fillOrderValue(row, 'remarks', _pick(result, const ['msg', 'message']));
    _fillOrderValue(
      row,
      'created_at',
      DateTime.now().toLocal().toString().split('.').first,
    );
    return row;
  }

  Future<Map<String, dynamic>> _resolvePurchasedOrder(
    Map<String, dynamic> product,
    Map<String, dynamic> result,
  ) async {
    final fallback = _buildOrderDetailRow(product, result);
    try {
      final list = await api.getApiList(
        widget.session.token,
        '/get_order_record',
        extra: const {'limit': 1, 'page': 1},
      );
      if (list.isNotEmpty) return {...fallback, ...list.first};
    } catch (_) {}
    return fallback;
  }

  Future<void> buy(
    Map<String, dynamic> product, {
    BuildContext? flowContext,
  }) async {
    final activeContext = flowContext ?? context;
    if (!activeContext.mounted) return;
    final id = _pick(product, const ['id']);
    if (id.isEmpty) {
      await _showPrettyDialog(
        activeContext,
        title: '商品信息不完整',
        message: '当前商品缺少必要信息，刷新商品中心后再试。',
        icon: Icons.info_rounded,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: activeContext,
      builder: (_) =>
          _ProductPurchaseConfirmDialog(product: product, pick: _pick),
    );
    if (ok != true) return;
    try {
      final r = await api.buyGoods(widget.session.token, id);
      final order = await _resolvePurchasedOrder(product, r);
      if (!mounted || !activeContext.mounted) return;
      await Navigator.push<void>(
        activeContext,
        MaterialPageRoute(
          builder: (_) => _ApiRecordDetailScreen(
            feature: const _ApiFeature(
              '订单记录',
              Icons.shopping_bag_outlined,
              '/get_order_record',
            ),
            row: order,
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !activeContext.mounted) return;
      await _showPrettyDialog(
        activeContext,
        title: '购买未完成',
        message: '当前商品购买暂时没有完成，请稍后刷新商品中心后再试。',
        icon: Icons.info_rounded,
      );
    }
  }

  Widget _productCard(Map<String, dynamic> product) {
    final name = _pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '商品');
    final desc = _pick(product, const [
      'commodity_details',
      'desc',
      'description',
      'content',
      'remark',
      'summary',
    ]);
    final price = _pick(product, const [
      'commodity_price',
      'price',
      'money',
      'amount',
      'coin',
      'coins',
      'integral',
    ]);
    final stock = _pick(product, const [
      'commodity_inventory',
      'stock',
      'num',
      'number',
      'inventory',
      'surplus',
    ]);
    final payment =
        const {
          '0': '金币支付',
          '1': '积分支付',
          '2': '支付宝当面付',
          '3': '易支付',
          '4': '源支付',
        }[_pick(product, const ['payment_method', 'payment_type'])] ??
        _pick(product, const ['payment_method', 'payment_type']);
    final priceText = price.isEmpty
        ? ''
        : price.startsWith('¥')
        ? price
        : payment.contains('金币')
        ? '$price 金币'
        : payment.contains('积分')
        ? '$price 积分'
        : '¥$price';
    final picture = _pick(product, const [
      'product_picture',
      'picture',
      'image',
      'img',
      'cover',
    ]);
    final id = _pick(product, const ['id']);
    final canBuy = id.isNotEmpty && id != '0';
    final imageUrl = resolveMediaUrl(picture);
    Widget media({double size = 88}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: imageUrl.isEmpty ? BlinStyle.softFill : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BlinStyle.hairline(context, .55).color),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) => const Icon(
                Icons.local_mall_rounded,
                color: BlinStyle.primary,
                size: 30,
              ),
            )
          : const Icon(
              Icons.local_mall_rounded,
              color: BlinStyle.primary,
              size: 30,
            ),
    );
    Widget info({bool compact = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: BlinStyle.textPrimary(context),
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            desc,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BlinStyle.textSecondary(context),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          priceText.isEmpty ? '价格待确认' : priceText,
          style: const TextStyle(
            color: BlinStyle.success,
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            if (payment.isNotEmpty)
              _ProductMetaChip(
                label: payment,
                color: BlinStyle.primary,
                icon: Icons.wallet_outlined,
              ),
            if (stock.isNotEmpty)
              _ProductMetaChip(
                label: '库存 $stock',
                color: BlinStyle.warning,
                icon: Icons.inventory_2_outlined,
              ),
            if (!canBuy)
              const _ProductMetaChip(
                label: '仅展示',
                color: BlinStyle.subtle,
                icon: Icons.remove_red_eye_outlined,
              ),
          ],
        ),
      ],
    );
    return SoftCard(
      onTap: () => showProductDetail(product),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardMode = constraints.maxWidth >= 420;
          if (cardMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: SizedBox.expand(child: media(size: double.infinity)),
                ),
                const SizedBox(height: 13),
                info(),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canBuy ? () => buy(product) : null,
                    icon: Icon(
                      canBuy
                          ? Icons.shopping_cart_checkout_rounded
                          : Icons.remove_red_eye_outlined,
                    ),
                    label: Text(canBuy ? '购买' : '查看'),
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              media(),
              const SizedBox(width: 13),
              Expanded(child: info(compact: true)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: canBuy ? () => buy(product) : null,
                icon: Icon(
                  canBuy
                      ? Icons.shopping_cart_checkout_rounded
                      : Icons.remove_red_eye_outlined,
                  size: 20,
                ),
                tooltip: canBuy ? '购买' : '查看',
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '商品中心',
            subtitle: '权益、积分和虚拟资产',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              IconButton(
                onPressed: load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
              ),
            ],
          ),
          Expanded(
            child: ModuleContent(
              child: BlinRefresh(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                  children: [
                    _SlimSectionHeader(
                      title: '精选商品',
                      subtitle: loading
                          ? '正在加载'
                          : products.isEmpty
                          ? '暂无商品'
                          : '${products.length} 个可选商品',
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const _ApiLoadingSkeleton()
                    else if (error != null)
                      _CommerceEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: '商品加载失败',
                        subtitle: error!,
                        actionText: '重新加载',
                        onAction: () => unawaited(load()),
                      )
                    else if (products.isEmpty)
                      const _CommerceEmptyState(
                        icon: Icons.local_mall_outlined,
                        title: '还没有商品',
                        subtitle: '有新商品时会出现在这里。',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoColumns = constraints.maxWidth >= 680;
                          final cardWidth = twoColumns
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final entry in products.asMap().entries)
                                SizedBox(
                                  width: cardWidth,
                                  child: SoftAppear(
                                    index: entry.key,
                                    child: _productCard(entry.value),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApiFeatureScreen extends StatefulWidget {
  final UserSession session;
  final _ApiFeature feature;
  const _ApiFeatureScreen({required this.session, required this.feature});

  @override
  State<_ApiFeatureScreen> createState() => _ApiFeatureScreenState();
}

class _ApiFeatureScreenState extends State<_ApiFeatureScreen> {
  final api = const ApiService();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? detail;
  late final Map<String, TextEditingController> controllers;
  bool submitting = false;

  bool get _isRecordListWithoutIntro =>
      widget.feature.path == '/get_user_billing' ||
      widget.feature.path == '/get_order_record';

  String get _screenSubtitle {
    switch (widget.feature.path) {
      case '/get_user_billing':
        return '余额、积分和资产变动';
      case '/get_order_record':
        return '商品购买和订单状态';
      case '/get_user_withdraw_cash_list':
        return '提现申请和处理状态';
      default:
        return widget.feature.list ? '记录列表' : '操作表单';
    }
  }

  String get _featureIntro {
    switch (widget.feature.path) {
      case '/get_user_billing':
        return '每一笔收入和支出都会按时间展示在这里。';
      case '/get_order_record':
        return '商品订单、支付方式和处理状态统一展示。';
      case '/get_user_withdraw_cash_list':
        return '查看提现账号、金额和处理进度。';
      default:
        return widget.feature.list ? '这里展示你的最新记录。' : '填写必要信息后提交，结果会更新到当前账号。';
    }
  }

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final field in widget.feature.fields)
        field.key: TextEditingController(),
    };
    load();
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _listExtra {
    final path = widget.feature.path;
    if (path == '/ranking_list') {
      return const {
        'sort': 'money',
        'sortOrder': 'desc',
        'limit': 10,
        'page': 1,
      };
    }
    if (path == '/invitation_ranking') {
      return const {'sortOrder': 'desc', 'limit': 10};
    }
    if (path == '/get_user_billing' ||
        path == '/get_user_withdraw_cash_list' ||
        path == '/get_order_record' ||
        path == '/get_fan_list') {
      return const {'limit': 10, 'page': 1};
    }
    return const {};
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.feature.list) {
        final r = await api.getApiList(
          widget.session.token,
          widget.feature.path,
          extra: _listExtra,
        );
        if (mounted) {
          setState(() {
            rows = r;
          });
        }
      } else if (widget.feature.fields.isEmpty &&
          widget.feature.path.startsWith('/get_')) {
        final r = await api.getApiData(
          widget.session.token,
          widget.feature.path,
        );
        if (mounted) setState(() => detail = r);
      } else {
        if (mounted) setState(() => detail = null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (widget.feature.list) {
          rows = [];
          error = null;
        } else {
          detail = null;
          error = null;
        }
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // 列表按接口原始返回展示，不额外追加未确认的请求参数。

  Future<void> submitForm() async {
    final extra = <String, dynamic>{};
    for (final field in widget.feature.fields) {
      final value = controllers[field.key]?.text.trim() ?? '';
      if (field.required && value.isEmpty) {
        await _showPrettyDialog(
          context,
          title: '信息还没填完整',
          message: '请先填写「${field.label}」，再继续提交。',
          icon: Icons.edit_note_rounded,
        );
        return;
      }
      if (value.isNotEmpty) extra[field.key] = value;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final r = await api.getApiData(
        widget.session.token,
        widget.feature.path,
        extra: extra,
      );
      if (!mounted) return;
      setState(() => detail = r);
      await _showPrettyDialog(
        context,
        title: '${widget.feature.title}已完成',
        message: '操作已完成。',
        icon: Icons.check_circle_rounded,
        detail: r,
      );
    } catch (_) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '${widget.feature.title}未完成',
        message: '当前操作没有完成，请确认信息后稍后再试。',
        icon: Icons.info_rounded,
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: widget.feature.title,
            subtitle: _screenSubtitle,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              IconButton(
                onPressed: load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
              ),
            ],
          ),
          Expanded(
            child: ModuleContent(
              child: BlinRefresh(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                  children: [
                    if (!_isRecordListWithoutIntro) ...[
                      _SlimSectionHeader(
                        title: widget.feature.list ? '记录明细' : '操作信息',
                        subtitle: loading
                            ? '正在加载'
                            : widget.feature.list
                            ? '${rows.length} 条记录'
                            : _featureIntro,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (loading)
                      const _ApiLoadingSkeleton()
                    else if (error != null)
                      SoftCard(
                        child: _ApiDetailCard(
                          data: {
                            'title': widget.feature.title,
                            'summary': '内容正在准备中，记录生成后会自动展示。',
                          },
                        ),
                      )
                    else if (widget.feature.list)
                      _ApiRows(rows: rows, feature: widget.feature)
                    else
                      _ApiFormPanel(
                        feature: widget.feature,
                        controllers: controllers,
                        detail: detail,
                        submitting: submitting,
                        onSubmit: submitForm,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApiLoadingSkeleton extends StatelessWidget {
  const _ApiLoadingSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      4,
      (i) => SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBox(width: i.isEven ? 180 : 130, height: 18, radius: 999),
            const SizedBox(height: 12),
            const _SkeletonBox(width: double.infinity, height: 12, radius: 999),
            const SizedBox(height: 8),
            _SkeletonBox(width: i.isEven ? 240 : 200, height: 12, radius: 999),
          ],
        ),
      ),
    ),
  );
}

class _ApiRecordDetailData {
  final _ApiFeature feature;
  final Map<String, dynamic> row;

  const _ApiRecordDetailData({required this.feature, required this.row});

  bool get isBilling => feature.path == '/get_user_billing';
  bool get isOrder => feature.path == '/get_order_record';
  bool get isPurchaseBill => isBilling && transactionTypeCode == '3';

  String pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return fallback;
  }

  String _map(String value, Map<String, String> labels) =>
      labels[value] ?? value;

  String get transactionTypeCode => pick(const ['transaction_type']);

  String get transactionType => _map(transactionTypeCode, const {
    '0': '邀请奖励',
    '1': '注册奖励',
    '2': '签到奖励',
    '3': '购买商品',
    '4': '内容付费',
    '5': '附件下载',
    '6': '打赏文章',
    '7': '提现',
    '8': '卡密兑换',
    '9': '转账',
    '10': '消息回复',
    '11': '互动',
    '12': '充值',
    '13': '系统调整',
    '15': '红包',
  });

  String get flowText {
    if (!isBilling) return '';
    final amount = rawAmount.trim();
    if (amount.startsWith('-')) return '支出';
    if (amount.startsWith('+')) return '收入';
    if (amount == '0' || amount == '0.00') return '记录';
    if (isExpenseBill) return '支出';
    return _map(pick(const ['flow_type', 'direction']), const {
      '0': '支出',
      '1': '收入',
      'out': '支出',
      'in': '收入',
      'expense': '支出',
      'income': '收入',
    });
  }

  bool get isIncomeBill => isBilling && rawAmount.trim().startsWith('+');

  bool get isExpenseBill {
    if (!isBilling) return false;
    final amount = rawAmount.trim();
    if (amount.startsWith('-')) return true;
    final flow = pick(const ['flow_type', 'direction']).toLowerCase();
    if (const {'0', 'out', 'expense', 'deduct', 'pay'}.contains(flow)) {
      return true;
    }
    return isPurchaseBill;
  }

  String get billAmountLabel {
    if (isIncomeBill) return '收入金额';
    if (isExpenseBill) return '支出金额';
    return '变动金额';
  }

  String get deductionType => _map(
    isPurchaseBill && paymentMethod.contains('金币')
        ? 'money'
        : isPurchaseBill && paymentMethod.contains('积分')
        ? 'integral'
        : pick([
            'deduction_type',
            'money_type',
            'asset_type',
            'asset',
            'currency',
            'coin_type',
            if (!isPurchaseBill) 'type',
          ]),
    const {
      '0': '金币',
      '1': '积分',
      'money': '金币',
      'coin': '金币',
      'coins': '金币',
      'gold': '金币',
      'integral': '积分',
      'point': '积分',
      'points': '积分',
      'score': '积分',
    },
  );

  String get paymentMethod => _map(
    pick(const ['payment_method', 'payment_type']),
    const {'0': '金币支付', '1': '积分支付', '2': '支付宝当面付', '3': '易支付', '4': '源支付'},
  );

  String get productType => _map(pick(const ['product_type', 'type']), const {
    '0': '兑换会员',
    '1': '购买积分',
    '2': '购买金币',
    '3': '购买会员',
  });

  String get statusText {
    final normalized = _recordStatusText(row, billing: isBilling);
    if (normalized.isNotEmpty) return normalized;
    final raw = pick(const ['status_text', 'status']);
    return _map(raw, const {
      '0': '待处理',
      '1': '已完成',
      '2': '已取消',
      '3': '处理失败',
      'paid': '已支付',
      'success': '已完成',
      'pending': '待处理',
      'failed': '处理失败',
      'cancelled': '已取消',
    });
  }

  String get timeText => pick(const [
    'created_at',
    'create_time',
    'addtime',
    'pay_time',
    'time',
    'updated_at',
  ]);

  String get imageUrl => pick(const [
    'product_picture',
    'app_icon',
    'icon',
    'avatar',
    'usertx',
    'cover',
    'picture',
    'image',
  ]);

  String get rawAmount {
    if (isBilling) {
      if (isPurchaseBill) {
        final paidAmount = pick(const [
          'actual_amount',
          'pay_amount',
          'payment_amount',
          'paid_amount',
          'pay_money',
          'real_money',
          'deduction_amount',
          'deduct_amount',
          'consume_amount',
          'cost_amount',
          'order_amount',
          'commodity_price',
          'goods_price',
          'product_price',
          'price',
        ]);
        if (paidAmount.isNotEmpty) return paidAmount;
      }
      return pick(const [
        'transaction_amount',
        'actual_amount',
        'pay_amount',
        'payment_amount',
        'paid_amount',
        'deduction_amount',
        'deduct_amount',
        'consume_amount',
        'cost_amount',
        'money',
        'amount',
        'coin',
        'coins',
        'integral',
        'score',
        'balance',
      ]);
    }
    return pick(const [
      'transaction_amount',
      'commodity_price',
      'money',
      'amount',
      'price',
      'coin',
      'coins',
      'integral',
      'score',
      'balance',
    ]);
  }

  String get amountText {
    final raw = rawAmount;
    if (raw.isEmpty) return '';
    if (isBilling) {
      final normalized = raw.trim();
      final displayAmount =
          isExpenseBill &&
              !normalized.startsWith('-') &&
              !normalized.startsWith('+') &&
              normalized != '0' &&
              normalized != '0.00'
          ? '-$normalized'
          : normalized;
      if (normalized.startsWith('+') ||
          normalized.startsWith('-') ||
          normalized == '0' ||
          normalized == '0.00') {
        return deductionType.isEmpty
            ? displayAmount
            : '$displayAmount $deductionType';
      }
      return deductionType.isEmpty
          ? displayAmount
          : '$displayAmount $deductionType';
    }
    if (isOrder) {
      if (raw.startsWith('¥')) return raw;
      if (paymentMethod.contains('金币')) return '$raw 金币';
      if (paymentMethod.contains('积分')) return '$raw 积分';
      return '¥$raw';
    }
    return raw;
  }

  Color get amountColor {
    if (isExpenseBill) return BlinStyle.danger;
    return BlinStyle.success;
  }

  String get title {
    if (isBilling) {
      return [
        transactionType,
        deductionType,
      ].where((e) => e.isNotEmpty).join(' · ');
    }
    if (isOrder) {
      return pick(const [
        'product_name',
        'goods_name',
        'order_no',
        'order_number',
        'trade_no',
        'id',
      ], '订单详情');
    }
    return pick(const ['title', 'name', 'id'], '记录详情');
  }

  String get subtitle {
    if (isBilling) {
      final remark = pick(const [
        'remarks',
        'remark',
        'description',
        'content',
      ]);
      final tradeNo = pick(const [
        'trade_no',
        'transaction_no',
        'transaction_id',
        'order_no',
        'transfer_no',
      ]);
      return [
        flowText,
        remark,
        if (tradeNo.isNotEmpty) '单号 $tradeNo',
      ].where((e) => e.isNotEmpty).join(' · ');
    }
    if (isOrder) {
      return [paymentMethod, statusText].where((e) => e.isNotEmpty).join(' · ');
    }
    return '';
  }

  String get detailTitle => isBilling
      ? '账单详情'
      : isOrder
      ? '订单详情'
      : '记录详情';

  String get heroLabel => isBilling
      ? billAmountLabel
      : isOrder
      ? (statusText.isEmpty ? '订单记录' : statusText)
      : feature.title;

  List<_ApiRecordField> get primaryRows {
    if (isBilling) {
      return [
        _ApiRecordField(Icons.swap_vert_rounded, '收支方向', flowText),
        _ApiRecordField(Icons.category_outlined, '交易类型', transactionType),
        _ApiRecordField(
          Icons.confirmation_number_outlined,
          '交易单号',
          pick(const [
            'trade_no',
            'transaction_no',
            'transaction_id',
            'order_no',
            'transfer_no',
          ]),
        ),
        _ApiRecordField(
          Icons.account_balance_wallet_outlined,
          '资产类型',
          deductionType,
        ),
        _ApiRecordField(Icons.payments_outlined, billAmountLabel, amountText),
        _ApiRecordField(Icons.schedule_rounded, '记录时间', timeText),
      ].where((e) => e.value.isNotEmpty).toList();
    }
    return [
      _ApiRecordField(Icons.local_mall_outlined, '商品名称', title),
      _ApiRecordField(
        Icons.receipt_long_outlined,
        '订单号',
        pick(const ['order_no', 'order_number']),
      ),
      _ApiRecordField(
        Icons.confirmation_number_outlined,
        '交易号',
        pick(const ['trade_no']),
      ),
      _ApiRecordField(
        Icons.account_balance_wallet_outlined,
        '支付方式',
        paymentMethod,
      ),
      _ApiRecordField(Icons.verified_outlined, '订单状态', statusText),
      _ApiRecordField(Icons.payments_outlined, '订单金额', amountText),
      _ApiRecordField(Icons.schedule_rounded, '下单时间', timeText),
    ].where((e) => e.value.isNotEmpty).toList();
  }

  List<_ApiRecordField> get secondaryRows {
    if (isBilling) {
      return [
        _ApiRecordField(
          Icons.notes_outlined,
          '备注',
          pick(const ['remarks', 'remark', 'description', 'content']),
        ),
      ].where((e) => e.value.isNotEmpty).toList();
    }
    return [
      _ApiRecordField(Icons.category_outlined, '商品类型', productType),
      _ApiRecordField(
        Icons.storefront_outlined,
        '商品编号',
        pick(const ['shopid', 'product_id', 'goods_id']),
      ),
      _ApiRecordField(
        Icons.inventory_2_outlined,
        '数量',
        pick(const ['num', 'number', 'count', 'quantity']),
      ),
      _ApiRecordField(
        Icons.notes_outlined,
        '备注',
        pick(const ['remarks', 'remark', 'description', 'content']),
      ),
      _ApiRecordField(Icons.tag_rounded, '记录编号', pick(const ['id', 'uid'])),
      _ApiRecordField(Icons.update_rounded, '更新时间', pick(const ['updated_at'])),
    ].where((e) => e.value.isNotEmpty).toList();
  }
}

class _ApiRecordField {
  final IconData icon;
  final String label;
  final String value;
  const _ApiRecordField(this.icon, this.label, this.value);
}

String _recordStatusText(Map<String, dynamic> row, {bool billing = false}) {
  final sources = _recordSources(row);
  String pick(List<String> keys) {
    for (final source in sources) {
      for (final key in keys) {
        final value = source[key];
        final text = '${value ?? ''}'.trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
    }
    return '';
  }

  final type = pick(const ['transaction_type', 'type', 'bill_type']);
  final raw = pick(const [
    'status',
    'state',
    'transfer_status',
    'order_status',
    'red_packet_status',
    'packet_status',
    'receive_status',
    'claim_status',
    'pay_status',
    'payment_status',
    'status_text',
  ]).toLowerCase();
  final hasAcceptedAt = pick(const [
    'accepted_at',
    'received_at',
    'accept_time',
    'receive_time',
    'paid_at',
    'finish_time',
    'finished_at',
  ]).isNotEmpty;
  final hasClaim = pick(const [
    'claim_amount',
    'receive_amount',
    'my_claim_amount',
    'claimed_amount',
    'amount_received',
  ]).isNotEmpty;
  final amount = pick(const [
    'transaction_amount',
    'actual_amount',
    'pay_amount',
    'payment_amount',
    'paid_amount',
    'deduction_amount',
    'deduct_amount',
    'consume_amount',
    'cost_amount',
    'money',
    'amount',
    'coin',
    'coins',
    'integral',
    'score',
    'balance',
  ]).trim();
  final remark = pick(const [
    'remarks',
    'remark',
    'description',
    'content',
    'title',
    'status_text',
  ]);
  final textBlob = sources
      .map(
        (source) => source.entries.map((e) => '${e.key}:${e.value}').join('|'),
      )
      .join('|')
      .toLowerCase();
  final isTransfer =
      type == '9' ||
      raw.contains('transfer') ||
      textBlob.contains('transfer_id') ||
      textBlob.contains('转账');
  final isRedPacket =
      type == '15' ||
      raw.contains('packet') ||
      raw.contains('red') ||
      textBlob.contains('red_packet_id') ||
      textBlob.contains('红包');
  if (isTransfer) {
    if (billing && RegExp(r'退回|退款|返还|超时|过期').hasMatch(remark)) {
      return remark.contains('超时') || remark.contains('过期') ? '已超时退回' : '已退回';
    }
    if (hasAcceptedAt ||
        const {
          '1',
          'accepted',
          'accept',
          'received',
          'receive',
          'paid',
          'success',
          'done',
          'completed',
          '已收款',
          '收款成功',
        }.contains(raw)) {
      return '已收款';
    }
    if (billing &&
        (amount.startsWith('+') || RegExp(r'收到|收款|入账').hasMatch(remark))) {
      return '已收款';
    }
    if (const {'2', 'refunded', 'returned', 'expired', '已退回'}.contains(raw)) {
      return raw == 'expired' ? '已超时退回' : '已退回';
    }
    if (billing &&
        (amount.startsWith('-') || RegExp(r'转账|发起|支付|扣除').hasMatch(remark))) {
      return '已完成';
    }
  }
  if (isRedPacket) {
    if (billing && RegExp(r'退回|退款|返还|超时|过期').hasMatch(remark)) {
      return '已退回';
    }
    if (hasClaim ||
        const {
          '1',
          'claimed',
          'received',
          'receive',
          'success',
          'done',
          'finished',
          'completed',
          '已领取',
          '已领完',
        }.contains(raw)) {
      return '已领取';
    }
    if (billing &&
        (amount.startsWith('+') || RegExp(r'领取|收到|入账').hasMatch(remark))) {
      return '已领取';
    }
    if (const {'2', 'refunded', 'expired', '已退回', '已过期'}.contains(raw)) {
      return '已退回';
    }
    if (billing &&
        (amount.startsWith('-') || RegExp(r'红包|发出|支付|扣除').hasMatch(remark))) {
      return '已完成';
    }
  }
  if (billing &&
      const {'1', 'paid', 'success', 'done', 'completed'}.contains(raw)) {
    return '已完成';
  }
  return '';
}

List<Map<String, dynamic>> _recordSources(Map<String, dynamic> row) {
  final sources = <Map<String, dynamic>>[row];
  void add(Object? value) {
    if (value is Map<String, dynamic>) {
      sources.add(Map<String, dynamic>.from(value));
    } else if (value is Map) {
      sources.add(Map<String, dynamic>.from(value));
    }
  }

  for (final key in const [
    'data',
    'detail',
    'transfer',
    'order',
    'red_packet',
    'packet',
    'claim',
    'billing',
    'bill',
  ]) {
    add(row[key]);
  }
  final content = row['content'];
  if (content is Map) {
    final map = Map<String, dynamic>.from(content);
    sources.add(map);
    for (final key in const [
      'transfer',
      'order',
      'red_packet',
      'packet',
      'claim',
    ]) {
      add(map[key]);
    }
  } else if (content is String && content.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(content);
      add(decoded);
    } catch (_) {}
  }
  return sources;
}

class _ApiRecordDetailScreen extends StatelessWidget {
  final _ApiFeature feature;
  final Map<String, dynamic> row;

  const _ApiRecordDetailScreen({required this.feature, required this.row});

  @override
  Widget build(BuildContext context) {
    final data = _ApiRecordDetailData(feature: feature, row: row);
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: data.detailTitle,
              subtitle: data.timeText.isEmpty ? feature.title : data.timeText,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ApiRecordHero(data: data),
                          const SizedBox(height: 12),
                          _ApiRecordSection(
                            title: data.isBilling ? '交易详情' : '订单信息',
                            fields: data.primaryRows,
                          ),
                          if (data.secondaryRows.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _ApiRecordSection(
                              title: data.isBilling ? '备注说明' : '商品与备注',
                              fields: data.secondaryRows,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiRecordHero extends StatelessWidget {
  final _ApiRecordDetailData data;

  const _ApiRecordHero({required this.data});

  @override
  Widget build(BuildContext context) {
    final imageUrl = resolveMediaUrl(data.imageUrl);
    final showImage = data.isOrder && imageUrl.isNotEmpty;
    final accent = data.isOrder ? BlinStyle.commerce : data.amountColor;
    final media = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: showImage ? Colors.white : accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BlinStyle.hairline(context, .60).color),
      ),
      clipBehavior: Clip.antiAlias,
      child: showImage
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) => Icon(
                data.isBilling
                    ? Icons.receipt_long_rounded
                    : Icons.shopping_bag_outlined,
                color: accent,
              ),
            )
          : Icon(
              data.isBilling
                  ? Icons.receipt_long_rounded
                  : Icons.shopping_bag_outlined,
              color: accent,
              size: 28,
            ),
    );
    return _CommerceHeroCard(
      icon: data.isBilling
          ? Icons.receipt_long_rounded
          : Icons.shopping_bag_outlined,
      accent: accent,
      label: data.heroLabel,
      title: data.amountText.isEmpty ? data.title : data.amountText,
      subtitle: data.amountText.isEmpty ? data.subtitle : data.title,
      media: media,
      chips: [
        for (final text
            in data.subtitle
                .split(' · ')
                .where((e) => e.trim().isNotEmpty)
                .take(3))
          _ProductMetaChip(label: text, color: accent),
      ],
    );
  }
}

class _ApiRecordSection extends StatelessWidget {
  final String title;
  final List<_ApiRecordField> fields;

  const _ApiRecordSection({required this.title, required this.fields});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 4),
          child: Text(
            title,
            style: TextStyle(
              color: BlinStyle.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        for (var i = 0; i < fields.length; i++)
          _CommerceFieldRow(
            key: ValueKey('${fields[i].label}_${fields[i].value}'),
            icon: fields[i].icon,
            label: fields[i].label,
            value: fields[i].value,
            color: BlinStyle.primary,
            showDivider: i != fields.length - 1,
          ),
      ],
    ),
  );
}

class _ApiRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final _ApiFeature feature;
  const _ApiRows({required this.rows, required this.feature});

  String _pick(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return '';
  }

  String _mapValue(String value, Map<String, String> labels) =>
      labels[value] ?? value;

  String _transactionType(String value) => _mapValue(value, const {
    '0': '邀请奖励',
    '1': '注册奖励',
    '2': '签到奖励',
    '3': '购买商品',
    '4': '内容付费',
    '5': '附件下载',
    '6': '打赏文章',
    '7': '提现',
    '8': '卡密兑换',
    '9': '转账',
    '10': '消息回复',
    '11': '互动',
    '12': '充值',
    '13': '系统调整',
    '15': '红包',
  });

  String _billingTransactionTypeCode(Map<String, dynamic> row) =>
      _pick(row, const ['transaction_type']);

  bool _billingIsPurchase(Map<String, dynamic> row) =>
      _billingTransactionTypeCode(row) == '3';

  String _billingPaymentMethod(Map<String, dynamic> row) =>
      _paymentMethod(_pick(row, const ['payment_method', 'payment_type']));

  String _billingAmount(Map<String, dynamic> row) {
    if (_billingIsPurchase(row)) {
      final paidAmount = _pick(row, const [
        'actual_amount',
        'pay_amount',
        'payment_amount',
        'paid_amount',
        'pay_money',
        'real_money',
        'deduction_amount',
        'deduct_amount',
        'consume_amount',
        'cost_amount',
        'order_amount',
        'commodity_price',
        'goods_price',
        'product_price',
        'price',
      ]);
      if (paidAmount.isNotEmpty) return paidAmount;
    }
    return _pick(row, const [
      'transaction_amount',
      'actual_amount',
      'pay_amount',
      'payment_amount',
      'paid_amount',
      'deduction_amount',
      'deduct_amount',
      'consume_amount',
      'cost_amount',
      'money',
      'amount',
      'coin',
      'coins',
      'integral',
      'score',
      'balance',
    ]);
  }

  String _billingFlow(Map<String, dynamic> row) {
    final amount = _billingAmount(row).trim();
    if (amount.startsWith('-')) return '支出';
    if (amount.startsWith('+')) return '收入';
    if (amount == '0' || amount == '0.00') return '记录';
    if (_billingIsExpense(row)) return '支出';
    return _mapValue(_pick(row, const ['flow_type', 'direction']), const {
      '0': '支出',
      '1': '收入',
      'out': '支出',
      'in': '收入',
      'expense': '支出',
      'income': '收入',
    });
  }

  bool _billingIsExpense(Map<String, dynamic> row) {
    final amount = _billingAmount(row).trim();
    if (amount.startsWith('-')) return true;
    final flow = _pick(row, const ['flow_type', 'direction']).toLowerCase();
    if (const {'0', 'out', 'expense', 'deduct', 'pay'}.contains(flow)) {
      return true;
    }
    return _billingIsPurchase(row);
  }

  String _billingAssetType(Map<String, dynamic> row) {
    final payment = _billingPaymentMethod(row);
    if (_billingIsPurchase(row) && payment.contains('金币')) return '金币';
    if (_billingIsPurchase(row) && payment.contains('积分')) return '积分';
    return _mapValue(
      _pick(row, const [
        'deduction_type',
        'money_type',
        'asset_type',
        'asset',
        'currency',
        'coin_type',
        'type',
      ]),
      const {
        '0': '金币',
        '1': '积分',
        'money': '金币',
        'coin': '金币',
        'coins': '金币',
        'gold': '金币',
        'integral': '积分',
        'point': '积分',
        'points': '积分',
        'score': '积分',
      },
    );
  }

  String _withdrawType(String value) =>
      _mapValue(value, const {'0': '金币提现', '1': '积分提现'});

  String _productType(String value) => _mapValue(value, const {
    '0': '兑换会员',
    '1': '购买积分',
    '2': '购买金币',
    '3': '购买会员',
  });

  String _paymentMethod(String value) => _mapValue(value, const {
    '0': '金币支付',
    '1': '积分支付',
    '2': '支付宝当面付',
    '3': '易支付',
    '4': '源支付',
  });

  bool get _usesDedicatedDetail =>
      feature.path == '/get_user_billing' ||
      feature.path == '/get_order_record';

  bool get _isBillingList => feature.path == '/get_user_billing';

  bool get _isOrderList => feature.path == '/get_order_record';

  void _openDetail(BuildContext context, Map<String, dynamic> row) {
    if (_usesDedicatedDetail) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => _ApiRecordDetailScreen(feature: feature, row: row),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SoftCard(
            padding: const EdgeInsets.all(BlinStyle.cardPadding),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .72,
              child: SingleChildScrollView(child: _ApiDetailCard(data: row)),
            ),
          ),
        ),
      ),
    );
  }

  String _displayTitle(Map<String, dynamic> row) {
    final path = feature.path;
    if (path == '/get_user_billing') {
      final t = _transactionType(_pick(row, const ['transaction_type']));
      final d = _billingAssetType(row);
      return [t, d].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_withdraw_cash_list') {
      final t = _withdrawType(_pick(row, const ['type']));
      return t.isEmpty ? '提现记录' : t;
    }
    if (path == '/get_order_record') {
      return _pick(row, const [
        'product_name',
        'goods_name',
        'title',
        'order_no',
        'order_number',
        'trade_no',
        'transaction_no',
        'id',
      ]);
    }
    if (path == '/get_section_list' || path == '/get_section_information') {
      return _pick(row, const [
        'section_name',
        'title',
        'name',
        'section_title',
        'sub_section_name',
        'sub_section_title',
        'id',
      ]);
    }
    if (path == '/ranking_list' || path == '/invitation_ranking') {
      return _pick(row, const [
        'nickname',
        'username',
        'name',
        'userid',
        'user_id',
        'id',
      ]);
    }
    if (path == '/get_user_apps_list') {
      return _pick(row, const ['app_name', 'name', 'title', 'id']);
    }
    if (path == '/get_user_badge') {
      return _pick(row, const [
        'badge_name',
        'medal_name',
        'name',
        'title',
        'id',
      ]);
    }
    return _pick(row, const [
      'title',
      'product_name',
      'app_name',
      'badge_name',
      'medal_name',
      'name',
      'nickname',
      'username',
      'content',
      'remark',
      'message',
      'goods_name',
      'order_no',
      'order_number',
      'trade_no',
      'id',
    ]);
  }

  String _displaySubtitle(Map<String, dynamic> row) {
    final path = feature.path;
    if (path == '/product_list') {
      final type = _productType(_pick(row, const ['type']));
      final pay = _paymentMethod(_pick(row, const ['payment_method']));
      final desc = _pick(row, const [
        'commodity_details',
        'description',
        'desc',
        'summary',
        'content',
      ]);
      return [desc, type, pay].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_order_record') {
      final pay = _paymentMethod(_pick(row, const ['payment_method']));
      final status = _pick(row, const ['status_text', 'status']);
      return [pay, status].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_billing') {
      final io = _billingFlow(row);
      final remark = _pick(row, const [
        'remarks',
        'remark',
        'description',
        'content',
      ]);
      final tradeNo = _pick(row, const [
        'trade_no',
        'transaction_no',
        'transaction_id',
        'order_no',
        'transfer_no',
      ]);
      return [
        io,
        remark,
        if (tradeNo.isNotEmpty) '单号 $tradeNo',
      ].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_section_list' || path == '/get_section_information') {
      return _pick(row, const [
        'section_description',
        'section_announcement',
        'description',
        'content',
      ]);
    }
    if (path == '/get_user_withdraw_cash_list') {
      return _pick(row, const [
        'account',
        'remarks',
        'remark',
        'status_text',
        'status',
      ]);
    }
    if (path == '/ranking_list') {
      final money = _pick(row, const ['money', 'coin', 'coins']);
      final integral = _pick(row, const ['integral', 'score']);
      final exp = _pick(row, const ['exp', 'experience']);
      return [
        if (money.isNotEmpty) '金币 $money',
        if (integral.isNotEmpty) '积分 $integral',
        if (exp.isNotEmpty) '经验 $exp',
      ].join(' · ');
    }
    if (path == '/invitation_ranking') {
      final invite = _pick(row, const [
        'invitation_num',
        'invite_count',
        'count',
        'num',
      ]);
      return invite.isEmpty ? '' : '邀请 $invite 人';
    }
    return _pick(row, const [
      'commodity_details',
      'desc',
      'description',
      'summary',
      'app_introduce',
      'text',
      'type',
      'category',
      'status_text',
      'status',
      'created_at',
      'create_time',
      'time',
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      if (_isBillingList) {
        return const _ApiListEmptyState(
          icon: Icons.receipt_long_outlined,
          title: '你还没有账单',
          subtitle: '转账、红包、购买和余额变动会显示在这里。',
        );
      }
      if (_isOrderList) {
        return const _ApiListEmptyState(
          icon: Icons.shopping_bag_outlined,
          title: '还没有订单记录',
          subtitle: '购买商品后，订单会按时间显示在这里。',
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      children: rows.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final row = entry.value;
        final title = _displayTitle(row);
        final subtitle = _displaySubtitle(row);
        final isBilling = feature.path == '/get_user_billing';
        final amount = isBilling
            ? _billingAmount(row)
            : _pick(row, const [
                'commodity_price',
                'transaction_amount',
                'total_amount',
                'money',
                'amount',
                'price',
                'coin',
                'coins',
                'integral',
                'score',
                'balance',
              ]);
        final image = _pick(row, const [
          'product_picture',
          'app_icon',
          'icon',
          'avatar',
          'usertx',
          'cover',
          'picture',
          'image',
        ]);
        final time = _pick(row, const [
          'created_at',
          'create_time',
          'addtime',
          'pay_time',
          'time',
          'updated_at',
        ]);
        final normalizedStatus = _recordStatusText(row, billing: isBilling);
        final status = normalizedStatus.isNotEmpty
            ? normalizedStatus
            : _pick(row, const ['status_text', 'status']);
        final isMoney =
            feature.path.contains('billing') ||
            feature.path.contains('withdraw') ||
            feature.path.contains('order') ||
            feature.path.contains('product') ||
            feature.title.contains('账单') ||
            feature.title.contains('提现') ||
            feature.title.contains('订单') ||
            feature.title.contains('商品');
        final assetType = isBilling ? _billingAssetType(row) : '';
        final normalizedBillingAmount =
            isBilling &&
                _billingIsExpense(row) &&
                !amount.trim().startsWith('-') &&
                !amount.trim().startsWith('+') &&
                amount.trim() != '0' &&
                amount.trim() != '0.00'
            ? '-${amount.trim()}'
            : amount;
        final amountText = amount.isEmpty
            ? ''
            : isBilling
            ? [
                normalizedBillingAmount,
                assetType,
              ].where((e) => e.isNotEmpty).join(' ')
            : isMoney && !amount.startsWith('¥')
            ? '¥$amount'
            : amount;
        final amountColor = isBilling && _billingIsExpense(row)
            ? BlinStyle.danger
            : BlinStyle.success;
        final leadingText =
            (feature.path == '/ranking_list' ||
                feature.path == '/invitation_ranking')
            ? '$index'
            : '';
        final leadingIcon = isBilling
            ? (_billingIsExpense(row)
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
            : feature.path == '/get_order_record'
            ? Icons.shopping_bag_outlined
            : feature.icon;
        final leadingColor = isBilling
            ? amountColor
            : feature.path == '/get_order_record'
            ? BlinStyle.primary
            : BlinStyle.primary;
        return SoftAppear(
          index: index,
          child: SoftCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.zero,
            radius: 18,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openDetail(context, row),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: image.isEmpty
                            ? leadingColor.withValues(alpha: .10)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: BlinStyle.hairline(context, .55).color,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: resolveMediaUrl(image).isNotEmpty
                          ? Image.network(
                              resolveMediaUrl(image),
                              fit: BoxFit.cover,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.fallback,
                              errorBuilder: (_, _, _) => leadingText.isNotEmpty
                                  ? Center(
                                      child: Text(
                                        leadingText,
                                        style: const TextStyle(
                                          color: BlinStyle.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      leadingIcon,
                                      color: leadingColor,
                                      size: 22,
                                    ),
                            )
                          : leadingText.isNotEmpty
                          ? Center(
                              child: Text(
                                leadingText,
                                style: const TextStyle(
                                  color: BlinStyle.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : Icon(leadingIcon, color: leadingColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? '记录详情' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: BlinStyle.textPrimary(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BlinStyle.textSecondary(context),
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (time.isNotEmpty && time != subtitle) ...[
                            const SizedBox(height: 7),
                            Text(
                              time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: BlinStyle.subtle,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (amountText.isNotEmpty)
                          Text(
                            amountText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: amountColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (status.isNotEmpty && status != subtitle) ...[
                          const SizedBox(height: 8),
                          _ProductMetaChip(label: status, color: leadingColor),
                        ],
                      ],
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: BlinStyle.subtle,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ApiListEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ApiListEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) =>
      _CommerceEmptyState(icon: icon, title: title, subtitle: subtitle);
}

class _ApiFormPanel extends StatelessWidget {
  final _ApiFeature feature;
  final Map<String, TextEditingController> controllers;
  final Map<String, dynamic>? detail;
  final bool submitting;
  final Future<void> Function() onSubmit;
  const _ApiFormPanel({
    required this.feature,
    required this.controllers,
    required this.detail,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasForm =
        feature.fields.isNotEmpty || !feature.path.startsWith('/get_');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasForm)
          SoftCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  feature.fields.isEmpty
                      ? '确认执行${feature.title}'
                      : '填写${feature.title}信息',
                  style: const TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...feature.fields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[field.key],
                      decoration: InputDecoration(
                        labelText: field.required
                            ? '${field.label} *'
                            : field.label,
                        hintText: field.hint.isEmpty ? null : field.hint,
                        filled: true,
                        fillColor: BlinStyle.iconSurface(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: BlinStyle.line),
                        ),
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done_rounded),
                  label: Text(submitting ? '提交中...' : '提交'),
                ),
              ],
            ),
          ),
        if (detail != null) SoftCard(child: _ApiDetailCard(data: detail!)),
        if (!hasForm && detail == null) const SizedBox.shrink(),
      ],
    );
  }
}

class _ApiDetailCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ApiDetailCard({required this.data});

  static const _labels = {
    'id': 'ID',
    'uid': '用户ID',
    'user_id': '用户ID',
    'userid': '用户ID',
    'nickname': '昵称',
    'username': '账号',
    'name': '名称',
    'title': '标题',
    'section_name': '版块名称',
    'section_description': '版块描述',
    'section_announcement': '版块公告',
    'sub_section_name': '子版块名称',
    'content': '内容',
    'product_name': '商品名称',
    'product_picture': '商品图片',
    'commodity_details': '商品详情',
    'commodity_price': '商品价格',
    'commodity_inventory': '商品库存',
    'received_quantity': '已购数量',
    'type': '类型',
    'payment_method': '支付方式',
    'payment_type': '支付类型',
    'shopid': '商品ID',
    'order_no': '订单号',
    'order_number': '订单号',
    'trade_no': '交易号',
    'transaction_no': '交易单号',
    'transaction_id': '交易单号',
    'transfer_no': '转账单号',
    'forum_section': '版主',
    'transaction_type': '交易类型',
    'deduction_type': '扣减类型',
    'remarks': '备注',
    'account': '收款账号',
    'app_name': '应用名称',
    'app_icon': '应用图标',
    'app_introduce': '应用介绍',
    'badge_name': '徽章名称',
    'medal_name': '徽章名称',
    'email': '邮箱',
    'phone': '手机',
    'qq': 'QQ',
    'money': '金额',
    'amount': '金额',
    'transaction_amount': '金额',
    'total_amount': '金额',
    'balance': '余额',
    'coin': '金币',
    'coins': '金币',
    'integral': '积分',
    'score': '积分',
    'status': '状态',
    'msg': '提示',
    'message': '消息',
    'created_at': '创建时间',
    'create_time': '创建时间',
    'updated_at': '更新时间',
    'time': '时间',
  };

  String _label(String key) => _labels[key] ?? key.replaceAll('_', ' ');

  String _mappedScalar(String key, String text) {
    if (key == 'transaction_type') {
      return const {
            '0': '邀请奖励',
            '1': '注册奖励',
            '2': '签到奖励',
            '3': '购买商品',
            '4': '内容付费',
            '5': '附件下载',
            '6': '打赏文章',
            '7': '提现',
            '8': '卡密兑换',
            '9': '转账',
            '10': '消息回复',
            '11': '互动',
            '12': '充值',
            '13': '系统调整',
            '15': '红包',
          }[text] ??
          text;
    }
    if (key == 'deduction_type') {
      return const {'0': '金币', '1': '积分'}[text] ?? text;
    }
    if (key == 'payment_method') {
      return const {
            '0': '金币支付',
            '1': '积分支付',
            '2': '支付宝当面付',
            '3': '易支付',
            '4': '源支付',
          }[text] ??
          text;
    }
    if (key == 'type') {
      return const {
            '0': '金币/兑换',
            '1': '积分/购买积分',
            '2': '购买金币',
            '3': '购买会员',
          }[text] ??
          text;
    }
    if (key == 'transaction_amount' || key == 'total_amount') {
      return text;
    }
    return text;
  }

  String _value(dynamic value, [String key = '']) {
    if (value == null) return '';
    if (value is Map) {
      return value.entries
          .map((e) => '${_label('${e.key}')}: ${_value(e.value, '${e.key}')}')
          .where((e) => e.trim().isNotEmpty)
          .join('  ');
    }
    if (value is List) {
      return value.isEmpty ? '暂无' : value.map((e) => _value(e, key)).join('、');
    }
    final text = '$value'.trim();
    if (text == 'null' || text.isEmpty) return '';
    return _mappedScalar(key, text);
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries
        .map((e) => MapEntry(e.key, _value(e.value, e.key)))
        .where((e) => e.value.isNotEmpty)
        .take(24)
        .toList();
    if (entries.isEmpty) {
      return const Text(
        '暂无可显示数据',
        style: TextStyle(color: BlinStyle.ink, fontWeight: FontWeight.w900),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '详情',
          style: TextStyle(
            color: BlinStyle.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ...entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _label(e.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IncomingCallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IncomingCallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(34),
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
