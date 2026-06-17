import 'dart:async';
import 'dart:convert';
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
import '../services/auth_store.dart';
import '../services/conversation_preferences.dart';
import '../services/im_service.dart';
import '../services/message_alert_service.dart';
import '../services/screenshot_monitor.dart';
import '../widgets/blin_style.dart';
import 'chat_list_screen.dart';
import 'call_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Duration _incomingCallFreshness = Duration(seconds: 90);
  int index = 0;
  final visitedTabs = <int>{0};
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
  Timer? onlineHeartbeatTimer;
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
  final Map<String, BuildContext> incomingCallDialogContexts =
      <String, BuildContext>{};
  DateTime? lastPresenceBroadcastAt;

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
      final action = '${content['action'] ?? ''}';
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
      const Duration(seconds: 18),
      (_) => unawaited(_refreshUnreadCount()),
    );
    healthTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_checkImHealth()),
    );
    onlineHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_reportOnlineHeartbeat()),
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
    final groupId = int.tryParse(
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
    return mutedConversationKeys.contains(ConversationPreferences.peerKey(peerId));
  }

  void _scheduleStartupCallSignalSync() {
    for (final delay in const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 7),
      Duration(seconds: 12),
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
    callSignalSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
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
    if (signal.fromUserId <= 0 || signal.fromUserId == widget.session.id)
      return false;
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
    if (CallRouteGuard.isClosed(callId) || CallRouteGuard.isOutgoing(callId))
      return;
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
      if ('${decoded['type']}' != 'call') return;
      final rawPayload = decoded['payload'];
      if (rawPayload is! Map) return;
      final payload = Map<String, dynamic>.from(rawPayload);
      _queueIncomingCall(payload, notify: false, openNow: true);
    } catch (_) {}
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
                  AppAvatar(
                    imageUrl: peerAvatar,
                    name: peerName,
                    size: 84,
                  ),
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
      MaterialPageRoute(
        builder: (_) => CallScreen(
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
    reconnecting = true;
    connectStartedAt = DateTime.now();
    reconnectTimer?.cancel();
    try {
      final info = await const ApiService().getImConnectInfo(
        widget.session.token,
      );
      await im.connect(info: info, myId: widget.session.id);
      connectStartedAt = null;
      unawaited(_reportOnlineHeartbeat());
      unawaited(_broadcastOwnPresence(force: true));
    } catch (e) {
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

  Future<void> _reportOnlineHeartbeat({bool online = true}) async {
    try {
      await const ApiService().reportImOnlineHeartbeat(
        token: widget.session.token,
        online: online,
      );
      if (online) unawaited(_broadcastOwnPresence());
    } catch (_) {}
  }

  Future<void> _broadcastOwnPresence({bool force = false}) async {
    final now = DateTime.now();
    final last = lastPresenceBroadcastAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 25)) {
      return;
    }
    if (!im.connected || !im.isSocketConnected) return;
    lastPresenceBroadcastAt = now;
    try {
      final friends = await const ApiService().getFriends(widget.session.token);
      final payload = {
        'msg_type': 'presence',
        'client_msg_no':
            'presence_${widget.session.id}_${now.microsecondsSinceEpoch}',
        'event': 'online',
        'online': true,
        'user_id': widget.session.id,
        'uid': ImService.uidForUser(widget.session.id),
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
        'from_user_id': widget.session.id,
        'from_uid': ImService.uidForUser(widget.session.id),
        'content': {
          'event': 'online',
          'online': true,
          'user_id': widget.session.id,
          'uid': ImService.uidForUser(widget.session.id),
          'nickname': widget.session.nickname ?? widget.session.username,
          'avatar': widget.session.avatar,
          'time': now.toIso8601String(),
        },
        'create_time': now.toIso8601String(),
      };
      for (final friend in friends) {
        if (friend.id <= 0 || friend.id == widget.session.id) continue;
        final item = Map<String, dynamic>.from(payload)
          ..['to_user_id'] = friend.id
          ..['to_uid'] = ImService.uidForUser(friend.id);
        unawaited(
          im.sendDirect(
            channelId: ImService.uidForUser(friend.id),
            payload: item,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkImHealth() async {
    if (!mounted || reconnecting) return;
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
    reconnectTimer = Timer(const Duration(seconds: 3), () {
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
    unawaited(_reportOnlineHeartbeat());
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
        '${signal.fromUid}' == ImService.uidForUser(widget.session.id) ||
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
    syncingCallSignals = true;
    try {
      final sinceId = sinceIdOverride ?? lastCallSignalId;
      AppLogger.call('Home 开始后端补偿 since=$sinceId');
      final rows = await const ApiService().getImCallSignals(
        token: widget.session.token,
        sinceId: sinceId,
        limit: 50,
      );
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
        if (callId.isNotEmpty && handledIncomingCallIds.contains(callId))
          continue;
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
      AppLogger.error('HOME', '后端补偿失败', error: e, stack: st);
    } finally {
      if (sinceIdOverride == null && lastCallSignalId > 0) {
        unawaited(_saveCallSignalWatermark());
      }
      syncingCallSignals = false;
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final list = await const ApiService().getMessageList(
        widget.session.token,
      );
      // 通话只认 /get_im_call_signals 专用信令表，普通会话列表不再恢复 call payload。
      unawaited(_syncCallSignalsFromBackend());
      var total = list.fold<int>(0, (sum, item) => sum + item.unread);
      try {
        final requests = await const ApiService().getFriendRequests(
          widget.session.token,
        );
        total += requests.where((item) => item.pending).length;
      } catch (_) {}
      if (mounted && total != unreadCount) setState(() => unreadCount = total);
    } catch (_) {
      // 商业界面不暴露未读数量同步失败，保留上一次稳定值。
    }
  }

  Future<void> _logout() async {
    await alerts.stopKeepAlive();
    await _reportOnlineHeartbeat(online: false);
    await im.disconnect();
    await AuthStore().clear();
    widget.onLogout();
  }

  @override
  void dispose() {
    imSub?.cancel();
    friendSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    reconnectTimer?.cancel();
    callSignalSyncTimer?.cancel();
    healthTimer?.cancel();
    onlineHeartbeatTimer?.cancel();
    unawaited(_reportOnlineHeartbeat(online: false));
    messageSub?.cancel();
    callSub?.cancel();
    unreadTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleScreenshotKeyEvent);
    im.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final displayName = (widget.session.nickname?.trim().isNotEmpty == true)
        ? widget.session.nickname!.trim()
        : widget.session.username;
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => setState(() {
                      index = i;
                      visitedTabs.add(i);
                    }),
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: BlinStyle.softFill,
                        child: Text(
                          displayName.characters.first,
                          style: const TextStyle(
                            color: BlinStyle.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.chat_bubble_outline_rounded),
                        selectedIcon: Icon(Icons.chat_bubble_rounded),
                        label: Text('消息'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.group_outlined),
                        selectedIcon: Icon(Icons.group_rounded),
                        label: Text('联系人'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: Text('我的'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ['消息', '联系人', '我的'][selectedIndex],
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '欢迎回来，$displayName',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout_outlined),
                                tooltip: '退出登录',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: PageBackdrop(
                            child: IndexedStack(index: selectedIndex, children: pages),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ['消息', '联系人', '我的'][selectedIndex],
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '欢迎回来，$displayName',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout_outlined),
                          tooltip: '退出登录',
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: PageBackdrop(child: IndexedStack(index: selectedIndex, children: pages))),
                ],
              ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => setState(() {
                index = i;
                visitedTabs.add(i);
              }),
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                    child: const Icon(Icons.chat_bubble_rounded),
                  ),
                  label: '消息',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.group_outlined),
                  selectedIcon: Icon(Icons.group_rounded),
                  label: '联系人',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: '我的',
                ),
              ],
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
  );
  bool loadingProfile = true;
  bool hasLoadedProfile = false;
  String? profileError;
  Timer? profileSyncTimer;
  bool syncingProfile = false;
  DateTime? lastProfileSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadUserInfoConfig());
    loadProfile();
    profileSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
          : '今日签到状态已同步';
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
          onSessionChanged: widget.onSessionChanged,
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

  void openMyQr() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _MyQrScreen(session: widget.session)),
    );
  }

  Future<void> openGlobalLogs() async {
    final text = AppLogger.dump(limit: 500);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全局调试日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text.isEmpty ? '暂无日志' : text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('复制'),
          ),
        ],
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
      _MineMenuItem(
        '我的主页',
        Icons.person_outline_rounded,
        () => openFeature(
          const _ApiFeature(
            '我的主页',
            Icons.home_rounded,
            '/get_user_other_information',
            list: false,
          ),
        ),
      ),
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
      _MineMenuItem('设置', Icons.settings_outlined, openSettings),
      _MineMenuItem('全局调试日志', Icons.bug_report_outlined, openGlobalLogs),
    ];
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => loadProfile(),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _MineNativeHeader(
                  displayName: displayName,
                  avatar: avatar,
                  session: widget.session,
                  profile: profile,
                  showUserId: userInfoConfig.showUserId,
                  loading: loadingProfile && !hasLoadedProfile,
                  onQr: openMyQr,
                ),
                if (profileError != null)
                  Container(
                    width: double.infinity,
                    color: BlinStyle.surface(context),
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 10),
                    child: Text(
                      '个人资料暂时无法更新，请稍后再试',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                for (var i = 0; i < menuItems.length; i++)
                  _MineNativeMenuRow(item: menuItems[i]),
                const SizedBox(height: 30),
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
  final VoidCallback onQr;
  const _MineNativeHeader({
    required this.displayName,
    required this.avatar,
    required this.session,
    required this.profile,
    required this.showUserId,
    required this.loading,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: BlinStyle.page(context),
    child: Stack(
      children: [
        Container(
          height: 156,
          decoration: const BoxDecoration(color: Color(0xFFECEEEF)),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 24,
          child: IconButton(
            onPressed: onQr,
            icon: const Icon(Icons.qr_code_2_rounded, color: BlinStyle.muted),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 70),
          child: Column(
            children: [
              Center(
                child: AppAvatar(imageUrl: avatar, name: displayName, size: 90),
              ),
              const SizedBox(height: 15),
              Text(
                loading ? '加载中' : displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                showUserId
                    ? 'ID ${session.id}'
                    : '@${profile.username.isNotEmpty ? profile.username : session.username}',
                style: const TextStyle(color: BlinStyle.subtle, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MineNativeMenuRow extends StatelessWidget {
  final _MineMenuItem item;
  const _MineNativeMenuRow({required this.item});

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: NativeIconBox(icon: item.icon, color: BlinStyle.muted, size: 35),
    title: item.title,
    onTap: item.onTap,
    minHeight: 56,
    padding: const EdgeInsets.fromLTRB(15, 8, 12, 8),
    trailing: const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
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
      if (mounted) setState(() => profile = next);
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '钱包',
            subtitle: '余额和账单',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: BlinStyle.surface(context),
                      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
                      boxShadow: [BlinStyle.softShadow(.10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '账户余额',
                          style: TextStyle(
                            color: BlinStyle.subtle,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '¥${profile.coins}',
                              style: const TextStyle(
                                color: BlinStyle.ink,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                            if (loading) ...[
                              const SizedBox(width: 10),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '积分 ${profile.points}',
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  NativeListRow(
                    leading: const NativeIconBox(
                      icon: Icons.swap_horiz_rounded,
                      color: BlinStyle.primary,
                      size: 40,
                    ),
                    title: '好友转账',
                    subtitle: '进入聊天页可发起带小数金额的转账',
                    minHeight: 66,
                  ),
                  NativeListRow(
                    leading: const NativeIconBox(
                      icon: Icons.receipt_long_rounded,
                      color: BlinStyle.primary,
                      size: 40,
                    ),
                    title: '账单明细',
                    subtitle: '查看余额变动记录',
                    minHeight: 66,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: BlinStyle.subtle,
                    ),
                    onTap: openBilling,
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

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [BlinStyle.softShadow(.22)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RewardIllustration(),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: BlinStyle.softInk,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: BlinStyle.line),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFB547)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '每日一言：把今天过好，就是最稳定的成长。',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BlinStyle.softShadow(.20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: BlinStyle.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
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

class _RewardIllustration extends StatelessWidget {
  const _RewardIllustration();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    height: 112,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BlinStyle.success.withValues(alpha: .12),
          ),
        ),
        Positioned(
          top: 8,
          left: 14,
          child: _SparkleDot(size: 10, color: BlinStyle.cyan),
        ),
        Positioned(
          top: 20,
          right: 18,
          child: _SparkleDot(size: 8, color: BlinStyle.purple),
        ),
        Positioned(
          bottom: 16,
          left: 24,
          child: _SparkleDot(size: 7, color: BlinStyle.green),
        ),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BlinStyle.warning,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [BlinStyle.softShadow(.18)],
          ),
          child: const Icon(Icons.stars_rounded, color: Colors.white, size: 38),
        ),
        Positioned(
          bottom: 10,
          right: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BlinStyle.softShadow(.10)],
            ),
            child: const Text(
              '+奖励',
              style: TextStyle(
                color: BlinStyle.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SparkleDot extends StatelessWidget {
  final double size;
  final Color color;
  const _SparkleDot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .85),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .16),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
  );
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
  const _ApiFeature(
    this.title,
    this.icon,
    this.path, {
    this.list = true,
    this.fields = const [],
  });
}

class _ApiFormField {
  final String key;
  final String label;
  final String hint;
  final bool required;
  final bool obscure;
  const _ApiFormField(
    this.key,
    this.label, {
    this.hint = '',
    this.required = false,
    this.obscure = false,
  });
}

class _SettingsScreen extends StatefulWidget {
  final UserSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<UserSession> onSessionChanged;
  final Future<void> Function() onLogout;
  const _SettingsScreen({
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onSessionChanged,
    required this.onLogout,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late ThemeMode themeMode;
  AppUserInfoConfig userInfoConfig = const AppUserInfoConfig(
    showUserId: false,
    usernameChangeEnabled: true,
    usernameChangeIntervalDays: 30,
  );

  @override
  void initState() {
    super.initState();
    themeMode = widget.themeMode;
    unawaited(_loadUserInfoConfig());
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  String get _themeLabel => switch (themeMode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '夜间',
    ThemeMode.system => '跟随系统',
  };

  Future<void> _loadUserInfoConfig() async {
    try {
      final config = await const ApiService().getUserInfoConfig();
      if (mounted) setState(() => userInfoConfig = config);
    } catch (_) {}
  }

  Future<void> _changeUsername() async {
    if (!userInfoConfig.usernameChangeEnabled) {
      await _showPrettyDialog(
        context,
        title: '暂不允许修改用户名',
        message: '当前应用已在后台关闭用户名修改。',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }
    final controller = TextEditingController(text: widget.session.username);
    final next = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改用户名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
          ],
          decoration: InputDecoration(
            labelText: '用户名',
            hintText: '4-8位英文或数字',
            helperText: userInfoConfig.usernameChangeIntervalDays <= 0
                ? '后台当前允许随时修改'
                : '修改后 ${userInfoConfig.usernameChangeIntervalDays} 天内不可再次修改',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next == widget.session.username) return;
    if (!RegExp(r'^[A-Za-z0-9]{4,8}$').hasMatch(next)) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '用户名格式不正确',
        message: '用户名只能使用 4-8 位英文或数字。',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    try {
      final updated = await const ApiService().changeUsername(
        session: widget.session,
        username: next,
      );
      widget.onSessionChanged(updated);
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '用户名已更新',
        message: '新的用户名：${updated.username}',
        icon: Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '用户名未更新',
        message: '$e',
        icon: Icons.info_outline_rounded,
      );
    }
  }

  void _openFeature(_ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ApiFeatureScreen(session: widget.session, feature: feature),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    try {
      final info = await const ApiService().getAppInfo();
      final updates = info['updates_info'];
      final updateMap = updates is Map
          ? Map<String, dynamic>.from(updates)
          : info;
      final latest = '${updateMap['update_version'] ?? ''}'.trim();
      final url = '${updateMap['update_url'] ?? ''}'.trim();
      final content = '${updateMap['update_content'] ?? ''}'.trim();
      if (!context.mounted) return;
      if (latest.isNotEmpty && latest != AppConfig.appVersion) {
        await _showPrettyDialog(
          context,
          title: '发现新版本 $latest',
          message: content.isEmpty
              ? '有新版本可用。${url.isEmpty ? '' : '\n更新地址：$url'}'
              : '$content${url.isEmpty ? '' : '\n\n更新地址：$url'}',
          icon: Icons.system_update_alt_rounded,
        );
      } else {
        await _showPrettyDialog(
          context,
          title: '已是最新版本',
          message: '当前版本 ${AppConfig.appVersion} 已是后台配置的最新版本。',
          icon: Icons.verified_rounded,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      await _showPrettyDialog(
        context,
        title: '检测未完成',
        message: '当前暂时没有同步到版本信息，请稍后再试。',
        icon: Icons.info_rounded,
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '设置中枢',
            subtitle: '账号资料、安全绑定、主题偏好和版本更新',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _ClientHeroPanel(
                    icon: Icons.tune_rounded,
                    kicker: 'CONTROL CENTER',
                    title: '设置中枢',
                    subtitle: '账号资料、安全绑定、主题偏好和版本更新都集中在这里，入口不变，操作更清晰。',
                    onBack: () => Navigator.pop(context),
                    stats: [
                      _MiniStatPill(
                        label: '账号',
                        value: userInfoConfig.showUserId
                            ? '${widget.session.id}'
                            : widget.session.username,
                      ),
                      _MiniStatPill(label: '主题', value: _themeLabel),
                      _MiniStatPill(label: '版本', value: AppConfig.appVersion),
                    ],
                  ),
                  const SizedBox(height: BlinStyle.moduleGap),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      children: [
                        _SettingTile(
                          icon: Icons.edit_note_rounded,
                          title: '编辑个人资料',
                          subtitle: '昵称、头像、背景资料',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '编辑资料',
                              Icons.edit_note_rounded,
                              '/modify_user_information',
                              list: false,
                              fields: [
                                _ApiFormField('nickname', '昵称', hint: '输入新的昵称'),
                                _ApiFormField('qq', 'QQ', hint: '可选'),
                                _ApiFormField('email', '邮箱', hint: '可选'),
                                _ApiFormField('phone', '手机号', hint: '可选'),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.alternate_email_rounded,
                          title: '修改用户名',
                          subtitle: userInfoConfig.usernameChangeEnabled
                              ? '英文和数字，最多 8 位'
                              : '后台已关闭用户名修改',
                          onTap: () => unawaited(_changeUsername()),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.add_a_photo_outlined,
                          title: '更换头像',
                          subtitle: '上传头像地址或图片路径',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '上传头像',
                              Icons.add_a_photo_outlined,
                              '/upload_avatar',
                              list: false,
                              fields: [
                                _ApiFormField(
                                  'avatar',
                                  '头像地址',
                                  hint: '图片 URL 或后台返回路径',
                                  required: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.image_outlined,
                          title: '更换主页背景',
                          subtitle: '设置个人主页背景图',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '上传背景',
                              Icons.image_outlined,
                              '/upload_background',
                              list: false,
                              fields: [
                                _ApiFormField(
                                  'background',
                                  '背景地址',
                                  hint: '图片 URL 或后台返回路径',
                                  required: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlinStyle.moduleGap),
                  SoftCard(
                    radius: BlinStyle.cardRadius,
                    padding: const EdgeInsets.all(BlinStyle.cardPadding),
                    child: Column(
                      children: [
                        _SettingTile(
                          icon: Icons.lock_reset_rounded,
                          title: '修改密码',
                          subtitle: '更新当前账号登录密码',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '修改密码',
                              Icons.lock_reset_rounded,
                              '/change_password',
                              list: false,
                              fields: [
                                _ApiFormField(
                                  'old_password',
                                  '原密码',
                                  obscure: true,
                                  required: true,
                                ),
                                _ApiFormField(
                                  'new_password',
                                  '新密码',
                                  obscure: true,
                                  required: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.link_rounded,
                          title: 'QQ 绑定',
                          subtitle: '绑定 QQ 账号',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '绑定QQ',
                              Icons.link_rounded,
                              '/bind_qq',
                              list: false,
                              fields: [
                                _ApiFormField('qq', 'QQ 号', required: true),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.link_off_rounded,
                          title: '解绑 QQ',
                          subtitle: '解除当前 QQ 绑定',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '解绑QQ',
                              Icons.link_off_rounded,
                              '/unbind_qq',
                              list: false,
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.email_outlined,
                          title: '修改邮箱',
                          subtitle: '更新账号邮箱',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '修改邮箱',
                              Icons.email_outlined,
                              '/modify_user_email',
                              list: false,
                              fields: [
                                _ApiFormField('email', '新邮箱', required: true),
                                _ApiFormField('code', '验证码', hint: '邮箱验证码'),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.phone_android_rounded,
                          title: '修改手机',
                          subtitle: '更新账号手机号',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '修改手机',
                              Icons.phone_android_rounded,
                              '/modify_user_phone',
                              list: false,
                              fields: [
                                _ApiFormField('phone', '新手机号', required: true),
                                _ApiFormField('code', '验证码', hint: '短信验证码'),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 22),
                        _SettingTile(
                          icon: Icons.card_giftcard_rounded,
                          title: '填写邀请码',
                          subtitle: '绑定邀请关系',
                          onTap: () => _openFeature(
                            const _ApiFeature(
                              '填写邀请码',
                              Icons.card_giftcard_rounded,
                              '/fill_invitation_code',
                              list: false,
                              fields: [
                                _ApiFormField(
                                  'invitation_code',
                                  '邀请码',
                                  required: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlinStyle.moduleGap),
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
                          trailing: Radio<ThemeMode>(
                            value: ThemeMode.system,
                            groupValue: themeMode,
                            onChanged: (v) {
                              if (v != null) setThemeMode(v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlinStyle.moduleGap),
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
                  const SizedBox(height: BlinStyle.moduleGap),
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
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (danger ? Colors.red : BlinStyle.green).withValues(
                  alpha: .12,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: danger ? Colors.red : BlinStyle.ink,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? Colors.red : BlinStyle.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: BlinStyle.muted),
          ],
        ),
      ),
    ),
  );
}

class _ProductCenterScreen extends StatefulWidget {
  final UserSession session;
  const _ProductCenterScreen({required this.session});

  @override
  State<_ProductCenterScreen> createState() => _ProductCenterScreenState();
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
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
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
        error = '商品正在同步，请稍后下拉刷新';
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ApiDetailCard(data: detail),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: canBuy
                    ? () {
                        Navigator.pop(context);
                        buy(detail);
                      }
                    : null,
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: Text(canBuy ? '立即购买' : '展示商品'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> buy(Map<String, dynamic> product) async {
    final id = _pick(product, const ['id']);
    if (id.isEmpty) {
      await _showPrettyDialog(
        context,
        title: '商品信息不完整',
        message: '当前商品缺少必要信息，刷新商品中心后再试。',
        icon: Icons.info_rounded,
      );
      return;
    }
    final name = _pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '该商品');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BlinStyle.softShadow(.20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.shopping_bag_rounded,
                color: BlinStyle.green,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                '确认购买',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '确认购买「$name」吗？',
                style: const TextStyle(
                  color: BlinStyle.muted,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('购买'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await api.buyGoods(widget.session.token, id);
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '购买结果',
        message: '商品购买请求已完成，结果已同步到当前账号。',
        icon: Icons.check_circle_rounded,
        detail: r,
      );
    } catch (_) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
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
    final priceText = price.isEmpty
        ? ''
        : (price.startsWith('¥') ? price : '¥$price');
    final picture = _pick(product, const [
      'product_picture',
      'picture',
      'image',
      'img',
      'cover',
    ]);
    final canBuy = _pick(product, const ['id']) != '0';
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => showProductDetail(product),
      child: SoftCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: picture.isEmpty ? BlinStyle.softFill : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: BlinStyle.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: picture.isNotEmpty
                  ? Image.network(
                      picture,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.local_mall_rounded,
                        color: BlinStyle.ink,
                        size: 26,
                      ),
                    )
                  : const Icon(
                      Icons.local_mall_rounded,
                      color: BlinStyle.ink,
                      size: 26,
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      if (priceText.isNotEmpty)
                        Text(
                          priceText,
                          style: const TextStyle(
                            color: BlinStyle.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (stock.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          '库存 $stock',
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: canBuy ? () => buy(product) : null,
              child: Text(canBuy ? '购买' : '展示'),
            ),
          ],
        ),
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
            subtitle: '会员权益和虚拟资产',
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
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _ClientHeroPanel(
                      icon: Icons.storefront_rounded,
                      kicker: 'MARKET',
                      title: '商品中心',
                      subtitle: '精选服务、会员权益和虚拟资产统一陈列，购买后继续同步到当前账号。',
                      onBack: () => Navigator.pop(context),
                      onRefresh: load,
                      stats: [
                        _MiniStatPill(label: '商品', value: '${products.length}'),
                        _MiniStatPill(
                          label: '账号',
                          value: '${widget.session.id}',
                        ),
                        const _MiniStatPill(label: '状态', value: 'LIVE'),
                      ],
                    ),
                    const SizedBox(height: BlinStyle.moduleGap),
                    if (loading)
                      const _ApiLoadingSkeleton()
                    else if (error != null)
                      SoftCard(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else if (products.isEmpty)
                      const SoftCard(
                        child: Text(
                          '后台暂无商品，请添加商品后刷新',
                          style: TextStyle(
                            color: BlinStyle.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      ...products.map(_productCard),
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
        message: '操作结果已同步到当前账号。',
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
            subtitle: widget.feature.path,
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
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _ClientHeroPanel(
                      icon: widget.feature.icon,
                      kicker: widget.feature.path,
                      title: widget.feature.title,
                      subtitle: widget.feature.list
                          ? '这里展示接口返回的真实记录，刷新不会改变原业务请求参数。'
                          : '填写必要信息后执行原接口，结果会以结构化卡片反馈。',
                      onBack: () => Navigator.pop(context),
                      onRefresh: load,
                      stats: [
                        _MiniStatPill(
                          label: widget.feature.list ? '记录' : '字段',
                          value: widget.feature.list
                              ? '${rows.length}'
                              : '${widget.feature.fields.length}',
                        ),
                        _MiniStatPill(
                          label: '接口',
                          value: widget.feature.list ? 'LIST' : 'ACTION',
                        ),
                      ],
                    ),
                    const SizedBox(height: BlinStyle.moduleGap),
                    if (loading)
                      const _ApiLoadingSkeleton()
                    else if (error != null)
                      SoftCard(
                        child: _ApiDetailCard(
                          data: {
                            'title': widget.feature.title,
                            'summary': '内容正在准备中，后台记录生成后会自动同步。',
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
    '9': '发布内容',
    '10': '消息回复',
    '11': '互动',
    '12': '充值',
    '13': '系统调整',
  });

  String _deductionType(String value) =>
      _mapValue(value, const {'0': '金币', '1': '积分'});

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

  String _displayTitle(Map<String, dynamic> row) {
    final path = feature.path;
    if (path == '/get_user_billing') {
      final t = _transactionType(
        _pick(row, const ['transaction_type', 'type']),
      );
      final d = _deductionType(_pick(row, const ['deduction_type']));
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
        'order_no',
        'order_number',
        'trade_no',
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
      ]);
      return [desc, type, pay].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_order_record') {
      final pay = _paymentMethod(_pick(row, const ['payment_method']));
      final status = _pick(row, const ['status_text', 'status']);
      return [pay, status].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_billing') {
      final io = _mapValue(_pick(row, const ['type']), const {
        '0': '支出',
        '1': '收入',
      });
      final remark = _pick(row, const [
        'remarks',
        'remark',
        'description',
        'content',
      ]);
      return [io, remark].where((e) => e.isNotEmpty).join(' · ');
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
      return SoftCard(
        child: _ApiDetailCard(
          data: {'title': feature.title, 'summary': '后台暂无真实记录，请添加或产生数据后刷新。'},
        ),
      );
    }
    return Column(
      children: rows.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final row = entry.value;
        final title = _displayTitle(row);
        final subtitle = _displaySubtitle(row);
        final amount = _pick(row, const [
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
        final status = _pick(row, const ['status_text', 'status']);
        final isMoney =
            feature.path.contains('billing') ||
            feature.path.contains('withdraw') ||
            feature.path.contains('order') ||
            feature.path.contains('product') ||
            feature.title.contains('账单') ||
            feature.title.contains('提现') ||
            feature.title.contains('订单') ||
            feature.title.contains('商品');
        final amountText = amount.isEmpty
            ? ''
            : (isMoney && !amount.startsWith('¥') ? '¥$amount' : amount);
        final leadingText =
            (feature.path == '/ranking_list' ||
                feature.path == '/invitation_ranking')
            ? '$index'
            : '';
        return SoftCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              builder: (_) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * .72,
                    child: SingleChildScrollView(
                      child: _ApiDetailCard(data: row),
                    ),
                  ),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: image.isEmpty
                        ? BlinStyle.green.withValues(alpha: .12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => leadingText.isNotEmpty
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
                                  feature.icon,
                                  color: BlinStyle.ink,
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
                      : Icon(feature.icon, color: BlinStyle.ink, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '记录详情' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (status.isNotEmpty && status != subtitle) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: BlinStyle.green.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '状态 $status',
                            style: const TextStyle(
                              color: BlinStyle.softInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      if (time.isNotEmpty && time != subtitle) ...[
                        const SizedBox(height: 8),
                        Text(
                          time,
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (amountText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    amountText,
                    style: const TextStyle(
                      color: BlinStyle.green,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
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
                      obscureText: field.obscure,
                      decoration: InputDecoration(
                        labelText: field.required
                            ? '${field.label} *'
                            : field.label,
                        hintText: field.hint.isEmpty ? null : field.hint,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .72),
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
        if (!hasForm && detail == null)
          SoftCard(
            child: _ApiDetailCard(
              data: {
                'title': feature.title,
                'summary': '后台暂无真实信息，请添加或产生数据后刷新。',
              },
            ),
          ),
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
    'content': '内容',
    'product_name': '商品名称',
    'product_picture': '商品图片',
    'commodity_details': '商品详情',
    'commodity_price': '商品价格',
    'commodity_inventory': '商品库存',
    'type': '类型',
    'payment_method': '支付方式',
    'payment_type': '支付类型',
    'shopid': '商品ID',
    'order_no': '订单号',
    'order_number': '订单号',
    'trade_no': '交易号',
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
            '9': '发布内容',
            '10': '消息回复',
            '11': '互动',
            '12': '充值',
            '13': '系统调整',
          }[text] ??
          text;
    }
    if (key == 'deduction_type')
      return const {'0': '金币', '1': '积分'}[text] ?? text;
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
    if (key == 'type')
      return const {
            '0': '金币/兑换',
            '1': '积分/购买积分',
            '2': '购买金币',
            '3': '购买会员',
          }[text] ??
          text;
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
    if (value is List)
      return value.isEmpty ? '暂无' : value.map((e) => _value(e, key)).join('、');
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
        '操作已完成',
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

class _ClientHeroPanel extends StatelessWidget {
  final IconData icon;
  final String kicker;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final List<Widget> stats;

  const _ClientHeroPanel({
    required this.icon,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onRefresh,
    this.stats = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      loud: true,
      radius: 32,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const Spacer(),
              if (onRefresh != null)
                IconButton.filledTonal(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradientIcon(icon: icon, size: 58, iconSize: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kicker,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: BlinStyle.softInk,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: stats),
          ],
        ],
      ),
    );
  }
}

class _MiniStatPill extends StatelessWidget {
  final String label;
  final Object? value;

  const _MiniStatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .88)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: BlinStyle.muted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${value ?? ''}',
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
