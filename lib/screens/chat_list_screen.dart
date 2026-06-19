import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import '../calls/call_media_engine.dart';
import '../calls/call_session.dart';
import '../calls/call_signaling_adapter.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../models/call_signal.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/conversation_preferences.dart';
import '../services/failed_message_store.dart';
import '../services/file_download/file_downloader.dart';
import '../services/group_profile_events.dart';
import '../services/im_service.dart';
import '../services/screenshot_monitor.dart';
import '../utils/media_url.dart' as media_url;
import '../widgets/blin_style.dart';
import '../widgets/embedded_browser.dart';
import '../widgets/link_text.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'group_settings_screen.dart';

class ChatListNavigator {
  _ChatListScreenState? _state;

  Future<void> openPeer({
    required int userId,
    required String name,
    String avatar = '',
  }) async {
    await _state?._openPeerFromExternal(
      userId: userId,
      name: name,
      avatar: avatar,
    );
  }

  Future<void> openGroup({required int groupId, String groupNo = ''}) async {
    await _state?._openGroupFromExternal(groupId: groupId, groupNo: groupNo);
  }
}

class ChatListScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final bool voiceMessageEnabled;
  final bool screenshotNoticeEnabled;
  final ValueChanged<int>? onUnreadChanged;
  final ChatListNavigator? navigator;
  final int resetSwipeToken;
  const ChatListScreen({
    super.key,
    required this.session,
    required this.im,
    this.voiceMessageEnabled = true,
    this.screenshotNoticeEnabled = false,
    this.onUnreadChanged,
    this.navigator,
    this.resetSwipeToken = 0,
  });
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  final api = const ApiService();
  final search = TextEditingController();
  List<ConversationItem> items = [];
  List<Map<String, dynamic>> systemNotifications = [];
  int systemUnreadCount = 0;
  List<UserSearchResult> friends = [];
  List<ImGroup> groups = [];
  List<_UnifiedConversation> conversations = [];
  Set<String> pinnedConversationKeys = {};
  Map<String, int> hiddenConversationTimes = {};
  Set<int> savedGroupIds = {};
  Map<int, String> groupRemarks = {};
  int swipeResetToken = 0;
  bool showUserId = false;
  bool showGroupNo = true;
  bool loading = true;
  bool loadingList = false;
  String? error;
  StreamSubscription? sub;
  StreamSubscription? friendSub;
  StreamSubscription? groupProfileSub;
  StreamSubscription? presenceSub;
  StreamSubscription? connectionSub;
  Timer? onlineTimer;
  Timer? listRefreshTimer;
  final Map<int, ImOnlineStatus> peerOnline = {};
  final Map<int, DateTime> realtimePresenceAt = {};
  final Map<int, int> groupUnread = {};
  final Set<int> locallyDeletedFriendIds = {};

  @override
  void initState() {
    super.initState();
    swipeResetToken = widget.resetSwipeToken;
    widget.navigator?._state = this;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPinnedConversations());
    unawaited(loadUserInfoConfig());
    unawaited(load());
    sub = widget.im.messages.listen((message) {
      if (_isHiddenRealtimeGroupCallEvent(message)) return;
      final groupId = int.tryParse('${message.raw['group_id'] ?? 0}') ?? 0;
      if (groupId > 0 && !message.isMe) {
        if (mounted) {
          setState(() {
            groupUnread[groupId] = (groupUnread[groupId] ?? 0) + 1;
            conversations = _sortedConversations([
              for (final item in conversations)
                if (item.key == 'group:$groupId')
                  item.copyWith(
                    preview: message.preview,
                    timeText: message.createTime.toIso8601String(),
                    unread: groupUnread[groupId] ?? 0,
                  )
                else
                  item,
            ]);
          });
        }
        _emitUnreadTotal();
      }
      unawaited(load());
    });
    friendSub = widget.im.friendEvents.listen((payload) {
      final content = normalizeFriendEventContent(payload);
      final action = '${content['action'] ?? ''}';
      if (action == 'request') {
        unawaited(showFriendRequest(payload));
      } else if (action == 'accepted' && mounted) {
        final name = '${content['nickname'] ?? '对方'}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 已通过你的好友申请')));
      } else if (action == 'rejected' && mounted) {
        final name = '${content['nickname'] ?? '对方'}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 已拒绝你的好友申请')));
      }
      unawaited(load());
    });
    groupProfileSub = GroupProfileEvents.stream.listen((group) {
      _applyGroupProfileUpdate(group);
    });
    presenceSub = widget.im.presences.listen((p) {
      if (mounted) {
        setState(() {
          realtimePresenceAt[p.userId] = DateTime.now();
          peerOnline[p.userId] = ImOnlineStatus(
            online: p.online,
            device: p.device,
          );
        });
      }
    });
    connectionSub = widget.im.connectionChanges.listen((_) {
      if (widget.im.connected) unawaited(refreshPeerOnlineForItems(items));
    });
    onlineTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && widget.im.connected && items.isNotEmpty) {
        unawaited(refreshPeerOnlineForItems(items));
      }
    });
    listRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && widget.im.connected) unawaited(load());
    });
  }

  @override
  void didUpdateWidget(covariant ChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSwipeToken != widget.resetSwipeToken) {
      _resetConversationSwipes();
    }
  }

  void _resetConversationSwipes() {
    if (!mounted) return;
    setState(() => swipeResetToken++);
  }

  void _applyGroupProfileUpdate(ImGroup updated) {
    if (!mounted) return;
    setState(() {
      groups = [
        for (final group in groups) group.id == updated.id ? updated : group,
      ];
      conversations = _sortedConversations([
        for (final item in conversations)
          if (item.key == 'group:${updated.id}')
            item.copyWith(
              group: updated,
              title: groupRemarks[updated.id]?.trim().isNotEmpty == true
                  ? groupRemarks[updated.id]!.trim()
                  : updated.name,
              avatar: updated.avatar,
            )
          else
            item,
      ]);
    });
  }

  Future<void> refreshPeerOnlineForItems(List<ConversationItem> list) async {
    for (final item in list) {
      try {
        final status = await api.getImOnlineStatus(
          token: widget.session.token,
          userId: item.userId,
        );
        if (mounted) {
          final realtimeAt = realtimePresenceAt[item.userId];
          final hasFreshRealtime =
              realtimeAt != null &&
              DateTime.now().difference(realtimeAt) <
                  const Duration(seconds: 45);
          if (!hasFreshRealtime)
            setState(() => peerOnline[item.userId] = status);
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => peerOnline[item.userId] = const ImOnlineStatus(online: false),
          );
        }
      }
    }
  }

  Future<void> loadUserInfoConfig() async {
    try {
      final config = await api.getUserInfoConfig();
      if (mounted) {
        setState(() {
          showUserId = config.showUserId;
          showGroupNo = config.showGroupNo;
        });
      }
    } catch (_) {}
  }

  String userSubtitle(UserSearchResult user) =>
      showUserId ? 'ID: ${user.id}  @${user.username}' : '@${user.username}';

  String groupSubtitle(ImGroup group) {
    final count = '${group.memberCount}人';
    if (!showGroupNo) return count;
    final no = group.groupNo.isEmpty ? '${group.id}' : group.groupNo;
    return '$count · 群号 $no';
  }

  bool _isHiddenRealtimeGroupCallEvent(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    return type == 'group_call_join' || type == 'group_call_leave';
  }

  Future<void> _loadPinnedConversations() async {
    final saved = await ConversationPreferences.loadPinned(widget.session.id);
    final hidden = await ConversationPreferences.loadHidden(widget.session.id);
    if (!mounted) return;
    setState(() {
      pinnedConversationKeys = saved;
      hiddenConversationTimes = hidden;
      conversations = _sortedConversations(conversations);
    });
  }

  Future<void> toggleConversationPin(_UnifiedConversation conversation) async {
    final next = Set<String>.from(pinnedConversationKeys);
    final pinned = next.contains(conversation.key);
    if (pinned) {
      next.remove(conversation.key);
    } else {
      next.add(conversation.key);
    }
    setState(() {
      pinnedConversationKeys = next;
      conversations = _sortedConversations(conversations);
    });
    await ConversationPreferences.setPinned(
      widget.session.id,
      conversation.key,
      !pinned,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(pinned ? '已取消置顶' : '已置顶聊天')));
  }

  Future<void> hideConversation(_UnifiedConversation conversation) async {
    if (conversation.isSystem) return;
    final confirmed = await _showBlinConfirm(
      context,
      title: '删除会话',
      message: conversation.group != null
          ? '删除后会清空该群聊在本机的聊天记录，消息入口会从首页隐藏。'
          : '删除后会清空该聊天在本机的聊天记录，消息入口会从首页隐藏。',
      icon: Icons.delete_outline_rounded,
      cancelLabel: '取消',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    final hiddenAt =
        conversation.sortTime?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    setState(() {
      hiddenConversationTimes = {
        ...hiddenConversationTimes,
        conversation.key: hiddenAt,
      };
      conversations.removeWhere((item) => item.key == conversation.key);
      if (conversation.peerId > 0) {
        items.removeWhere((item) => item.userId == conversation.peerId);
        peerOnline.remove(conversation.peerId);
      }
      if (conversation.group != null) {
        groupUnread.remove(conversation.group!.id);
      }
    });
    _emitUnreadTotal();
    await ConversationPreferences.setHidden(
      widget.session.id,
      conversation.key,
      hiddenAt,
    );
    try {
      if (conversation.group != null) {
        await api.clearGroupChatHistory(
          token: widget.session.token,
          groupId: conversation.group!.id,
        );
      } else if (conversation.peerId > 0) {
        await api.clearPeerChatHistory(
          token: widget.session.token,
          peerId: conversation.peerId,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已从消息列表删除')));
  }

  List<_UnifiedConversation> _sortedConversations(
    List<_UnifiedConversation> source,
  ) {
    final sorted = source
        .map(
          (item) =>
              item.copyWith(pinned: pinnedConversationKeys.contains(item.key)),
        )
        .toList();
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final aTime = a.sortTime;
      final bTime = b.sortTime;
      if (aTime != null && bTime != null) {
        final byTime = bTime.compareTo(aTime);
        if (byTime != 0) return byTime;
      } else if (aTime != null || bTime != null) {
        return aTime != null ? -1 : 1;
      }
      final bySourceOrder = a.order.compareTo(b.order);
      if (bySourceOrder != 0) return bySourceOrder;
      return a.title.compareTo(b.title);
    });
    return sorted;
  }

  Future<List<_UnifiedConversation>> _buildUnifiedConversations({
    required List<ConversationItem> privateItems,
    required List<ImGroup> groupItems,
    required List<Map<String, dynamic>> notificationItems,
    required int notificationUnread,
  }) async {
    final result = <_UnifiedConversation>[
      for (var i = 0; i < privateItems.length; i++)
        _UnifiedConversation.peer(privateItems[i], order: i),
    ];
    if (notificationItems.isNotEmpty || notificationUnread > 0) {
      result.add(
        _UnifiedConversation.system(
          notificationItems,
          unread: notificationUnread,
          order: result.length,
        ),
      );
    }
    final groupConversations = await Future.wait([
      for (var i = 0; i < groupItems.length; i++)
        _groupConversation(groupItems[i], order: result.length + i),
    ]);
    result.addAll(groupConversations);
    return _sortedConversations(
      result.where((item) => !_isConversationHidden(item)).toList(),
    );
  }

  bool _isConversationHidden(_UnifiedConversation conversation) {
    final hiddenAt = hiddenConversationTimes[conversation.key];
    if (hiddenAt == null || hiddenAt <= 0 || conversation.isSystem) {
      return false;
    }
    final latestAt = conversation.sortTime?.millisecondsSinceEpoch ?? 0;
    if (latestAt > hiddenAt || (latestAt <= 0 && conversation.unread > 0)) {
      unawaited(
        ConversationPreferences.setHidden(
          widget.session.id,
          conversation.key,
          0,
        ),
      );
      hiddenConversationTimes.remove(conversation.key);
      return false;
    }
    return true;
  }

  Future<_UnifiedConversation> _groupConversation(
    ImGroup group, {
    required int order,
  }) async {
    final groupNoText = group.groupNo.isEmpty ? '${group.id}' : group.groupNo;
    var preview = showGroupNo
        ? '${group.memberCount}人 · 群号 $groupNoText'
        : '${group.memberCount}人';
    var latest = _firstNonEmpty(group.raw, const [
      'last_time',
      'last_msg_time',
      'last_message_time',
      'msg_time',
      'updated_at',
      'create_time',
    ]);
    try {
      final list = await api.getGroupChatLog(
        token: widget.session.token,
        groupId: group.id,
        myId: widget.session.id,
        page: 1,
        limit: 1,
      );
      final visible = list
          .where((message) => !_isHiddenRealtimeGroupCallEvent(message))
          .toList();
      if (visible.isNotEmpty) {
        final message = visible.last;
        preview = message.preview;
        latest = message.createTime.toIso8601String();
      }
    } catch (_) {}
    return _UnifiedConversation.group(
      group,
      order: order,
      unread: groupUnread[group.id] ?? 0,
      preview: preview,
      timeText: latest,
      title: groupRemarks[group.id]?.trim().isNotEmpty == true
          ? groupRemarks[group.id]!.trim()
          : group.name,
    );
  }

  Future<void> _loadGroupLocalSettings(List<ImGroup> groupList) async {
    final saved = await ConversationPreferences.loadSavedGroups(
      widget.session.id,
    );
    final remarks = <int, String>{};
    for (final group in groupList) {
      final remark = await ConversationPreferences.loadGroupRemark(
        widget.session.id,
        group.id,
      );
      if (remark.trim().isNotEmpty) remarks[group.id] = remark.trim();
    }
    savedGroupIds = saved;
    groupRemarks = remarks;
  }

  void _emitUnreadTotal() {
    final personalUnread = items.fold<int>(0, (sum, item) => sum + item.unread);
    final groupUnreadTotal = groupUnread.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    widget.onUnreadChanged?.call(
      personalUnread + groupUnreadTotal + systemUnreadCount,
    );
  }

  Future<void> load() async {
    if (loadingList) return;
    loadingList = true;
    try {
      final r = await api.getMessageList(widget.session.token);
      List<UserSearchResult> friendList = friends;
      List<ImGroup> groupList = groups;
      try {
        friendList = await api.getFriends(widget.session.token);
      } catch (_) {}
      try {
        groupList = await api.getImGroups(widget.session.token);
      } catch (_) {}
      await _loadGroupLocalSettings(groupList);
      hiddenConversationTimes = await ConversationPreferences.loadHidden(
        widget.session.id,
      );
      List<Map<String, dynamic>> notifications = systemNotifications;
      List<Map<String, dynamic>> unreadNotifications = const [];
      try {
        notifications = await api.getMessageNotifications(
          widget.session.token,
          page: 1,
          limit: 20,
        );
        unreadNotifications = await api.getMessageNotifications(
          widget.session.token,
          page: 1,
          limit: 50,
          unreadOnly: true,
        );
      } catch (_) {}
      final visibleItems = r
          .where(
            (item) =>
                !locallyDeletedFriendIds.contains(item.userId) &&
                !_isPeerConversationHidden(item),
          )
          .toList();
      final visibleFriends = friendList
          .where((user) => !locallyDeletedFriendIds.contains(user.id))
          .toList();
      final unified = await _buildUnifiedConversations(
        privateItems: visibleItems,
        groupItems: groupList,
        notificationItems: notifications,
        notificationUnread: unreadNotifications.length,
      );
      final unreadTotal = visibleItems.fold<int>(
        0,
        (sum, item) => sum + item.unread,
      );
      final groupUnreadTotal = groupUnread.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );
      widget.onUnreadChanged?.call(
        unreadTotal + groupUnreadTotal + unreadNotifications.length,
      );
      if (mounted) {
        setState(() {
          items = visibleItems;
          friends = visibleFriends;
          groups = groupList;
          conversations = unified;
          systemNotifications = notifications;
          systemUnreadCount = unreadNotifications.length;
          swipeResetToken++;
        });
      }
      unawaited(refreshPeerOnlineForItems(r));
    } catch (e) {
      final text = '$e';
      final friendly =
          text.contains('TimeoutException') ||
              text.contains('Future not completed')
          ? '消息列表加载超时，正在后台重试'
          : text;
      if (mounted && items.isEmpty) setState(() => error = friendly);
    } finally {
      loadingList = false;
      if (mounted) setState(() => loading = false);
    }
  }

  bool _isPeerConversationHidden(ConversationItem item) {
    final hiddenAt =
        hiddenConversationTimes[ConversationPreferences.peerKey(item.userId)];
    if (hiddenAt == null || hiddenAt <= 0) return false;
    final latestAt = item.msgDateTime?.millisecondsSinceEpoch ?? 0;
    if (latestAt > hiddenAt || (latestAt <= 0 && item.unread > 0)) {
      unawaited(
        ConversationPreferences.setHidden(
          widget.session.id,
          ConversationPreferences.peerKey(item.userId),
          0,
        ),
      );
      hiddenConversationTimes.remove(
        ConversationPreferences.peerKey(item.userId),
      );
      return false;
    }
    return true;
  }

  Future<void> sendFriendSignal(
    UserSearchResult user, {
    required String action,
    required String message,
  }) async {
    // 好友事件统一交给后端接口处理，客户端只监听 WuKongIM 结果，不直接发送 IM。
  }

  Future<void> showFriendRequest(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final content = normalizeFriendEventContent(payload);
    if (content.isEmpty) return;
    final fromId =
        int.tryParse('${payload['from_user_id'] ?? content['user_id'] ?? 0}') ??
        0;
    if (fromId <= 0 || fromId == widget.session.id) return;
    final name = '${content['nickname'] ?? '新朋友'}';
    final message = '${content['message'] ?? '请求添加你为好友'}';
    final accepted = await _showBlinConfirm(
      context,
      title: '好友申请',
      message: '$name\n$message',
      icon: Icons.person_add_alt_1_rounded,
      cancelLabel: '稍后',
      confirmLabel: '通过',
    );
    if (accepted != true) return;
    try {
      await api.handleFriendRequest(
        widget.session.token,
        userId: fromId,
        accept: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已和 $name 成为好友')));
        await load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('通过好友申请失败：$e')));
    }
  }

  Future<void> addFriend(UserSearchResult user) async {
    if (_isExistingFriend(user.id)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('你们已经是好友')));
      }
      return;
    }
    try {
      final msg = await api.addFriend(
        widget.session.token,
        user.id,
        message: '你好，我想添加你为好友',
      );
      await sendFriendSignal(user, action: 'request', message: '你好，我想添加你为好友');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        await load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _isExistingFriend(int userId) {
    if (userId <= 0) return false;
    return friends.any((user) => user.id == userId);
  }

  void openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FriendsScreen(
          friends: friends,
          showUserId: showUserId,
          onOpen: openUserProfile,
        ),
      ),
    );
  }

  Future<void> createGroup() async {
    if (friends.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要两位好友才能创建群聊')));
      return;
    }
    final fallbackName = widget.session.nickname?.trim().isNotEmpty == true
        ? widget.session.nickname!.trim()
        : '我的群聊';
    final result = await _showCreateGroupDialog(
      context: context,
      friends: friends,
      fallbackName: fallbackName,
      userSubtitle: userSubtitle,
    );
    if (result == null) return;
    final rawName = '${result['name'] ?? ''}'.trim();
    final name = rawName.isEmpty ? fallbackName : rawName;
    final memberIds =
        (result['members'] as List?)?.cast<int>() ?? const <int>[];
    if (memberIds.length < 2) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少邀请两位好友才能创建群聊')));
      return;
    }
    try {
      final group = await api.createImGroup(
        token: widget.session.token,
        name: name,
        memberIds: memberIds,
      );
      await load();
      if (mounted) openGroupChat(group);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('建群失败：$e')));
    }
  }

  void openGroupChat(ImGroup group) {
    _resetConversationSwipes();
    if ((groupUnread[group.id] ?? 0) > 0 && mounted) {
      setState(() {
        groupUnread[group.id] = 0;
        conversations = _sortedConversations([
          for (final item in conversations)
            item.key == 'group:${group.id}' ? item.copyWith(unread: 0) : item,
        ]);
      });
      _emitUnreadTotal();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GroupChatScreen(
          session: widget.session,
          im: widget.im,
          group: group,
          voiceMessageEnabled: widget.voiceMessageEnabled,
          screenshotNoticeEnabled: widget.screenshotNoticeEnabled,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          groupUnread[group.id] = 0;
          conversations = _sortedConversations([
            for (final item in conversations)
              item.key == 'group:${group.id}' ? item.copyWith(unread: 0) : item,
          ]);
        });
        _emitUnreadTotal();
      }
      load();
    });
  }

  Future<void> openChat(int userId, String name, String avatar) async {
    _resetConversationSwipes();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          session: widget.session,
          im: widget.im,
          peerId: userId,
          peerName: name,
          peerAvatar: avatar,
          voiceMessageEnabled: widget.voiceMessageEnabled,
          screenshotNoticeEnabled: widget.screenshotNoticeEnabled,
        ),
      ),
    );
    if (result is Map && '${result['deletedUserId']}' == '$userId') {
      locallyDeletedFriendIds.add(userId);
      if (mounted) {
        setState(() {
          items.removeWhere((item) => item.userId == userId);
          friends.removeWhere((user) => user.id == userId);
          conversations.removeWhere((item) => item.key == 'peer:$userId');
          peerOnline.remove(userId);
        });
        _emitUnreadTotal();
      }
    }
    await load();
  }

  Future<void> openUserProfile(UserSearchResult user) async {
    _resetConversationSwipes();
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserProfileScreen(
          session: widget.session,
          user: user,
          showUserId: showUserId,
          isFriend: _isExistingFriend(user.id),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'message') {
      await openChat(user.id, user.nickname, user.avatar);
    } else if (action == 'add_friend') {
      await addFriend(user);
    }
  }

  Future<void> _openPeerFromExternal({
    required int userId,
    required String name,
    String avatar = '',
  }) async {
    if (userId <= 0 || !mounted) return;
    UserSearchResult? localFriend;
    for (final user in friends) {
      if (user.id == userId) {
        localFriend = user;
        break;
      }
    }
    ConversationItem? localItem;
    for (final item in items) {
      if (item.userId == userId) {
        localItem = item;
        break;
      }
    }
    final resolvedName =
        localFriend?.nickname ??
        localItem?.nickname ??
        (name.trim().isEmpty ? '用户$userId' : name.trim());
    final resolvedAvatar = localFriend?.avatar ?? localItem?.avatar ?? avatar;
    await openChat(userId, resolvedName, resolvedAvatar);
  }

  Future<void> _openGroupFromExternal({
    required int groupId,
    String groupNo = '',
  }) async {
    if (!mounted) return;
    ImGroup? group;
    for (final item in groups) {
      if ((groupId > 0 && item.id == groupId) ||
          (groupNo.trim().isNotEmpty && item.groupNo == groupNo.trim())) {
        group = item;
        break;
      }
    }
    if (group == null && groupId > 0) {
      try {
        group = await api.getImGroupInfo(
          token: widget.session.token,
          groupId: groupId,
        );
      } catch (_) {}
    }
    if (group == null || !mounted) return;
    openGroupChat(group);
  }

  void openSystemNotifications() {
    _resetConversationSwipes();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SystemNotificationsScreen(
          session: widget.session,
          im: widget.im,
          initialItems: systemNotifications,
          initialUnreadCount: systemUnreadCount,
        ),
      ),
    ).then((_) => load());
  }

  void openFriendRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FriendRequestsScreen(session: widget.session, im: widget.im),
      ),
    ).then((_) => load());
  }

  Future<void> showSearchDialog() async {
    _resetConversationSwipes();
    final selected = await Navigator.push<_HomeSearchSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => _HomeMessageSearchScreen(
          session: widget.session,
          conversations: items,
          friends: friends,
          groups: groups,
          groupRemarks: groupRemarks,
          showUserId: showUserId,
          showGroupNo: showGroupNo,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.group != null) {
      openGroupChat(selected.group!);
      return;
    }
    if (selected.peerId > 0) {
      await openChat(selected.peerId, selected.peerName, selected.peerAvatar);
    }
  }

  Future<void> openAddFriendSearch({String initialKeyword = ''}) async {
    final selected = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserScreen(
          session: widget.session,
          initialKeyword: initialKeyword,
          showUserId: showUserId,
          friendIds: friends.map((user) => user.id).toSet(),
          onAddFriend: addFriend,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected is _SearchUserProfileAction) {
      if (selected.action == 'message') {
        await openChat(
          selected.user.id,
          selected.user.nickname,
          selected.user.avatar,
        );
      } else if (selected.action == 'add_friend') {
        await addFriend(selected.user);
      }
    } else if (selected is UserSearchResult) {
      await openChat(selected.id, selected.nickname, selected.avatar);
    } else if (selected is _ScannedQrIntent) {
      await handleScannedQr(selected.raw);
    }
  }

  Future<void> scanQrFromHome() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (raw == null || raw.trim().isEmpty) return;
    await handleScannedQr(raw.trim());
  }

  Future<void> handleScannedQr(String raw) async {
    final result = _QrPayload.parse(raw);
    if (result.isExternalUrl) {
      await openEmbeddedBrowser(result.url!, title: result.url!.host);
      return;
    }
    if (result.isGroup) {
      await handleGroupQr(raw, result);
      return;
    }
    if (result.isInternalUnsupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('暂不支持的二维码：${result.type}')));
      return;
    }
    await handleUserQr(raw);
  }

  Future<void> handleUserQr(String raw) async {
    try {
      final user = await api.scanUserQr(widget.session.token, raw);
      if (!mounted) return;
      if (user.id == widget.session.id) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('不能添加自己')));
        return;
      }
      final action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ScanUserActionSheet(
          user: user,
          showUserId: showUserId,
          isFriend: _isExistingFriend(user.id),
          onAdd: () => Navigator.pop(context, 'add'),
          onChat: () => Navigator.pop(context, 'chat'),
        ),
      );
      if (!mounted) return;
      if (action == 'add') {
        await addFriend(user);
      } else if (action == 'chat') {
        await openChat(user.id, user.nickname, user.avatar);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('二维码识别失败：$e')));
    }
  }

  Future<void> handleGroupQr(String raw, _QrPayload result) async {
    try {
      var group = _findLocalGroup(result.groupId, result.groupNo);
      group ??= await api.scanImGroupQr(
        token: widget.session.token,
        qrData: raw,
        groupId: result.groupId,
        groupNo: result.groupNo,
      );
      if (!mounted) return;
      final inGroup = _findLocalGroup(group.id, group.groupNo) != null;
      final action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ScanGroupActionSheet(
          group: group!,
          inGroup: inGroup,
          showGroupNo: showGroupNo,
          onJoin: () => Navigator.pop(context, 'join'),
          onOpen: () => Navigator.pop(context, 'open'),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'join' && !inGroup) {
        final msg = await api.joinImGroup(
          token: widget.session.token,
          groupId: group.id,
          groupNo: group.groupNo,
          qrData: raw,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        await load();
        group = _findLocalGroup(group.id, group.groupNo) ?? group;
      }
      if (action == 'open' || action == 'join') {
        openGroupChat(group);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('群二维码识别失败：$e')));
    }
  }

  ImGroup? _findLocalGroup(int groupId, String groupNo) {
    for (final group in groups) {
      if (groupId > 0 && group.id == groupId) return group;
      if (groupNo.trim().isNotEmpty && group.groupNo == groupNo.trim()) {
        return group;
      }
    }
    return null;
  }

  Future<void> openEmbeddedBrowser(Uri uri, {String title = '网页'}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbeddedBrowserScreen(url: uri, title: title),
      ),
    );
  }

  Future<void> manualOpenDialog() async {
    final keyword = await _showBlinTextInput(
      context,
      title: '搜索用户名',
      label: '用户名',
      hint: '例如：abcd12',
      icon: Icons.alternate_email_rounded,
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    await openAddFriendSearch(initialKeyword: keyword.trim());
  }

  Future<void> showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateActionSheet(
        onNearby: () => Navigator.pop(context, 'nearby'),
        onCreateGroup: () => Navigator.pop(context, 'group'),
        onAddFriend: () => Navigator.pop(context, 'add_friend'),
      ),
    );
    if (!mounted) return;
    if (action == 'nearby') {
      await openNearbyPeople();
    } else if (action == 'group') {
      await createGroup();
    } else if (action == 'add_friend') {
      await manualOpenDialog();
    }
  }

  Future<void> openNearbyPeople() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _NearbyPeopleScreen()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(load());
      if (widget.im.connected && items.isNotEmpty) {
        unawaited(refreshPeerOnlineForItems(items));
      }
    }
  }

  @override
  void dispose() {
    if (widget.navigator?._state == this) widget.navigator?._state = null;
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    onlineTimer?.cancel();
    listRefreshTimer?.cancel();
    connectionSub?.cancel();
    presenceSub?.cancel();
    groupProfileSub?.cancel();
    friendSub?.cancel();
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.page(context),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BlinStyle.pagePadding,
              14,
              BlinStyle.pagePadding,
              10,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '消息',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(width: 8),
                          _ConnectionPill(
                            connected: widget.im.connected,
                            connecting: widget.im.connecting,
                          ),
                        ],
                      ),
                    ),
                    ShellAction(
                      icon: Icons.qr_code_scanner_rounded,
                      onTap: scanQrFromHome,
                      tooltip: '扫一扫',
                    ),
                    const SizedBox(width: 8),
                    ShellAction(
                      icon: Icons.add_rounded,
                      onTap: showCreateMenu,
                      tooltip: '新建',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ProductSearchField(
                  hintText: '搜索聊天、群聊或聊天记录',
                  readOnly: true,
                  onTap: showSearchDialog,
                ),
              ],
            ),
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: BlinStyle.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (loading)
                    const _ChatSkeletonList()
                  else if (conversations.isEmpty)
                    _Empty(session: widget.session, onManual: manualOpenDialog)
                  else
                    ...conversations.map(
                      (conversation) => _UnifiedConversationTile(
                        conversation: conversation,
                        resetSwipeToken: swipeResetToken,
                        online: conversation.isGroup
                            ? null
                            : peerOnline[conversation.peerId],
                        onTap: () {
                          if (conversation.isSystem) {
                            openSystemNotifications();
                          } else if (conversation.group != null) {
                            openGroupChat(conversation.group!);
                          } else if (conversation.peer != null) {
                            final peer = conversation.peer!;
                            openChat(peer.userId, peer.nickname, peer.avatar);
                          }
                        },
                        onTogglePin: () => toggleConversationPin(conversation),
                        onDelete: () => hideConversation(conversation),
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

class _ConnectionPill extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _ConnectionPill({required this.connected, required this.connecting});

  @override
  Widget build(BuildContext context) {
    final color = connected ? BlinStyle.success : BlinStyle.subtle;
    final text = connected
        ? '实时在线'
        : connecting
        ? '正在准备消息'
        : '消息稍后同步';
    return Tooltip(
      message: text,
      child: Semantics(
        label: text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: BlinStyle.surface(context), width: 1.5),
            boxShadow: connected
                ? [
                    BoxShadow(
                      color: BlinStyle.success.withValues(alpha: .22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final bool voiceMessageEnabled;
  final bool screenshotNoticeEnabled;
  const ContactsScreen({
    super.key,
    required this.session,
    required this.im,
    this.voiceMessageEnabled = true,
    this.screenshotNoticeEnabled = false,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final api = const ApiService();
  List<UserSearchResult> friends = [];
  List<ImGroup> groups = [];
  List<Map<String, dynamic>> notifications = [];
  int unreadCount = 0;
  int momentsUnreadCount = 0;
  Set<int> savedGroupIds = {};
  Map<int, String> groupRemarks = {};
  bool showUserId = false;
  bool showGroupNo = true;
  AppMomentsConfig momentsConfig = const AppMomentsConfig(enabled: false);
  bool loading = true;
  bool refreshing = false;
  String? error;
  StreamSubscription? friendSub;
  StreamSubscription? messageSub;
  StreamSubscription? groupProfileSub;

  @override
  void initState() {
    super.initState();
    unawaited(loadUserInfoConfig());
    unawaited(load());
    friendSub = widget.im.friendEvents.listen((_) => unawaited(load()));
    messageSub = widget.im.messages.listen(
      (_) => unawaited(load(silent: true)),
    );
    groupProfileSub = GroupProfileEvents.stream.listen((group) {
      if (!mounted) return;
      setState(() {
        groups = [
          for (final item in groups) item.id == group.id ? group : item,
        ];
      });
    });
  }

  Future<void> loadUserInfoConfig() async {
    try {
      final config = await api.getUserInfoConfig();
      if (mounted) {
        setState(() {
          showUserId = config.showUserId;
          showGroupNo = config.showGroupNo;
        });
      }
    } catch (_) {}
    try {
      final moments = await api.getMomentsConfig();
      if (mounted) setState(() => momentsConfig = moments);
    } catch (_) {}
  }

  String userSubtitle(UserSearchResult user) =>
      showUserId ? 'ID: ${user.id}  @${user.username}' : '@${user.username}';

  List<ImGroup> get savedGroups =>
      groups.where((group) => savedGroupIds.contains(group.id)).toList();

  String groupDisplayName(ImGroup group) {
    final remark = groupRemarks[group.id]?.trim() ?? '';
    return remark.isNotEmpty ? remark : group.name;
  }

  Future<void> loadGroupLocalSettings(List<ImGroup> groupList) async {
    final saved = await ConversationPreferences.loadSavedGroups(
      widget.session.id,
    );
    final remarks = <int, String>{};
    for (final group in groupList) {
      final remark = await ConversationPreferences.loadGroupRemark(
        widget.session.id,
        group.id,
      );
      if (remark.trim().isNotEmpty) remarks[group.id] = remark.trim();
    }
    savedGroupIds = saved;
    groupRemarks = remarks;
  }

  @override
  void dispose() {
    friendSub?.cancel();
    messageSub?.cancel();
    groupProfileSub?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    if (!silent && mounted) {
      setState(() {
        loading = friends.isEmpty && groups.isEmpty;
        error = null;
      });
    }
    try {
      final result = await Future.wait<Object>([
        api.getFriends(widget.session.token),
        api.getImGroups(widget.session.token),
        api.getMessageNotifications(widget.session.token, page: 1, limit: 20),
        api.getFriendRequests(widget.session.token),
        api.getMomentUnreadCount(widget.session.token).catchError((_) => 0),
      ]);
      final nextFriends = (result[0] as List<UserSearchResult>).toList()
        ..sort((a, b) => a.nickname.compareTo(b.nickname));
      final nextGroups = (result[1] as List<ImGroup>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await loadGroupLocalSettings(nextGroups);
      if (!mounted) return;
      setState(() {
        friends = nextFriends;
        groups = nextGroups;
        notifications = (result[2] as List<Map<String, dynamic>>).toList();
        unreadCount = (result[3] as List<FriendRequestItem>)
            .where((item) => item.pending)
            .length;
        momentsUnreadCount = result[4] as int;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '通讯录暂时无法更新，请稍后再试');
    } finally {
      refreshing = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openChat(UserSearchResult user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          session: widget.session,
          im: widget.im,
          peerId: user.id,
          peerName: user.nickname,
          peerAvatar: user.avatar,
          voiceMessageEnabled: widget.voiceMessageEnabled,
          screenshotNoticeEnabled: widget.screenshotNoticeEnabled,
        ),
      ),
    );
    unawaited(load(silent: true));
  }

  Future<void> openUserProfile(UserSearchResult user) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserProfileScreen(
          session: widget.session,
          user: user,
          showUserId: showUserId,
          isFriend: true,
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'message') {
      await openChat(user);
    } else if (action == 'add_friend') {
      await addFriend(user);
    }
  }

  Future<void> openGroupChat(ImGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GroupChatScreen(
          session: widget.session,
          im: widget.im,
          group: group,
          voiceMessageEnabled: widget.voiceMessageEnabled,
          screenshotNoticeEnabled: widget.screenshotNoticeEnabled,
        ),
      ),
    );
    unawaited(load(silent: true));
  }

  void openSystemNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SystemNotificationsScreen(
          session: widget.session,
          im: widget.im,
          initialItems: notifications,
          initialUnreadCount: unreadCount,
        ),
      ),
    ).then((_) => load(silent: true));
  }

  Future<void> openMoments() async {
    final config = await api.getMomentsConfig();
    if (!config.enabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('朋友圈已关闭')));
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _MomentsScreen(session: widget.session, api: api, config: config),
      ),
    );
    unawaited(load(silent: true));
  }

  Future<void> openMyGroups() async {
    final visibleGroups = savedGroups;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MyGroupsScreen(
          groups: visibleGroups,
          loading: loading,
          showUserId: showUserId,
          showGroupNo: showGroupNo,
          displayNameFor: groupDisplayName,
          onRefresh: () async {
            await load(silent: true);
            return savedGroups;
          },
          onOpenGroup: openGroupChat,
          onCreateGroup: createGroup,
        ),
      ),
    );
    unawaited(load(silent: true));
  }

  void openFriendRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FriendRequestsScreen(session: widget.session, im: widget.im),
      ),
    ).then((_) => load(silent: true));
  }

  Future<void> addFriend(UserSearchResult user) async {
    try {
      final msg = await api.addFriend(
        widget.session.token,
        user.id,
        message: '你好，我想添加你为好友',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加好友失败：$e')));
    }
  }

  Future<void> showFriendSearchDialog() async {
    final selected = await Navigator.push<UserSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FriendSearchScreen(friends: friends, showUserId: showUserId),
      ),
    );
    if (selected == null || !mounted) return;
    await openUserProfile(selected);
  }

  Future<void> createGroup() async {
    if (friends.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要两位好友才能创建群聊')));
      return;
    }
    final fallbackName = widget.session.nickname?.trim().isNotEmpty == true
        ? widget.session.nickname!.trim()
        : '我的群聊';
    final result = await _showCreateGroupDialog(
      context: context,
      friends: friends,
      fallbackName: fallbackName,
      userSubtitle: userSubtitle,
    );
    if (result == null) return;
    final rawName = '${result['name'] ?? ''}'.trim();
    final name = rawName.isEmpty ? fallbackName : rawName;
    final memberIds =
        (result['members'] as List?)?.cast<int>() ?? const <int>[];
    if (memberIds.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少邀请两位好友才能创建群聊')));
      return;
    }
    try {
      final group = await api.createImGroup(
        token: widget.session.token,
        name: name,
        memberIds: memberIds,
      );
      await load(silent: true);
      if (mounted) await openGroupChat(group);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('建群失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '通讯录',
            subtitle: '${friends.length} 位好友 · ${groups.length} 个群聊',
            actions: [
              ShellAction(
                icon: Icons.search_rounded,
                onTap: showFriendSearchDialog,
                tooltip: '搜索好友',
              ),
              const SizedBox(width: 8),
              ShellAction(
                icon: Icons.group_add_rounded,
                onTap: createGroup,
                tooltip: '创建群聊',
              ),
            ],
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  _ContactActionTile(
                    icon: Icons.person_add_alt_1_outlined,
                    title: '新的朋友',
                    subtitle: unreadCount > 0 ? '$unreadCount 条待处理申请' : '好友申请',
                    badge: unreadCount,
                    onTap: openFriendRequests,
                  ),
                  _ContactActionTile(
                    icon: Icons.groups_outlined,
                    title: '我的群聊',
                    subtitle: savedGroups.isEmpty
                        ? '暂无保存的群聊'
                        : '${savedGroups.length} 个群聊',
                    onTap: openMyGroups,
                  ),
                  _ContactActionTile(
                    icon: Icons.notifications_none_rounded,
                    title: '系统通知',
                    subtitle: '账号消息和系统提醒',
                    onTap: openSystemNotifications,
                  ),
                  if (momentsConfig.enabled)
                    _ContactActionTile(
                      icon: Icons.auto_graph_outlined,
                      title: '朋友圈',
                      subtitle: momentsConfig.visibilityLabel,
                      badge: momentsUnreadCount,
                      onTap: openMoments,
                    ),
                  const _SectionTitle('好友'),
                  if (loading)
                    const SizedBox.shrink()
                  else if (friends.isEmpty)
                    _ContactEmptyTile(
                      icon: Icons.person_search_outlined,
                      text: '暂无好友，好友申请会显示在新的朋友里。',
                      onTap: openFriendRequests,
                    )
                  else
                    ...friends.map(
                      (user) => _ChatTile(
                        onTap: () => openUserProfile(user),
                        avatar: user.avatar,
                        name: user.nickname,
                        subtitle: userSubtitle(user),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.subtle,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FriendSearchScreen extends StatefulWidget {
  final List<UserSearchResult> friends;
  final bool showUserId;

  const _FriendSearchScreen({required this.friends, required this.showUserId});

  @override
  State<_FriendSearchScreen> createState() => _FriendSearchScreenState();
}

class _FriendSearchScreenState extends State<_FriendSearchScreen> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  List<UserSearchResult> get results {
    final keyword = controller.text.trim().toLowerCase();
    if (keyword.isEmpty) return widget.friends;
    return widget.friends.where((user) {
      final nickname = user.nickname.toLowerCase();
      final username = user.username.toLowerCase();
      final id = '${user.id}';
      return nickname.contains(keyword) ||
          username.contains(keyword) ||
          id.contains(keyword);
    }).toList();
  }

  String _subtitle(UserSearchResult user) => widget.showUserId
      ? 'ID: ${user.id}  @${user.username}'
      : '@${user.username}';

  @override
  Widget build(BuildContext context) {
    final items = results;
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '搜索好友',
              subtitle: '${widget.friends.length} 位好友',
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
                    SoftCard(
                      padding: const EdgeInsets.all(BlinStyle.cardPadding),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索昵称或用户名',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: controller.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    controller.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: BlinStyle.moduleGap),
                    if (widget.friends.isEmpty)
                      const SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.people_outline_rounded,
                          title: '暂无好友',
                          subtitle: '好友建立后，可以在这里搜索并快速进入聊天。',
                        ),
                      )
                    else if (items.isEmpty)
                      const SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.person_search_outlined,
                          title: '没有找到好友',
                          subtitle: '换个昵称、用户名或用户 ID 试试。',
                        ),
                      )
                    else
                      for (final user in items)
                        _ChatTile(
                          onTap: () => Navigator.pop(context, user),
                          avatar: user.avatar,
                          name: user.nickname,
                          subtitle: _subtitle(user),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: BlinStyle.subtle,
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

class _MyGroupsScreen extends StatefulWidget {
  final List<ImGroup> groups;
  final bool loading;
  final bool showUserId;
  final bool showGroupNo;
  final String Function(ImGroup) displayNameFor;
  final Future<List<ImGroup>> Function() onRefresh;
  final ValueChanged<ImGroup> onOpenGroup;
  final VoidCallback onCreateGroup;

  const _MyGroupsScreen({
    required this.groups,
    required this.loading,
    required this.showUserId,
    required this.showGroupNo,
    required this.displayNameFor,
    required this.onRefresh,
    required this.onOpenGroup,
    required this.onCreateGroup,
  });

  @override
  State<_MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends State<_MyGroupsScreen> {
  late List<ImGroup> groups = widget.groups;
  late bool loading = widget.loading;

  String _subtitle(ImGroup group) {
    final count = '${group.memberCount}人';
    if (!widget.showGroupNo) return count;
    final no = group.groupNo.isEmpty ? '${group.id}' : group.groupNo;
    return '$count · 群号 $no';
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final next = await widget.onRefresh();
      if (mounted) setState(() => groups = next);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '我的群聊',
            subtitle: '${groups.length} 个群聊',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              TsddAssetIconButton(
                asset: 'assets/tsdd/common/msg_add.png',
                onTap: widget.onCreateGroup,
                tooltip: '创建群聊',
              ),
            ],
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: _refresh,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (loading)
                    const _ChatSkeletonList()
                  else if (groups.isEmpty)
                    _ContactEmptyTile(
                      icon: Icons.groups_outlined,
                      text: '暂无群聊，可以从右上角创建群聊。',
                      onTap: widget.onCreateGroup,
                    )
                  else
                    ...groups.map(
                      (group) => _ChatTile(
                        onTap: () => widget.onOpenGroup(group),
                        avatar: group.avatar,
                        name: widget.displayNameFor(group),
                        subtitle: _subtitle(group),
                        fallbackIcon: Icons.groups_rounded,
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.subtle,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SystemNotificationsScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final List<Map<String, dynamic>> initialItems;
  final int initialUnreadCount;
  const _SystemNotificationsScreen({
    required this.session,
    required this.im,
    required this.initialItems,
    required this.initialUnreadCount,
  });

  @override
  State<_SystemNotificationsScreen> createState() =>
      _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState
    extends State<_SystemNotificationsScreen> {
  final api = const ApiService();
  late List<Map<String, dynamic>> items = widget.initialItems;
  late int unreadCount = widget.initialUnreadCount;
  bool loading = false;
  bool clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
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
    setState(() => loading = true);
    try {
      final list = await api.getMessageNotifications(
        widget.session.token,
        page: 1,
        limit: 50,
      );
      final unread = await api.getMessageNotifications(
        widget.session.token,
        page: 1,
        limit: 50,
        unreadOnly: true,
      );
      if (mounted) {
        setState(() {
          items = list;
          unreadCount = unread.length;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markAllRead() async {
    if (clearing) return;
    setState(() => clearing = true);
    try {
      await api.clearMessageNotification(widget.session.token);
      if (mounted) {
        setState(() {
          unreadCount = 0;
          items = items.map((e) => {...e, '_read_local': true}).toList();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('系统通知已全部标记为已读')));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('一键已读失败，请稍后再试')));
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  String _notificationId(Map<String, dynamic> row) =>
      _pick(row, const ['id', 'notification_id', 'message_id', 'notice_id']);

  bool _isUnread(Map<String, dynamic> row) {
    if (row['_read_local'] == true) return false;
    final raw =
        '${row['is_read'] ?? row['read'] ?? row['status'] ?? row['isread'] ?? ''}'
            .toLowerCase()
            .trim();
    if (raw.isEmpty) return true;
    return raw == '0' || raw == 'false' || raw == 'unread' || raw == '未读';
  }

  Future<void> openNotification(Map<String, dynamic> row) async {
    final id = _notificationId(row);
    final wasUnread = _isUnread(row);
    final handled = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .32),
      builder: (_) => _NotificationDetailDialog(
        row: row,
        token: widget.session.token,
        api: api,
        im: widget.im,
        session: widget.session,
      ),
    );
    if (handled == true) unawaited(load());
    if (wasUnread) {
      try {
        await api.clearMessageNotification(
          widget.session.token,
          notificationId: id,
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          unreadCount = unreadCount > 0 ? unreadCount - 1 : 0;
          items = items
              .map((e) => identical(e, row) ? {...e, '_read_local': true} : e)
              .toList();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '系统通知',
            subtitle: '系统提醒和账号消息',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              if (unreadCount > 0)
                IconButton(
                  onPressed: clearing ? null : markAllRead,
                  icon: clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all_rounded),
                  tooltip: '一键已读',
                ),
            ],
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (loading && items.isEmpty)
                    const _ChatSkeletonList()
                  else if (items.isEmpty)
                    NativeListRow(
                      leading: const NativeIconBox(
                        icon: Icons.notifications_none_rounded,
                        color: BlinStyle.subtle,
                        size: 40,
                      ),
                      title: '暂无系统通知',
                      subtitle: '系统提醒会显示在这里',
                      minHeight: 68,
                    )
                  else
                    ...items.map((row) {
                      final title = _pick(row, const [
                        'title',
                        'type_name',
                        'notification_type',
                      ], '系统通知');
                      final content = _pick(row, const [
                        'content',
                        'message',
                        'msg',
                        'text',
                      ], '你有一条新的系统通知');
                      final time = _pick(row, const [
                        'create_time',
                        'time',
                        'created_at',
                        'time_ago',
                      ]);
                      final unread = _isUnread(row);
                      return NativeListRow(
                        onTap: () => openNotification(row),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const NativeIconBox(
                              icon: Icons.notifications_none_rounded,
                              color: BlinStyle.primary,
                              size: 42,
                            ),
                            if (unread)
                              Positioned(
                                right: -1,
                                top: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF3B30),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: title,
                        subtitle: content,
                        meta: _formatConversationTime(time),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.subtle,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FriendRequestsScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  const _FriendRequestsScreen({required this.session, required this.im});

  @override
  State<_FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<_FriendRequestsScreen> {
  final api = const ApiService();
  List<FriendRequestItem> items = [];
  bool loading = true;
  final Set<int> handling = <int>{};

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final list = await api.getFriendRequests(widget.session.token);
      if (mounted) setState(() => items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('好友申请读取失败：$e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> handle(FriendRequestItem item, bool accept) async {
    if (handling.contains(item.fromUserId)) return;
    setState(() => handling.add(item.fromUserId));
    try {
      final msg = await api.handleFriendRequest(
        widget.session.token,
        userId: item.fromUserId,
        accept: accept,
      );
      if (accept) {
        await api.sendMessage(
          token: widget.session.token,
          receiverId: item.fromUserId,
          content: '我已通过你的好友申请，现在我们可以开始聊天了',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('处理失败：$e')));
      }
    } finally {
      if (mounted) setState(() => handling.remove(item.fromUserId));
    }
  }

  Future<void> deleteRequest(FriendRequestItem item) async {
    if (handling.contains(item.fromUserId)) return;
    final confirmed = await _showBlinConfirm(
      context,
      title: '删除记录',
      message: '删除 ${item.nickname} 的好友申请记录？',
      icon: Icons.delete_outline_rounded,
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    setState(() => handling.add(item.fromUserId));
    try {
      final msg = await api.deleteFriendRequest(
        widget.session.token,
        userId: item.fromUserId,
      );
      if (!mounted) return;
      setState(() {
        items.removeWhere((row) => row.fromUserId == item.fromUserId);
        handling.remove(item.fromUserId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    } finally {
      if (mounted) setState(() => handling.remove(item.fromUserId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '新的朋友',
            subtitle: '好友申请独立处理',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: BlinRefresh(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (loading && items.isEmpty)
                    const _ChatSkeletonList()
                  else if (items.isEmpty)
                    const NativeListRow(
                      leading: NativeIconBox(
                        icon: Icons.person_add_disabled_outlined,
                        color: BlinStyle.subtle,
                        size: 40,
                      ),
                      title: '暂无好友申请',
                      subtitle: '新的好友申请会显示在这里',
                      minHeight: 68,
                    )
                  else
                    for (final item in items)
                      Dismissible(
                        key: ValueKey('friend_request_${item.fromUserId}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await deleteRequest(item);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Theme.of(context).colorScheme.error,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        child: NativeListRow(
                          leading: AppAvatar(
                            imageUrl: item.avatar,
                            name: item.nickname,
                            size: 44,
                          ),
                          title: item.nickname,
                          subtitle: item.message,
                          meta: item.statusText,
                          minHeight: 76,
                          trailing: item.pending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          handling.contains(item.fromUserId)
                                          ? null
                                          : () => handle(item, false),
                                      child: const Text('拒绝'),
                                    ),
                                    const SizedBox(width: 6),
                                    FilledButton(
                                      onPressed:
                                          handling.contains(item.fromUserId)
                                          ? null
                                          : () => handle(item, true),
                                      child: const Text('同意'),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  tooltip: '删除记录',
                                  onPressed: handling.contains(item.fromUserId)
                                      ? null
                                      : () => deleteRequest(item),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: BlinStyle.subtle,
                                  ),
                                ),
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

class _NotificationDetailDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  final String token;
  final ApiService api;
  final ImService im;
  final UserSession session;
  const _NotificationDetailDialog({
    required this.row,
    required this.token,
    required this.api,
    required this.im,
    required this.session,
  });

  @override
  State<_NotificationDetailDialog> createState() =>
      _NotificationDetailDialogState();
}

class _NotificationDetailDialogState extends State<_NotificationDetailDialog> {
  String _pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = widget.row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  IconData get icon {
    final type = _pick(const [
      'type',
      'notification_type',
      'action',
    ]).toLowerCase();
    final text =
        '${_pick(const ['title', 'type_name'])} ${_pick(const ['content', 'message', 'msg', 'text'])}';
    if (type.contains('account') || text.contains('账号'))
      return Icons.account_circle_rounded;
    if (type.contains('group') || text.contains('群'))
      return Icons.groups_rounded;
    if (type.contains('reply') || text.contains('回复'))
      return Icons.mark_chat_unread_rounded;
    return Icons.notifications_active_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final title = _pick(const [
      'title',
      'type_name',
      'notification_type',
    ], '系统通知');
    final content = _pick(const [
      'content',
      'message',
      'msg',
      'text',
    ], '你有一条新的互动通知');
    final time = _pick(const ['create_time', 'time', 'created_at', 'time_ago']);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: SoftCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NativeIconBox(icon: icon, color: BlinStyle.primary, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(content, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.done_rounded),
                label: const Text('已阅读'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatSkeletonList extends StatelessWidget {
  const _ChatSkeletonList();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      5,
      (i) => Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.fromLTRB(15, 10, 12, 0),
        color: BlinStyle.surface(context),
        child: Column(
          children: [
            Row(
              children: [
                const _ChatSkeletonBox(width: 50, height: 50, radius: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ChatSkeletonBox(
                        width: i.isEven ? 130 : 170,
                        height: 16,
                        radius: 999,
                      ),
                      const SizedBox(height: 10),
                      const _ChatSkeletonBox(
                        width: double.infinity,
                        height: 12,
                        radius: 999,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 60, top: 9),
              child: Divider(
                height: 1,
                thickness: .5,
                color: BlinStyle.hairline(context, .70).color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChatSkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const _ChatSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: BlinStyle.softFill,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
    color: BlinStyle.page(context),
    child: Text(
      text,
      style: const TextStyle(
        color: BlinStyle.subtle,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _CreateActionSheet extends StatelessWidget {
  final VoidCallback onNearby;
  final VoidCallback onCreateGroup;
  final VoidCallback onAddFriend;

  const _CreateActionSheet({
    required this.onNearby,
    required this.onCreateGroup,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
        child: SoftCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: BlinStyle.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text('快速操作', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('选择要发起的操作', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _CreateSheetAction(
                      icon: Icons.person_add_alt_1_outlined,
                      title: '加好友',
                      subtitle: '搜索账号添加好友',
                      color: BlinStyle.primary,
                      onTap: onAddFriend,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CreateSheetAction(
                      icon: Icons.location_on_outlined,
                      title: '附近人',
                      subtitle: '发现身边的人',
                      color: BlinStyle.success,
                      onTap: onNearby,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CreateSheetWideAction(
                icon: Icons.groups_outlined,
                title: '创建群聊',
                subtitle: '选择好友发起新的群会话',
                onTap: onCreateGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateSheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CreateSheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NativeIconBox(icon: icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: BlinStyle.textPrimary(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _CreateSheetWideAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateSheetWideAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BlinStyle.iconSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BlinStyle.hairline(context, .62).color),
        ),
        child: Row(
          children: [
            NativeIconBox(icon: icon, color: BlinStyle.primary, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: BlinStyle.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
          ],
        ),
      ),
    ),
  );
}

class _ScanUserActionSheet extends StatelessWidget {
  final UserSearchResult user;
  final bool showUserId;
  final bool isFriend;
  final VoidCallback onAdd;
  final VoidCallback onChat;

  const _ScanUserActionSheet({
    required this.user,
    required this.showUserId,
    required this.isFriend,
    required this.onAdd,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
        child: SoftCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: BlinStyle.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              NativeListRow(
                leading: AppAvatar(
                  imageUrl: user.avatar,
                  name: user.nickname,
                  size: 52,
                ),
                title: user.nickname,
                subtitle: showUserId
                    ? 'ID: ${user.id}  @${user.username}'
                    : '@${user.username}',
                minHeight: 68,
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('发消息'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isFriend ? null : onAdd,
                      icon: Icon(
                        isFriend
                            ? Icons.check_circle_outline_rounded
                            : Icons.person_add_alt_1_rounded,
                      ),
                      label: Text(isFriend ? '已添加' : '申请好友'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanGroupActionSheet extends StatelessWidget {
  final ImGroup group;
  final bool inGroup;
  final bool showGroupNo;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  const _ScanGroupActionSheet({
    required this.group,
    required this.inGroup,
    required this.showGroupNo,
    required this.onJoin,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final subtitle = [
      '${group.memberCount}人',
      if (showGroupNo && group.groupNo.isNotEmpty) '群号 ${group.groupNo}',
    ].join(' · ');
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
        child: SoftCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: BlinStyle.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              NativeListRow(
                leading: AppAvatar(
                  imageUrl: group.avatar,
                  name: group.name,
                  size: 52,
                  fallbackIcon: Icons.groups_rounded,
                ),
                title: group.name,
                subtitle: subtitle,
                minHeight: 68,
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: inGroup ? onOpen : onJoin,
                icon: Icon(
                  inGroup
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.group_add_rounded,
                ),
                label: Text(inGroup ? '进入群聊' : '加入群聊'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HomeSearchResultKind { conversation, peerMessage, group, groupMessage }

class _HomeSearchSelection {
  final int peerId;
  final String peerName;
  final String peerAvatar;
  final ImGroup? group;

  const _HomeSearchSelection.peer({
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  }) : group = null;

  const _HomeSearchSelection.group(this.group)
    : peerId = 0,
      peerName = '',
      peerAvatar = '';
}

class _HomeSearchResult {
  final _HomeSearchResultKind kind;
  final String title;
  final String subtitle;
  final String meta;
  final String avatar;
  final IconData? fallbackIcon;
  final int peerId;
  final String peerName;
  final String peerAvatar;
  final ImGroup? group;

  const _HomeSearchResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.meta = '',
    this.avatar = '',
    this.fallbackIcon,
    this.peerId = 0,
    this.peerName = '',
    this.peerAvatar = '',
    this.group,
  });

  bool get isGroup => group != null;

  _HomeSearchSelection get selection => isGroup
      ? _HomeSearchSelection.group(group)
      : _HomeSearchSelection.peer(
          peerId: peerId,
          peerName: peerName,
          peerAvatar: peerAvatar,
        );
}

class _HomeMessageSearchScreen extends StatefulWidget {
  final UserSession session;
  final List<ConversationItem> conversations;
  final List<UserSearchResult> friends;
  final List<ImGroup> groups;
  final Map<int, String> groupRemarks;
  final bool showUserId;
  final bool showGroupNo;

  const _HomeMessageSearchScreen({
    required this.session,
    required this.conversations,
    required this.friends,
    required this.groups,
    required this.groupRemarks,
    required this.showUserId,
    required this.showGroupNo,
  });

  @override
  State<_HomeMessageSearchScreen> createState() =>
      _HomeMessageSearchScreenState();
}

class _HomeMessageSearchScreenState extends State<_HomeMessageSearchScreen> {
  final api = const ApiService();
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final results = <_HomeSearchResult>[];
  Timer? debounce;
  int generation = 0;
  bool searching = false;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void onKeywordChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(search(value));
    });
    if (value.trim().isEmpty) {
      generation++;
      setState(() {
        results.clear();
        searching = false;
        message = null;
      });
    }
  }

  Future<void> search(String raw) async {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    final current = ++generation;
    final local = _localResults(keyword);
    setState(() {
      results
        ..clear()
        ..addAll(local);
      searching = true;
      message = null;
    });
    final history = await _historyResults(keyword, current);
    if (!mounted || current != generation) return;
    setState(() {
      results
        ..clear()
        ..addAll(_dedupeResults([...local, ...history]));
      searching = false;
      message = results.isEmpty ? '没有找到相关聊天记录' : null;
    });
  }

  List<_HomeSearchResult> _localResults(String keyword) {
    final lower = keyword.toLowerCase();
    final output = <_HomeSearchResult>[];
    for (final item in widget.conversations) {
      if (!_containsAny(lower, [
        item.nickname,
        item.username,
        item.preview,
        item.msgTime,
      ])) {
        continue;
      }
      output.add(
        _HomeSearchResult(
          kind: _HomeSearchResultKind.conversation,
          title: item.nickname,
          subtitle: item.preview.isEmpty ? '@${item.username}' : item.preview,
          meta: item.msgTime,
          avatar: item.avatar,
          peerId: item.userId,
          peerName: item.nickname,
          peerAvatar: item.avatar,
        ),
      );
    }
    for (final friend in widget.friends) {
      if (widget.conversations.any((item) => item.userId == friend.id)) {
        continue;
      }
      if (!_containsAny(lower, [
        friend.nickname,
        friend.username,
        if (widget.showUserId) '${friend.id}',
      ])) {
        continue;
      }
      output.add(
        _HomeSearchResult(
          kind: _HomeSearchResultKind.conversation,
          title: friend.nickname,
          subtitle: widget.showUserId
              ? 'ID ${friend.id} · @${friend.username}'
              : '@${friend.username}',
          avatar: friend.avatar,
          peerId: friend.id,
          peerName: friend.nickname,
          peerAvatar: friend.avatar,
        ),
      );
    }
    for (final group in widget.groups) {
      final title = _groupTitle(group);
      final groupNo = group.groupNo.isEmpty ? '${group.id}' : group.groupNo;
      if (!_containsAny(lower, [
        title,
        group.name,
        if (widget.showGroupNo) groupNo,
      ])) {
        continue;
      }
      output.add(
        _HomeSearchResult(
          kind: _HomeSearchResultKind.group,
          title: title,
          subtitle: widget.showGroupNo
              ? '${group.memberCount}人 · 群号 $groupNo'
              : '${group.memberCount}人',
          avatar: group.avatar,
          fallbackIcon: Icons.groups_rounded,
          group: group,
        ),
      );
    }
    return output;
  }

  Future<List<_HomeSearchResult>> _historyResults(
    String keyword,
    int current,
  ) async {
    final output = <_HomeSearchResult>[];
    final lower = keyword.toLowerCase();
    for (final item in widget.conversations) {
      if (!mounted || current != generation) return output;
      try {
        final list = await api.getChatLog(
          token: widget.session.token,
          receiverId: item.userId,
          myId: widget.session.id,
          page: 1,
          limit: 80,
        );
        for (final message in list.reversed) {
          final preview = message.preview.trim();
          if (preview.isEmpty || !preview.toLowerCase().contains(lower)) {
            continue;
          }
          output.add(
            _HomeSearchResult(
              kind: _HomeSearchResultKind.peerMessage,
              title: item.nickname,
              subtitle: preview,
              meta: _formatConversationTime(
                message.createTime.toIso8601String(),
              ),
              avatar: item.avatar,
              peerId: item.userId,
              peerName: item.nickname,
              peerAvatar: item.avatar,
            ),
          );
          break;
        }
      } catch (_) {}
    }
    for (final group in widget.groups) {
      if (!mounted || current != generation) return output;
      try {
        final list = await api.getGroupChatLog(
          token: widget.session.token,
          groupId: group.id,
          myId: widget.session.id,
          page: 1,
          limit: 80,
        );
        for (final message in list.reversed) {
          final preview = message.preview.trim();
          if (preview.isEmpty || !preview.toLowerCase().contains(lower)) {
            continue;
          }
          output.add(
            _HomeSearchResult(
              kind: _HomeSearchResultKind.groupMessage,
              title: _groupTitle(group),
              subtitle: preview,
              meta: _formatConversationTime(
                message.createTime.toIso8601String(),
              ),
              avatar: group.avatar,
              fallbackIcon: Icons.groups_rounded,
              group: group,
            ),
          );
          break;
        }
      } catch (_) {}
    }
    return output;
  }

  List<_HomeSearchResult> _dedupeResults(List<_HomeSearchResult> source) {
    final seen = <String>{};
    final output = <_HomeSearchResult>[];
    for (final item in source) {
      final key =
          '${item.kind}:${item.peerId}:${item.group?.id ?? 0}:${item.subtitle}';
      if (seen.add(key)) output.add(item);
    }
    return output;
  }

  bool _containsAny(String lowerKeyword, Iterable<String> values) {
    for (final value in values) {
      final text = value.trim().toLowerCase();
      if (text.isNotEmpty && text.contains(lowerKeyword)) return true;
    }
    return false;
  }

  String _groupTitle(ImGroup group) {
    final remark = widget.groupRemarks[group.id]?.trim() ?? '';
    return remark.isNotEmpty ? remark : group.name;
  }

  IconData _resultIcon(_HomeSearchResult item) {
    switch (item.kind) {
      case _HomeSearchResultKind.conversation:
        return Icons.chat_bubble_outline_rounded;
      case _HomeSearchResultKind.peerMessage:
        return Icons.manage_search_rounded;
      case _HomeSearchResultKind.group:
        return Icons.groups_outlined;
      case _HomeSearchResultKind.groupMessage:
        return Icons.forum_outlined;
    }
  }

  String _resultTypeText(_HomeSearchResult item) {
    switch (item.kind) {
      case _HomeSearchResultKind.conversation:
        return '会话';
      case _HomeSearchResultKind.peerMessage:
        return '聊天记录';
      case _HomeSearchResultKind.group:
        return '群聊';
      case _HomeSearchResultKind.groupMessage:
        return '群聊记录';
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyword = controller.text.trim();
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '搜索',
              subtitle: '聊天、群聊和聊天记录',
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
                    SoftCard(
                      padding: const EdgeInsets.all(BlinStyle.cardPadding),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: onKeywordChanged,
                        onSubmitted: (value) => unawaited(search(value)),
                        decoration: InputDecoration(
                          hintText: '搜索聊天记录、消息列表、群聊',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: keyword.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    controller.clear();
                                    onKeywordChanged('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (searching)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      const SizedBox(height: 2),
                    const SizedBox(height: 14),
                    if (keyword.isEmpty)
                      const SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.manage_search_rounded,
                          title: '搜索聊天内容',
                          subtitle: '可以搜索消息列表、好友昵称、群聊名称和最近聊天记录',
                        ),
                      )
                    else if (message != null)
                      SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.search_off_rounded,
                          title: '没有结果',
                          subtitle: message!,
                        ),
                      )
                    else
                      for (final item in results)
                        SoftCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: NativeListRow(
                            leading: AppAvatar(
                              imageUrl: item.avatar,
                              name: item.title,
                              size: 44,
                              fallbackIcon:
                                  item.fallbackIcon ?? _resultIcon(item),
                            ),
                            title: item.title,
                            subtitle: item.subtitle,
                            meta: item.meta.isNotEmpty
                                ? item.meta
                                : _resultTypeText(item),
                            minHeight: 66,
                            onTap: () => Navigator.pop(context, item.selection),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: BlinStyle.subtle,
                            ),
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

class _SearchUserScreen extends StatefulWidget {
  final UserSession session;
  final String initialKeyword;
  final bool showUserId;
  final Set<int> friendIds;
  final Future<void> Function(UserSearchResult user) onAddFriend;

  const _SearchUserScreen({
    required this.session,
    required this.onAddFriend,
    this.friendIds = const <int>{},
    this.showUserId = false,
    this.initialKeyword = '',
  });

  @override
  State<_SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<_SearchUserScreen> {
  final api = const ApiService();
  late final TextEditingController controller;
  final focusNode = FocusNode();
  late final Set<int> friendIds = {...widget.friendIds};
  List<UserSearchResult> users = [];
  bool loading = false;
  String? message;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialKeyword);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusNode.requestFocus();
      if (controller.text.trim().isNotEmpty) unawaited(search());
    });
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final keyword = controller.text.trim();
    if (keyword.isEmpty || loading) return;
    setState(() {
      loading = true;
      message = null;
      users = [];
    });
    try {
      final result = await api.searchUsers(widget.session.token, keyword);
      final filtered = result
          .where((user) => user.id != widget.session.id)
          .toList();
      if (!mounted) return;
      setState(() {
        users = filtered;
        message = filtered.isEmpty ? '没有找到该用户' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => message = '搜索暂时不可用：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addFriend(UserSearchResult user) async {
    if (_isFriend(user.id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('你们已经是好友')));
      return;
    }
    await widget.onAddFriend(user);
    if (mounted) setState(() => friendIds.add(user.id));
  }

  bool _isFriend(int userId) => friendIds.contains(userId);

  Future<void> openUserProfile(UserSearchResult user) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserProfileScreen(
          session: widget.session,
          user: user,
          showUserId: widget.showUserId,
          isFriend: _isFriend(user.id),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'message') {
      Navigator.pop(
        context,
        _SearchUserProfileAction(action: 'message', user: user),
      );
    } else if (action == 'add_friend') {
      if (_isFriend(user.id)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('你们已经是好友')));
        return;
      }
      await addFriend(user);
    }
  }

  Future<void> scanQr() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final parsed = _QrPayload.parse(raw.trim());
    if (parsed.isGroup ||
        parsed.isExternalUrl ||
        parsed.isInternalUnsupported) {
      Navigator.pop(context, _ScannedQrIntent(raw.trim()));
      return;
    }
    setState(() {
      loading = true;
      message = null;
      users = [];
    });
    try {
      final user = await api.scanUserQr(widget.session.token, raw.trim());
      if (!mounted) return;
      setState(() {
        users = user.id == widget.session.id ? [] : [user];
        message = user.id == widget.session.id ? '不能添加自己' : null;
      });
    } catch (e) {
      if (mounted) setState(() => message = '二维码识别失败：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSearch = controller.text.trim().isNotEmpty && !loading;
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '添加好友',
              subtitle: '搜索用户名或扫描二维码',
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              actions: [
                ShellAction(
                  icon: Icons.qr_code_scanner_rounded,
                  onTap: scanQr,
                  tooltip: '扫一扫',
                ),
              ],
            ),
            Expanded(
              child: ModuleContent(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SoftCard(
                      padding: const EdgeInsets.all(BlinStyle.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: controller,
                            focusNode: focusNode,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              setState(() {
                                if (value.trim().isEmpty) {
                                  users = [];
                                  message = null;
                                }
                              });
                            },
                            onSubmitted: (_) => unawaited(search()),
                            decoration: InputDecoration(
                              hintText: '输入用户名精确搜索',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                onPressed: controller.text.trim().isEmpty
                                    ? null
                                    : () {
                                        controller.clear();
                                        setState(() {
                                          users = [];
                                          message = null;
                                        });
                                      },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: scanQr,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                  ),
                                  label: const Text('扫码添加'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: canSearch
                                      ? () => unawaited(search())
                                      : null,
                                  icon: loading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search_rounded),
                                  label: const Text('搜索'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BlinStyle.moduleGap),
                    if (loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (message != null)
                      SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.person_search_outlined,
                          title: message!.contains('没有') ? '没有找到用户' : '搜索暂不可用',
                          subtitle: message!,
                        ),
                      )
                    else if (users.isEmpty)
                      const SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.person_add_alt_1_outlined,
                          title: '搜索好友',
                          subtitle: '输入用户名后搜索，也可以扫描对方二维码',
                        ),
                      )
                    else
                      for (final user in users)
                        SoftCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _SearchUserResultRow(
                            user: user,
                            showUserId: widget.showUserId,
                            isFriend: _isFriend(user.id),
                            onOpen: () => unawaited(openUserProfile(user)),
                            onAdd: () => unawaited(addFriend(user)),
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

class _SearchUserResultRow extends StatelessWidget {
  final UserSearchResult user;
  final bool showUserId;
  final bool isFriend;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const _SearchUserResultRow({
    required this.user,
    required this.showUserId,
    required this.isFriend,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: AppAvatar(imageUrl: user.avatar, name: user.nickname, size: 42),
    title: user.nickname,
    subtitle: showUserId
        ? 'ID: ${user.id}  @${user.username}'
        : '@${user.username}',
    minHeight: 64,
    onTap: onOpen,
    trailing: TextButton(
      onPressed: isFriend ? null : onAdd,
      style: TextButton.styleFrom(
        backgroundColor: isFriend
            ? BlinStyle.iconSurface(context)
            : BlinStyle.primary,
        foregroundColor: isFriend ? BlinStyle.subtle : Colors.white,
        minimumSize: const Size(54, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        isFriend ? '已添加' : '申请',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _SearchUserProfileScreen extends StatefulWidget {
  final UserSession session;
  final UserSearchResult user;
  final bool showUserId;
  final bool isFriend;

  const _SearchUserProfileScreen({
    required this.session,
    required this.user,
    required this.showUserId,
    required this.isFriend,
  });

  @override
  State<_SearchUserProfileScreen> createState() =>
      _SearchUserProfileScreenState();
}

class _SearchUserProfileScreenState extends State<_SearchUserProfileScreen> {
  final api = const ApiService();
  UserPublicProfile? profile;
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
      final next = await api.getUserInformation(
        token: widget.session.token,
        userId: widget.user.id,
      );
      if (mounted) setState(() => profile = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get displayName {
    final value = profile?.nickname.trim() ?? '';
    return value.isNotEmpty ? value : widget.user.nickname;
  }

  String get avatar {
    final value = profile?.avatar.trim() ?? '';
    return value.isNotEmpty ? value : widget.user.avatar;
  }

  String get username {
    final value =
        (profile?.username.trim().isNotEmpty == true
                ? profile!.username
                : widget.user.username)
            .trim();
    return value.isNotEmpty ? '@$value' : '';
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final signature = p?.signature.trim() ?? '';
    final sexName = p?.sexName.trim() ?? '';
    final level = p?.level.trim() ?? '';
    final createTime = p?.createTime.trim() ?? '';
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '个人主页',
              subtitle: displayName,
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
                    SoftCard(
                      child: InfoLine(
                        avatar: AppAvatar(
                          imageUrl: avatar,
                          name: displayName,
                          size: 72,
                        ),
                        title: displayName,
                        subtitle: [
                          if (username.isNotEmpty) username,
                          if (widget.showUserId) 'ID ${widget.user.id}',
                        ].join(' · '),
                        meta: signature.isNotEmpty ? signature : null,
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(
                          '资料暂时无法更新，已显示搜索结果',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SoftCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _ProfileActionRow(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: '发消息',
                            onTap: () => Navigator.pop(context, 'message'),
                          ),
                          Divider(
                            height: 1,
                            indent: 68,
                            color: BlinStyle.hairline(context, .55).color,
                          ),
                          _ProfileActionRow(
                            icon: widget.isFriend
                                ? Icons.check_circle_outline_rounded
                                : Icons.person_add_alt_1_outlined,
                            title: widget.isFriend ? '已添加好友' : '添加到通讯录',
                            enabled: !widget.isFriend,
                            onTap: widget.isFriend
                                ? null
                                : () => Navigator.pop(context, 'add_friend'),
                          ),
                        ],
                      ),
                    ),
                    if (signature.isNotEmpty ||
                        sexName.isNotEmpty ||
                        level.isNotEmpty ||
                        createTime.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SoftCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            if (signature.isNotEmpty)
                              _ProfileActionRow(
                                icon: Icons.edit_note_rounded,
                                title: '个性签名',
                                trailing: signature,
                                enabled: false,
                              ),
                            if (sexName.isNotEmpty)
                              _ProfileActionRow(
                                icon: Icons.person_outline_rounded,
                                title: '性别',
                                trailing: sexName,
                                enabled: false,
                              ),
                            if (level.isNotEmpty)
                              _ProfileActionRow(
                                icon: Icons.workspace_premium_outlined,
                                title: '等级',
                                trailing: level,
                                enabled: false,
                              ),
                            if (createTime.isNotEmpty)
                              _ProfileActionRow(
                                icon: Icons.event_available_outlined,
                                title: '加入时间',
                                trailing: createTime,
                                enabled: false,
                              ),
                          ],
                        ),
                      ),
                    ],
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

class _ProfileActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const _ProfileActionRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          NativeIconBox(
            icon: icon,
            color: enabled ? BlinStyle.primary : BlinStyle.subtle,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: enabled
                    ? BlinStyle.textPrimary(context)
                    : BlinStyle.subtle,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null && trailing!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                trailing!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ] else if (onTap != null && enabled)
            const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
        ],
      ),
    ),
  );
}

class _NearbyPeopleScreen extends StatelessWidget {
  const _NearbyPeopleScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '附近人',
            subtitle: '发现身边的用户',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: EdgeInsets.zero,
                children: const [
                  SoftCard(
                    child: ProductEmptyState(
                      icon: Icons.location_on_outlined,
                      title: '附近人暂未开放',
                      subtitle: '入口已调整到这里，后续接入位置权限和附近人接口后会展示附近用户。',
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

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  MobileScannerController? controller;
  bool popped = false;
  bool analyzingImage = false;

  bool get cameraSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    if (cameraSupported) controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _popCode(String code) {
    if (popped || code.trim().isEmpty) return;
    popped = true;
    Navigator.pop(context, code.trim());
  }

  bool get imageAnalyzeSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> pickQrImage() async {
    if (!imageAnalyzeSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台暂不支持识别本地二维码图片')));
      return;
    }
    if (controller == null) controller = MobileScannerController();
    setState(() => analyzingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      final path = result == null || result.files.isEmpty
          ? null
          : result.files.first.path;
      if (path == null || path.isEmpty) return;
      final capture = await controller!.analyzeImage(path);
      final code = capture?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      if (code == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未识别到二维码')));
        return;
      }
      _popCode(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('二维码图片识别失败：$e')));
    } finally {
      if (mounted) setState(() => analyzingImage = false);
    }
  }

  Future<void> manualInput() async {
    final value = await _showBlinTextInput(
      context,
      title: '输入二维码内容',
      label: '二维码内容',
      hint: '粘贴二维码文本',
      icon: Icons.qr_code_2_rounded,
      maxLines: 4,
    );
    if (value != null && value.trim().isNotEmpty) _popCode(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        if (cameraSupported)
          Positioned.fill(
            child: MobileScanner(
              controller: controller!,
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final code = barcodes.first.rawValue;
                if (code != null) _popCode(code);
              },
            ),
          )
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '当前平台请手动输入二维码内容',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: manualInput,
                    child: const Text('手动输入'),
                  ),
                ],
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: analyzingImage ? null : pickQrImage,
                  icon: analyzingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                        ),
                  label: const Text(
                    '相册',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton.icon(
                  onPressed: manualInput,
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                  label: const Text(
                    '手动输入',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (cameraSupported)
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ScannedQrIntent {
  final String raw;
  const _ScannedQrIntent(this.raw);
}

class _SearchUserProfileAction {
  final String action;
  final UserSearchResult user;
  const _SearchUserProfileAction({required this.action, required this.user});
}

class _QrPayload {
  final String raw;
  final String type;
  final int groupId;
  final String groupNo;
  final int userId;
  final Uri? url;

  const _QrPayload({
    required this.raw,
    this.type = '',
    this.groupId = 0,
    this.groupNo = '',
    this.userId = 0,
    this.url,
  });

  bool get isGroup =>
      type == 'im_group' ||
      type == 'group' ||
      type == 'imblinlin_group' ||
      groupId > 0 ||
      groupNo.isNotEmpty;

  bool get isExternalUrl =>
      url != null &&
      (url!.scheme == 'http' || url!.scheme == 'https') &&
      !_isInternalHost(url!) &&
      !isGroup;

  bool get isInternalUnsupported =>
      type.startsWith('im_') && !isGroup && userId <= 0 && !isExternalUrl;

  static _QrPayload parse(String raw) {
    final text = raw.trim();
    final json = _decodeJson(text);
    if (json != null) return _fromMap(text, json);
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final internalQr = _decodeInternalQrUri(uri);
      if (internalQr != null && internalQr.trim().isNotEmpty) {
        return parse(internalQr);
      }
      final parsed = _fromUri(text, uri);
      if (parsed != null) return parsed;
    }
    return _QrPayload(raw: text);
  }

  static _QrPayload _fromMap(String raw, Map<String, dynamic> map) {
    final type = '${map['type'] ?? map['scene'] ?? map['qr_type'] ?? ''}'
        .trim()
        .toLowerCase();
    final appid = int.tryParse('${map['appid'] ?? map['app_id'] ?? 0}') ?? 0;
    final appMismatch = appid > 0 && appid != AppConfig.appId;
    final groupId =
        int.tryParse('${map['group_id'] ?? map['gid'] ?? map['id'] ?? 0}') ?? 0;
    final groupNo = '${map['group_no'] ?? map['groupNo'] ?? map['no'] ?? ''}'
        .trim();
    final userId =
        int.tryParse('${map['user_id'] ?? map['uid'] ?? map['userid'] ?? 0}') ??
        0;
    final embeddedUrl = '${map['url'] ?? map['link'] ?? ''}'.trim();
    final url = embeddedUrl.isEmpty ? null : Uri.tryParse(embeddedUrl);
    return _QrPayload(
      raw: raw,
      type: appMismatch ? 'external_app' : type,
      groupId: appMismatch ? 0 : groupId,
      groupNo: appMismatch ? '' : groupNo,
      userId: appMismatch ? 0 : userId,
      url: url,
    );
  }

  static _QrPayload? _fromUri(String raw, Uri uri) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final internal = _isInternalHost(uri);
      final internalQrType = internal ? _internalQrType(uri) : '';
      final rawType =
          (internalQrType.isNotEmpty ? internalQrType : null) ??
          uri.queryParameters['type'] ??
          uri.queryParameters['scene'] ??
          (internal
              ? uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull
              : null) ??
          '';
      final groupId = internal
          ? int.tryParse(
                  '${uri.queryParameters['group_id'] ?? uri.queryParameters['gid'] ?? _pathIntAfter(uri, {'group', 'im_group'})}',
                ) ??
                0
          : 0;
      final groupNo = internal
          ? '${uri.queryParameters['group_no'] ?? uri.queryParameters['groupNo'] ?? ''}'
                .trim()
          : '';
      final userId = internal
          ? int.tryParse(
                  '${uri.queryParameters['user_id'] ?? uri.queryParameters['uid'] ?? 0}',
                ) ??
                0
          : 0;
      return _QrPayload(
        raw: raw,
        type: internal ? rawType.toLowerCase() : '',
        groupId: groupId,
        groupNo: groupNo,
        userId: userId,
        url: uri,
      );
    }
    if (uri.scheme == 'imblinlin' || uri.scheme == 'blinim') {
      final hostType = uri.host.toLowerCase();
      return _QrPayload(
        raw: raw,
        type: hostType,
        groupId:
            int.tryParse(
              '${uri.queryParameters['group_id'] ?? uri.queryParameters['gid'] ?? 0}',
            ) ??
            0,
        groupNo:
            '${uri.queryParameters['group_no'] ?? uri.queryParameters['groupNo'] ?? ''}'
                .trim(),
        userId:
            int.tryParse(
              '${uri.queryParameters['user_id'] ?? uri.queryParameters['uid'] ?? 0}',
            ) ??
            0,
      );
    }
    return null;
  }

  static int _pathIntAfter(Uri uri, Set<String> keys) {
    final segments = uri.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (keys.contains(segments[i].toLowerCase())) {
        return int.tryParse(segments[i + 1]) ?? 0;
      }
    }
    return 0;
  }

  static String _internalQrType(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path != '/q' && path != '/qr' && path != '/app-scan') return '';
    final scene =
        '${uri.queryParameters['t'] ?? uri.queryParameters['type'] ?? uri.queryParameters['scene'] ?? ''}'
            .trim()
            .toLowerCase();
    if (scene == 'g' || scene == 'group' || scene == 'im_group') {
      return 'im_group';
    }
    if (scene == 'u' || scene == 'user' || scene == 'friend') {
      return 'blin_user_qr';
    }
    return '';
  }

  static String? _decodeInternalQrUri(Uri uri) {
    if (!_isInternalHost(uri)) return null;
    final path = uri.path.toLowerCase();
    if (path != '/q' && path != '/qr' && path != '/app-scan') return null;
    final encoded =
        uri.queryParameters['d'] ??
        uri.queryParameters['data'] ??
        uri.queryParameters['payload'];
    if (encoded == null || encoded.trim().isEmpty) return null;
    var normalized = encoded.trim();
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    try {
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeJson(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static bool _isInternalHost(Uri uri) {
    final apiHost = Uri.tryParse(AppConfig.apiBase)?.host;
    if (apiHost == null || apiHost.isEmpty) return false;
    return uri.host == apiHost;
  }
}

class _ContactActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback onTap;
  const _ContactActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => _ChatTile(
    onTap: onTap,
    avatar: '',
    name: title,
    subtitle: subtitle,
    fallbackIcon: icon,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge > 0) Badge(label: Text(badge > 99 ? '99+' : '$badge')),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
      ],
    ),
  );
}

Future<bool> _showBlinConfirm(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.info_outline_rounded,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
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
            NativeIconBox(icon: icon, color: BlinStyle.primary, size: 58),
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
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: BlinStyle.danger,
                            foregroundColor: Colors.white,
                          )
                        : null,
                    onPressed: () => Navigator.pop(context, true),
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

Future<String?> _showBlinTextInput(
  BuildContext context, {
  required String title,
  required String label,
  String hint = '',
  String initialText = '',
  IconData icon = Icons.edit_note_rounded,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initialText);
  final value = await showDialog<String>(
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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: maxLines,
              textInputAction: maxLines > 1
                  ? TextInputAction.newline
                  : TextInputAction.search,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint.isEmpty ? null : hint,
              ),
              onSubmitted: (_) =>
                  Navigator.pop(context, controller.text.trim()),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  return value;
}

Future<Map<String, dynamic>?> _showCreateGroupDialog({
  required BuildContext context,
  required List<UserSearchResult> friends,
  required String fallbackName,
  required String Function(UserSearchResult user) userSubtitle,
}) async {
  final nameController = TextEditingController();
  final selected = <int>{};
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NativeIconBox(
                icon: Icons.group_add_rounded,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('创建群聊', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '群名称',
                  hintText: fallbackName,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: ListView(
                  children: [
                    for (final friend in friends)
                      CheckboxListTile(
                        value: selected.contains(friend.id),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selected.add(friend.id);
                          } else {
                            selected.remove(friend.id);
                          }
                        }),
                        title: Text(friend.nickname),
                        subtitle: Text(userSubtitle(friend)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'name': nameController.text.trim(),
                        'members': selected.toList(),
                      }),
                      child: const Text('创建'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  nameController.dispose();
  return result;
}

class _MomentsScreen extends StatefulWidget {
  final UserSession session;
  final ApiService api;
  final AppMomentsConfig config;
  const _MomentsScreen({
    required this.session,
    required this.api,
    required this.config,
  });

  @override
  State<_MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<_MomentsScreen> {
  final input = TextEditingController();
  final List<String> selectedImages = [];
  String videoUrl = '';
  String videoThumb = '';
  String visibilityType = 'friends';
  final Set<int> visibleUserIds = {};
  final Set<int> hiddenUserIds = {};
  List<UserSearchResult> momentFriends = [];
  List<MomentItem> items = [];
  List<MomentNotificationItem> notifications = [];
  UserProfileSummary selfProfile = const UserProfileSummary();
  bool loading = true;
  bool loadingNotices = false;
  bool posting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(loadSelfProfile());
    unawaited(load());
    unawaited(loadNotices());
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = items.isEmpty;
        error = null;
      });
    }
    try {
      final next = await widget.api.getMomentsList(
        token: widget.session.token,
        page: 1,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        items = next;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadNotices() async {
    if (loadingNotices) return;
    loadingNotices = true;
    try {
      final next = await widget.api.getMomentNotifications(
        widget.session.token,
      );
      if (!mounted) return;
      setState(() => notifications = next);
    } catch (_) {}
    loadingNotices = false;
  }

  Future<void> refreshAll() async {
    await Future.wait([load(), loadNotices(), loadSelfProfile()]);
  }

  Future<void> loadSelfProfile() async {
    try {
      final next = await widget.api.getUserOtherInformation(
        widget.session.token,
      );
      if (mounted) setState(() => selfProfile = next);
    } catch (_) {}
  }

  String get selfDisplayName => _firstLocalText([
    selfProfile.nickname,
    widget.session.nickname,
    selfProfile.username,
    widget.session.username,
    '我',
  ]);

  String get selfAvatar =>
      _firstLocalText([selfProfile.avatar, widget.session.avatar]);

  String _firstLocalText(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  String _pickUploadedUrl(Map<String, dynamic> data) => _firstLocalText([
    data['url'],
    data['path'],
    data['file_url'],
    data['src'],
    data['image'],
    data['image_path'],
    data['file_path'],
    data['oss_path'],
  ]);

  Future<void> pickImages() async {
    final remaining = (9 - selectedImages.length).clamp(0, 9).toInt();
    if (remaining <= 0) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final urls = <String>[];
    for (final file in result.files.take(remaining)) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final uploaded = await widget.api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: file.name,
      );
      final url = _pickUploadedUrl(uploaded);
      if (url.isNotEmpty) urls.add(url);
    }
    if (!mounted || urls.isEmpty) return;
    setState(() {
      final nextRemaining = (9 - selectedImages.length).clamp(0, 9).toInt();
      if (nextRemaining > 0) {
        selectedImages.addAll(urls.take(nextRemaining));
      }
    });
  }

  Future<void> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final uploaded = await widget.api.uploadChatFile(
      token: widget.session.token,
      bytes: bytes,
      filename: file.name,
    );
    final url = _pickUploadedUrl(uploaded);
    if (url.isEmpty || !mounted) return;
    setState(() => videoUrl = url);
    final thumb = file.extension?.toLowerCase().contains('mp4') == true
        ? ''
        : '';
    setState(() => videoThumb = thumb);
  }

  String get visibilityLabel {
    if (!widget.config.allVisible) return '仅好友可见';
    switch (visibilityType) {
      case 'public':
        return '全员可看';
      case 'include':
        return visibleUserIds.isEmpty ? '部分可见' : '${visibleUserIds.length}人可见';
      case 'exclude':
        return hiddenUserIds.isEmpty ? '不给谁看' : '${hiddenUserIds.length}人不可见';
      case 'private':
        return '仅自己可见';
      case 'friends':
      default:
        return '仅好友可见';
    }
  }

  IconData get visibilityIcon {
    if (!widget.config.allVisible) return Icons.people_outline_rounded;
    switch (visibilityType) {
      case 'public':
        return Icons.public_rounded;
      case 'include':
        return Icons.group_add_outlined;
      case 'exclude':
        return Icons.visibility_off_outlined;
      case 'private':
        return Icons.lock_outline_rounded;
      case 'friends':
      default:
        return Icons.people_outline_rounded;
    }
  }

  Future<void> chooseVisibility() async {
    if (momentFriends.isEmpty) {
      try {
        momentFriends = await widget.api.getFriends(widget.session.token);
      } catch (_) {}
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<_MomentVisibilitySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MomentVisibilitySheet(
        friends: momentFriends,
        initialType: visibilityType,
        initialVisibleIds: visibleUserIds,
        initialHiddenIds: hiddenUserIds,
        allowPublic: widget.config.allVisible,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      visibilityType = result.type;
      visibleUserIds
        ..clear()
        ..addAll(result.visibleIds);
      hiddenUserIds
        ..clear()
        ..addAll(result.hiddenIds);
    });
  }

  Future<void> post() async {
    final text = input.text.trim();
    if (text.isEmpty && selectedImages.isEmpty && videoUrl.isEmpty) return;
    final submitVisibilityType = widget.config.allVisible
        ? visibilityType
        : 'friends';
    setState(() => posting = true);
    try {
      await widget.api.createMoment(
        token: widget.session.token,
        content: text,
        images: selectedImages,
        videoUrl: videoUrl,
        videoThumb: videoThumb,
        visibilityType: submitVisibilityType,
        visibleUserIds: visibleUserIds.toList(),
        hiddenUserIds: hiddenUserIds.toList(),
      );
      input.clear();
      selectedImages.clear();
      videoUrl = '';
      videoThumb = '';
      visibilityType = 'friends';
      visibleUserIds.clear();
      hiddenUserIds.clear();
      await refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败：$e')));
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  String timeText(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}-${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  MomentItem? _replaceMoment(MomentItem moment) {
    final idx = items.indexWhere((e) => e.id == moment.id);
    if (idx < 0) return null;
    setState(() => items[idx] = moment);
    return moment;
  }

  Future<void> _toggleLike(MomentItem item) async {
    try {
      final result = await widget.api.toggleMomentLike(
        token: widget.session.token,
        momentId: item.id,
      );
      final currentUser = MomentLikeUser(
        userId: widget.session.id,
        nickname: selfDisplayName,
        avatar: selfAvatar,
      );
      final likeUsers = [...item.likeUsers]
        ..removeWhere((user) => user.userId == widget.session.id);
      if (result.liked) likeUsers.insert(0, currentUser);
      final next = item.copyWith(
        likedByMe: result.liked,
        likeCount: result.likeCount,
        likeUsers: likeUsers.take(12).toList(),
      );
      _replaceMoment(next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('点赞失败：$e')));
    }
  }

  Future<void> _openMomentDetail(MomentItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MomentDetailScreen(
          session: widget.session,
          displayName: selfDisplayName,
          avatar: selfAvatar,
          api: widget.api,
          initialMoment: item,
          onMomentChanged: (next) {
            final idx = items.indexWhere((e) => e.id == next.id);
            if (idx >= 0 && mounted) setState(() => items[idx] = next);
          },
          onDelete: () async {
            await widget.api.deleteMoment(
              token: widget.session.token,
              momentId: item.id,
            );
            if (!mounted) return;
            setState(() => items.removeWhere((e) => e.id == item.id));
          },
          onRefreshNotices: loadNotices,
        ),
      ),
    );
    await refreshAll();
  }

  Future<void> _deleteOwnMoment(MomentItem item) async {
    if (item.userId != widget.session.id) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除朋友圈'),
        content: const Text('删除后这条朋友圈将不再展示，确认删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteMoment(
        token: widget.session.token,
        momentId: item.id,
      );
      if (!mounted) return;
      setState(() => items.removeWhere((e) => e.id == item.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('朋友圈已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _openNotifications() async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _MomentNotificationScreen(
          session: widget.session,
          api: widget.api,
          items: notifications,
        ),
      ),
    );
    if (action == 'clear') {
      await widget.api.clearMomentNotifications(widget.session.token);
      if (mounted) setState(() => notifications = []);
      await refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = notifications.where((e) => !e.isRead).length;
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '朋友圈',
              subtitle: widget.config.visibilityLabel,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              actions: [
                ShellAction(
                  icon: Icons.notifications_none_rounded,
                  onTap: _openNotifications,
                  tooltip: '朋友圈消息',
                  selected: unreadCount > 0,
                ),
              ],
            ),
            Expanded(
              child: BlinRefresh(
                onRefresh: refreshAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlinStyle.pagePadding,
                    0,
                    BlinStyle.pagePadding,
                    BlinStyle.pagePadding,
                  ),
                  children: [
                    _MomentComposerCard(
                      session: widget.session,
                      displayName: selfDisplayName,
                      avatar: selfAvatar,
                      input: input,
                      selectedImages: selectedImages,
                      videoUrl: videoUrl,
                      videoThumb: videoThumb,
                      visibilityIcon: visibilityIcon,
                      visibilityLabel: visibilityLabel,
                      posting: posting,
                      onPickImages: selectedImages.length >= 9
                          ? null
                          : pickImages,
                      onPickVideo: videoUrl.isNotEmpty ? null : pickVideo,
                      onChooseVisibility: chooseVisibility,
                      onPost: posting ? null : post,
                      onRemoveImage: (url) =>
                          setState(() => selectedImages.remove(url)),
                      onRemoveVideo: () => setState(() {
                        videoUrl = '';
                        videoThumb = '';
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (error != null)
                      SoftCard(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (loading)
                      const _ChatSkeletonList()
                    else if (items.isEmpty)
                      const SoftCard(
                        child: ProductEmptyState(
                          icon: Icons.auto_graph_outlined,
                          title: '暂无朋友圈',
                          subtitle: '好友发布的动态会显示在这里',
                        ),
                      )
                    else
                      for (final item in items)
                        _MomentTile(
                          item: item,
                          timeText: timeText(item.createTime),
                          onTap: () => _openMomentDetail(item),
                          onLike: () => _toggleLike(item),
                          onDelete: item.userId == widget.session.id
                              ? () => _deleteOwnMoment(item)
                              : null,
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

class _MomentComposerCard extends StatelessWidget {
  final UserSession session;
  final String displayName;
  final String avatar;
  final TextEditingController input;
  final List<String> selectedImages;
  final String videoUrl;
  final String videoThumb;
  final IconData visibilityIcon;
  final String visibilityLabel;
  final bool posting;
  final VoidCallback? onPickImages;
  final VoidCallback? onPickVideo;
  final VoidCallback onChooseVisibility;
  final VoidCallback? onPost;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onRemoveVideo;

  const _MomentComposerCard({
    required this.session,
    required this.displayName,
    required this.avatar,
    required this.input,
    required this.selectedImages,
    required this.videoUrl,
    required this.videoThumb,
    required this.visibilityIcon,
    required this.visibilityLabel,
    required this.posting,
    required this.onPickImages,
    required this.onPickVideo,
    required this.onChooseVisibility,
    required this.onPost,
    required this.onRemoveImage,
    required this.onRemoveVideo,
  });

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    radius: 18,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(imageUrl: avatar, name: displayName, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '分享这一刻...',
                  filled: true,
                  fillColor: BlinStyle.iconSurface(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (selectedImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MomentImageGrid(
            images: selectedImages,
            onRemove: onRemoveImage,
            compact: true,
          ),
        ],
        if (videoUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MomentVideoCard(
            url: videoUrl,
            thumbUrl: videoThumb,
            onRemove: onRemoveVideo,
            compact: true,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            _MomentIconButton(
              icon: Icons.image_outlined,
              tooltip: '图片',
              onTap: onPickImages,
              selected: selectedImages.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _MomentIconButton(
              icon: Icons.videocam_outlined,
              tooltip: '视频',
              onTap: onPickVideo,
              selected: videoUrl.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _MomentScopeButton(
              icon: visibilityIcon,
              label: visibilityLabel,
              onTap: onChooseVisibility,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onPost,
              icon: posting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(posting ? '发布中' : '发布'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(74, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MomentIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  const _MomentIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? BlinStyle.primary : BlinStyle.textSecondary(context);
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: selected
                ? BlinStyle.primary.withValues(alpha: .10)
                : BlinStyle.iconSurface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BlinStyle.hairline(context, .55).color),
          ),
          child: Icon(icon, color: fg, size: 19),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: child);
  }
}

class _MomentScopeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MomentScopeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: BlinStyle.primary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BlinStyle.primary.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: BlinStyle.primary, size: 16),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MomentTile extends StatelessWidget {
  final MomentItem item;
  final String timeText;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback? onDelete;
  const _MomentTile({
    required this.item,
    required this.timeText,
    required this.onTap,
    required this.onLike,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(imageUrl: item.avatar, name: item.nickname, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            timeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: BlinStyle.textSecondary(
                              context,
                            ).withValues(alpha: .55),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.visibilityLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: BlinStyle.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ShellAction(
                icon: item.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                onTap: onLike,
                tooltip: item.likedByMe ? '取消赞' : '点赞',
                selected: item.likedByMe,
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: BlinStyle.subtle,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除朋友圈')),
                  ],
                ),
            ],
          ),
          if (item.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.content,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 14,
                height: 1.38,
              ),
            ),
          ],
          if (item.videoUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MomentVideoCard(
              url: item.videoUrl,
              thumbUrl: item.videoThumb,
              compact: true,
            ),
          ],
          if (item.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MomentImageGrid(images: item.images, compact: true),
          ],
          if (item.likeCount > 0 || item.commentCount > 0) ...[
            const SizedBox(height: 8),
            _MomentStatsBar(
              likeCount: item.likeCount,
              commentCount: item.commentCount,
              likedByMe: item.likedByMe,
              onLike: onLike,
              onComment: onTap,
            ),
          ],
          if (item.comments.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final comment in item.comments.take(3))
              _MomentCommentPreview(comment: comment),
          ],
        ],
      ),
    ),
  );
}

class _MomentStatsBar extends StatelessWidget {
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _MomentStatsBar({
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: BlinStyle.iconSurface(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: onLike,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Row(
              children: [
                Icon(
                  likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: likedByMe ? BlinStyle.danger : BlinStyle.muted,
                  size: 17,
                ),
                const SizedBox(width: 4),
                Text(
                  likeCount > 0 ? '$likeCount' : '赞',
                  style: TextStyle(
                    color: likedByMe ? BlinStyle.danger : BlinStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: onComment,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.mode_comment_outlined,
                  color: BlinStyle.muted,
                  size: 17,
                ),
                const SizedBox(width: 4),
                Text(
                  commentCount > 0 ? '$commentCount' : '评论',
                  style: const TextStyle(
                    color: BlinStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MomentVisibilitySelection {
  final String type;
  final Set<int> visibleIds;
  final Set<int> hiddenIds;

  const _MomentVisibilitySelection({
    required this.type,
    required this.visibleIds,
    required this.hiddenIds,
  });
}

class _MomentVisibilitySheet extends StatefulWidget {
  final List<UserSearchResult> friends;
  final String initialType;
  final Set<int> initialVisibleIds;
  final Set<int> initialHiddenIds;
  final bool allowPublic;

  const _MomentVisibilitySheet({
    required this.friends,
    required this.initialType,
    required this.initialVisibleIds,
    required this.initialHiddenIds,
    required this.allowPublic,
  });

  @override
  State<_MomentVisibilitySheet> createState() => _MomentVisibilitySheetState();
}

class _MomentVisibilitySheetState extends State<_MomentVisibilitySheet> {
  late String type = widget.allowPublic ? widget.initialType : 'friends';
  late final Set<int> visibleIds = {...widget.initialVisibleIds};
  late final Set<int> hiddenIds = {...widget.initialHiddenIds};

  bool get needsPicker => type == 'include' || type == 'exclude';

  String optionSubtitle(String value) {
    switch (value) {
      case 'public':
        return '所有使用该应用的人都可以看到';
      case 'include':
        return visibleIds.isEmpty ? '请选择可见好友' : '${visibleIds.length} 位好友可见';
      case 'exclude':
        return hiddenIds.isEmpty ? '请选择不可见好友' : '${hiddenIds.length} 位好友不可见';
      case 'private':
        return '只保存在自己的朋友圈';
      case 'friends':
      default:
        return '互为好友的人可以看到';
    }
  }

  void selectType(String next) {
    setState(() {
      type = next;
      if (type != 'include') visibleIds.clear();
      if (type != 'exclude') hiddenIds.clear();
    });
  }

  void toggleFriend(int id) {
    setState(() {
      final set = type == 'include' ? visibleIds : hiddenIds;
      if (!set.add(id)) set.remove(id);
    });
  }

  void submit() {
    Navigator.pop(
      context,
      _MomentVisibilitySelection(
        type: type,
        visibleIds: {...visibleIds},
        hiddenIds: {...hiddenIds},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .86,
        ),
        decoration: BoxDecoration(
          color: BlinStyle.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 8),
                child: Row(
                  children: [
                    const NativeIconBox(
                      icon: Icons.visibility_outlined,
                      color: BlinStyle.primary,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '谁可以看',
                        style: TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(onPressed: submit, child: const Text('完成')),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    _MomentVisibilityOption(
                      icon: Icons.people_outline_rounded,
                      title: '仅好友可见',
                      subtitle: optionSubtitle('friends'),
                      selected: type == 'friends',
                      onTap: () => selectType('friends'),
                    ),
                    if (widget.allowPublic) ...[
                      _MomentVisibilityOption(
                        icon: Icons.public_rounded,
                        title: '全员可看',
                        subtitle: optionSubtitle('public'),
                        selected: type == 'public',
                        onTap: () => selectType('public'),
                      ),
                      _MomentVisibilityOption(
                        icon: Icons.visibility_off_outlined,
                        title: '不给谁看',
                        subtitle: optionSubtitle('exclude'),
                        selected: type == 'exclude',
                        onTap: () => selectType('exclude'),
                      ),
                      _MomentVisibilityOption(
                        icon: Icons.group_add_outlined,
                        title: '谁可以看',
                        subtitle: optionSubtitle('include'),
                        selected: type == 'include',
                        onTap: () => selectType('include'),
                      ),
                      _MomentVisibilityOption(
                        icon: Icons.lock_outline_rounded,
                        title: '仅自己可见',
                        subtitle: optionSubtitle('private'),
                        selected: type == 'private',
                        onTap: () => selectType('private'),
                      ),
                    ],
                    if (needsPicker) ...[
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Text(
                          '选择好友',
                          style: TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.friends.isEmpty)
                        const NativeListRow(
                          leading: NativeIconBox(
                            icon: Icons.person_search_outlined,
                            color: BlinStyle.subtle,
                            size: 40,
                          ),
                          title: '暂无好友',
                          subtitle: '添加好友后可以单独设置可见范围',
                        )
                      else
                        for (final friend in widget.friends)
                          CheckboxListTile(
                            value: (type == 'include' ? visibleIds : hiddenIds)
                                .contains(friend.id),
                            onChanged: (_) => toggleFriend(friend.id),
                            secondary: AppAvatar(
                              imageUrl: friend.avatar,
                              name: friend.nickname,
                              size: 34,
                            ),
                            title: Text(
                              friend.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: friend.username.trim().isEmpty
                                ? null
                                : Text(friend.username),
                            controlAffinity: ListTileControlAffinity.trailing,
                          ),
                    ],
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

class _MomentVisibilityOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MomentVisibilityOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: NativeListRow(
      leading: NativeIconBox(
        icon: icon,
        color: selected ? BlinStyle.primary : BlinStyle.subtle,
        size: 40,
      ),
      title: title,
      subtitle: subtitle,
      minHeight: 68,
      selected: selected,
      onTap: onTap,
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? BlinStyle.primary : BlinStyle.subtle,
      ),
    ),
  );
}

class _MomentCommentPreview extends StatelessWidget {
  final MomentCommentItem comment;
  const _MomentCommentPreview({required this.comment});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: comment.nickname,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (comment.replyNickname.isNotEmpty) ...[
              const TextSpan(text: ' 回复 '),
              TextSpan(
                text: comment.replyNickname,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            TextSpan(
              text: '：${comment.content}',
              style: const TextStyle(color: BlinStyle.ink),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MomentImageGrid extends StatelessWidget {
  final List<String> images;
  final ValueChanged<String>? onRemove;
  final bool compact;
  const _MomentImageGrid({
    required this.images,
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleImages = images
        .map(media_url.resolveMediaUrl)
        .where((url) => url.isNotEmpty)
        .take(9)
        .toList();
    final count = visibleImages.length.clamp(1, 9);
    final columns = count == 1 ? 1 : (count <= 4 ? 2 : 3);
    final screen = MediaQuery.sizeOf(context).width;
    final maxWidth = compact
        ? max(120.0, min(screen - 96, 252.0))
        : double.infinity;
    final tileSize = compact
        ? (count == 1 ? 152.0 : (maxWidth - (columns - 1) * 5) / columns)
        : null;
    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: compact ? 5 : 6,
        crossAxisSpacing: compact ? 5 : 6,
        mainAxisExtent: tileSize,
      ),
      itemCount: visibleImages.length,
      itemBuilder: (_, index) {
        final url = visibleImages[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
              child: GestureDetector(
                onTap: () =>
                    _showMomentImagePreview(context, visibleImages, index),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (_, __, ___) => Container(
                    color: BlinStyle.softFill,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  onTap: () => onRemove!(url),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (!compact) return grid;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: maxWidth, child: grid),
    );
  }
}

class _MomentVideoCard extends StatelessWidget {
  final String url;
  final String thumbUrl;
  final VoidCallback? onRemove;
  final bool compact;
  const _MomentVideoCard({
    required this.url,
    this.thumbUrl = '',
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Stack(
      children: [
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: .72),
            builder: (_) => _MomentVideoDialog(url: url),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
              child: Container(
                color: BlinStyle.softFill,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (media_url.resolveMediaUrl(thumbUrl).isNotEmpty)
                      Image.network(
                        media_url.resolveMediaUrl(thumbUrl),
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    const Center(
                      child: Icon(Icons.play_circle_outline_rounded, size: 38),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(3),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
      ],
    );
    if (!compact) return card;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 252),
        child: card,
      ),
    );
  }
}

void _showMomentImagePreview(
  BuildContext context,
  List<String> images,
  int initialIndex,
) {
  final visibleImages = images
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (visibleImages.isEmpty) return;
  final safeInitialIndex = initialIndex
      .clamp(0, visibleImages.length - 1)
      .toInt();
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .92),
    builder: (_) => _MomentImagePreviewDialog(
      images: visibleImages,
      initialIndex: safeInitialIndex,
    ),
  );
}

class _MomentImagePreviewDialog extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _MomentImagePreviewDialog({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_MomentImagePreviewDialog> createState() =>
      _MomentImagePreviewDialogState();
}

class _MomentImagePreviewDialogState extends State<_MomentImagePreviewDialog> {
  late final PageController controller;
  late int index;

  @override
  void initState() {
    super.initState();
    index = widget.images.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
    controller = PageController(initialPage: index);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: widget.images.isEmpty
        ? Center(
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          )
        : Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: widget.images.length,
                onPageChanged: (value) => setState(() => index = value),
                itemBuilder: (_, page) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      media_url.resolveMediaUrl(widget.images[page]),
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: MediaQuery.paddingOf(context).top + 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1}/${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

class _MomentVideoDialog extends StatefulWidget {
  final String url;
  const _MomentVideoDialog({required this.url});

  @override
  State<_MomentVideoDialog> createState() => _MomentVideoDialogState();
}

class _MomentVideoDialogState extends State<_MomentVideoDialog> {
  late final VideoPlayerController controller;
  bool ready = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => ready = true);
          controller.play();
        })
        .catchError((e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.black,
    insetPadding: const EdgeInsets.all(18),
    child: AspectRatio(
      aspectRatio: ready && controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (ready)
            VideoPlayer(controller)
          else if (error != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '视频加载失败：$error',
                style: const TextStyle(color: Colors.white),
              ),
            )
          else
            const CircularProgressIndicator(),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MomentDetailScreen extends StatefulWidget {
  final UserSession session;
  final String displayName;
  final String avatar;
  final ApiService api;
  final MomentItem initialMoment;
  final ValueChanged<MomentItem> onMomentChanged;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRefreshNotices;
  const _MomentDetailScreen({
    required this.session,
    required this.displayName,
    required this.avatar,
    required this.api,
    required this.initialMoment,
    required this.onMomentChanged,
    required this.onDelete,
    required this.onRefreshNotices,
  });

  @override
  State<_MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<_MomentDetailScreen> {
  late MomentItem moment = widget.initialMoment;
  final commentController = TextEditingController();
  MomentCommentItem? replyTarget;
  bool submitting = false;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> like() async {
    final result = await widget.api.toggleMomentLike(
      token: widget.session.token,
      momentId: moment.id,
    );
    final currentUser = MomentLikeUser(
      userId: widget.session.id,
      nickname: widget.displayName,
      avatar: widget.avatar,
    );
    final likeUsers = [...moment.likeUsers]
      ..removeWhere((user) => user.userId == widget.session.id);
    if (result.liked) likeUsers.insert(0, currentUser);
    setState(
      () => moment = moment.copyWith(
        likedByMe: result.liked,
        likeCount: result.likeCount,
        likeUsers: likeUsers.take(12).toList(),
      ),
    );
    widget.onMomentChanged(moment);
  }

  Future<void> comment() async {
    final text = commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => submitting = true);
    try {
      final result = await widget.api.commentMoment(
        token: widget.session.token,
        momentId: moment.id,
        content: text,
        parentId: replyTarget?.id ?? 0,
      );
      commentController.clear();
      final nextComments = [...moment.comments, result.comment];
      setState(
        () => moment = moment.copyWith(
          commentCount: result.commentCount,
          comments: nextComments,
        ),
      );
      setState(() => replyTarget = null);
      widget.onMomentChanged(moment);
      await widget.onRefreshNotices();
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> deleteComment(MomentCommentItem comment) async {
    final nextCount = await widget.api.deleteMomentComment(
      token: widget.session.token,
      commentId: comment.id,
    );
    setState(
      () => moment = moment.copyWith(
        commentCount: nextCount,
        comments: moment.comments.where((e) => e.id != comment.id).toList(),
      ),
    );
    widget.onMomentChanged(moment);
  }

  Future<void> deleteMoment() async {
    await widget.onDelete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '朋友圈详情',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              IconButton(
                onPressed: like,
                icon: Icon(
                  moment.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              if (moment.userId == widget.session.id)
                IconButton(
                  onPressed: deleteMoment,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                BlinStyle.pagePadding,
                0,
                BlinStyle.pagePadding,
                BlinStyle.pagePadding,
              ),
              children: [
                _MomentTile(
                  item: moment,
                  timeText: _timeText(moment.createTime),
                  onTap: () {},
                  onLike: like,
                ),
                const SizedBox(height: 12),
                SoftCard(
                  padding: const EdgeInsets.all(BlinStyle.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeader(
                        title: replyTarget == null ? '写评论' : '回复评论',
                        subtitle: replyTarget == null
                            ? '输入后发送到这条动态'
                            : '正在回复 ${replyTarget!.nickname}',
                      ),
                      TextField(
                        controller: commentController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: replyTarget == null
                              ? '写评论...'
                              : '回复 ${replyTarget!.nickname}',
                          prefixIcon: replyTarget == null
                              ? null
                              : IconButton(
                                  onPressed: () => setState(() {
                                    replyTarget = null;
                                    commentController.clear();
                                  }),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          suffixIcon: IconButton(
                            onPressed: submitting ? null : () => comment(),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (moment.comments.isEmpty)
                  const SoftCard(
                    child: ProductEmptyState(
                      icon: Icons.mode_comment_outlined,
                      title: '暂无评论',
                      subtitle: '第一条评论会显示在这里',
                    ),
                  )
                else
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: AppSectionHeader(
                            title: '全部评论',
                            subtitle: '${moment.comments.length} 条互动',
                          ),
                        ),
                        for (final c in moment.comments)
                          _MomentCommentRow(
                            comment: c,
                            timeText: _timeText(c.createTime),
                            canDelete:
                                c.userId == widget.session.id ||
                                moment.userId == widget.session.id,
                            onReply: () {
                              setState(() {
                                replyTarget = c;
                                commentController.clear();
                              });
                            },
                            onDelete: () => deleteComment(c),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _timeText(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${time.month}-${time.day}';
  }
}

class _MomentCommentRow extends StatelessWidget {
  final MomentCommentItem comment;
  final String timeText;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  const _MomentCommentRow({
    required this.comment,
    required this.timeText,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: AppAvatar(
      imageUrl: comment.avatar,
      name: comment.nickname,
      size: 40,
    ),
    title: comment.replyNickname.isNotEmpty
        ? '${comment.nickname} 回复 ${comment.replyNickname}'
        : comment.nickname,
    subtitle: comment.content,
    meta: timeText,
    minHeight: 78,
    trailing: PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, color: BlinStyle.subtle),
      onSelected: (value) {
        if (value == 'reply') onReply();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'reply', child: Text('回复')),
        if (canDelete) const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  );
}

class _MomentNotificationScreen extends StatelessWidget {
  final UserSession session;
  final ApiService api;
  final List<MomentNotificationItem> items;
  const _MomentNotificationScreen({
    required this.session,
    required this.api,
    required this.items,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '朋友圈消息',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                child: const Text('全部已读'),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                BlinStyle.pagePadding,
                0,
                BlinStyle.pagePadding,
                BlinStyle.pagePadding,
              ),
              children: [
                if (items.isEmpty)
                  const SoftCard(
                    child: ProductEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: '暂无互动消息',
                      subtitle: '点赞、评论、回复会显示在这里',
                    ),
                  )
                else
                  for (final item in items) _MomentNoticeCard(item: item),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MomentNoticeCard extends StatelessWidget {
  final MomentNotificationItem item;
  const _MomentNoticeCard({required this.item});

  @override
  Widget build(BuildContext context) => SoftCard(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NativeListRow(
          leading: AppAvatar(
            imageUrl: item.actorAvatar,
            name: item.actorNickname,
            size: 44,
          ),
          title: item.actorNickname,
          subtitle: [
            item.actionLabel,
            if (item.content.trim().isNotEmpty) item.content,
          ].join(' '),
          meta:
              '${item.createTime.month}-${item.createTime.day} ${item.createTime.hour.toString().padLeft(2, '0')}:${item.createTime.minute.toString().padLeft(2, '0')}',
          minHeight: 74,
          trailing: item.isRead
              ? null
              : const NativeIconBox(
                  icon: Icons.fiber_manual_record_rounded,
                  color: BlinStyle.primary,
                  size: 28,
                ),
        ),
        if (item.momentContent.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BlinStyle.iconSurface(context),
                borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
              ),
              child: Text(
                item.momentContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ContactEmptyTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _ContactEmptyTile({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: NativeIconBox(icon: icon, color: BlinStyle.subtle, size: 40),
    title: text,
    onTap: onTap,
    minHeight: 60,
    trailing: const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
  );
}

class _FriendsScreen extends StatelessWidget {
  final List<UserSearchResult> friends;
  final bool showUserId;
  final ValueChanged<UserSearchResult> onOpen;
  const _FriendsScreen({
    required this.friends,
    required this.showUserId,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '我的好友',
            subtitle: '从好友列表进入私聊',
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
                  if (friends.isEmpty)
                    const SoftCard(
                      child: Text(
                        '暂无好友，可以通过“添加好友”搜索账号添加。',
                        style: TextStyle(
                          color: BlinStyle.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    ...friends.map(
                      (u) => _ChatTile(
                        onTap: () {
                          Navigator.pop(context);
                          onOpen(u);
                        },
                        avatar: u.avatar,
                        name: u.nickname,
                        subtitle: showUserId
                            ? 'ID: ${u.id}  @${u.username}'
                            : '@${u.username}',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.muted,
                        ),
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

enum _ConversationKind { peer, group, system }

class _UnifiedConversation {
  final _ConversationKind kind;
  final ConversationItem? peer;
  final ImGroup? group;
  final List<Map<String, dynamic>> notifications;
  final String key;
  final String title;
  final String avatar;
  final String preview;
  final String timeText;
  final int unread;
  final int order;
  final bool pinned;

  const _UnifiedConversation({
    required this.kind,
    required this.peer,
    required this.group,
    this.notifications = const [],
    required this.key,
    required this.title,
    required this.avatar,
    required this.preview,
    required this.timeText,
    required this.unread,
    required this.order,
    required this.pinned,
  });

  factory _UnifiedConversation.peer(
    ConversationItem item, {
    required int order,
  }) => _UnifiedConversation(
    kind: _ConversationKind.peer,
    peer: item,
    group: null,
    notifications: const [],
    key: 'peer:${item.userId}',
    title: item.nickname,
    avatar: item.avatar,
    preview: item.preview,
    timeText: item.msgTime,
    unread: item.unread,
    order: order,
    pinned: false,
  );

  factory _UnifiedConversation.group(
    ImGroup group, {
    required int order,
    required int unread,
    required String preview,
    required String timeText,
    String? title,
  }) => _UnifiedConversation(
    kind: _ConversationKind.group,
    peer: null,
    group: group,
    notifications: const [],
    key: 'group:${group.id}',
    title: title?.trim().isNotEmpty == true ? title!.trim() : group.name,
    avatar: group.avatar,
    preview: preview,
    timeText: timeText,
    unread: unread,
    order: order,
    pinned: false,
  );

  factory _UnifiedConversation.system(
    List<Map<String, dynamic>> notifications, {
    required int unread,
    required int order,
  }) {
    final latest = notifications.isEmpty
        ? const <String, dynamic>{}
        : notifications.first;
    final title = _firstNonEmpty(latest, const [
      'title',
      'type_name',
      'notification_type',
    ]);
    final content = _firstNonEmpty(latest, const [
      'content',
      'message',
      'msg',
      'text',
    ]);
    final time = _firstNonEmpty(latest, const [
      'create_time',
      'time',
      'created_at',
      'time_ago',
    ]);
    return _UnifiedConversation(
      kind: _ConversationKind.system,
      peer: null,
      group: null,
      notifications: notifications,
      key: 'system:notifications',
      title: '消息通知',
      avatar: '',
      preview: content.isNotEmpty
          ? content
          : (title.isNotEmpty ? title : '系统提醒'),
      timeText: time,
      unread: unread,
      order: order,
      pinned: false,
    );
  }

  bool get isGroup => kind == _ConversationKind.group;

  bool get isSystem => kind == _ConversationKind.system;

  int get peerId => peer?.userId ?? 0;

  DateTime? get sortTime => _parseConversationTime(timeText);

  _UnifiedConversation copyWith({
    ImGroup? group,
    String? title,
    String? avatar,
    String? preview,
    String? timeText,
    int? unread,
    bool? pinned,
  }) => _UnifiedConversation(
    kind: kind,
    peer: peer,
    group: group ?? this.group,
    notifications: notifications,
    key: key,
    title: title ?? this.title,
    avatar: avatar ?? this.avatar,
    preview: preview ?? this.preview,
    timeText: timeText ?? this.timeText,
    unread: unread ?? this.unread,
    order: order,
    pinned: pinned ?? this.pinned,
  );
}

class _UnifiedConversationTile extends StatelessWidget {
  final _UnifiedConversation conversation;
  final int resetSwipeToken;
  final ImOnlineStatus? online;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  const _UnifiedConversationTile({
    required this.conversation,
    required this.resetSwipeToken,
    required this.online,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tile = _ChatTile(
      onTap: onTap,
      avatar: conversation.avatar,
      name: conversation.title,
      subtitle: conversation.isSystem
          ? conversation.preview
          : (conversation.isGroup
                ? conversation.preview
                : conversation.preview),
      online: conversation.isGroup ? null : online,
      pinned: conversation.pinned,
      fallbackIcon: conversation.isSystem
          ? Icons.notifications_none_rounded
          : (conversation.isGroup ? Icons.groups_rounded : null),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conversation.isGroup)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(
                    Icons.groups_rounded,
                    color: BlinStyle.primary,
                    size: 16,
                  ),
                ),
              Text(
                _formatConversationTime(conversation.timeText),
                style: const TextStyle(
                  color: BlinStyle.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (conversation.unread > 0)
            Badge(
              label: Text(
                conversation.unread > 99 ? '99+' : '${conversation.unread}',
              ),
            ),
        ],
      ),
    );
    if (conversation.isSystem) return tile;
    return _ConversationSwipeActions(
      conversationKey: conversation.key,
      pinned: conversation.pinned,
      resetToken: resetSwipeToken,
      onTogglePin: onTogglePin,
      onDelete: onDelete,
      child: tile,
    );
  }
}

class _ConversationSwipeActions extends StatefulWidget {
  final String conversationKey;
  final bool pinned;
  final int resetToken;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final Widget child;

  const _ConversationSwipeActions({
    required this.conversationKey,
    required this.pinned,
    required this.resetToken,
    required this.onTogglePin,
    required this.onDelete,
    required this.child,
  });

  @override
  State<_ConversationSwipeActions> createState() =>
      _ConversationSwipeActionsState();
}

class _ConversationSwipeActionsState extends State<_ConversationSwipeActions> {
  static const double _actionWidth = 152;
  double _offset = 0;

  @override
  void didUpdateWidget(covariant _ConversationSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken ||
        oldWidget.conversationKey != widget.conversationKey) {
      _close();
    }
  }

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final next = (_offset - details.delta.dx).clamp(0.0, _actionWidth);
    if (next != _offset) setState(() => _offset = next);
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = velocity < -280 || (_offset > _actionWidth * .42);
    setState(() => _offset = shouldOpen ? _actionWidth : 0);
  }

  void _runAction(VoidCallback action) {
    _close();
    action();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: [
        if (_offset > 0)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ConversationSwipeButton(
                      icon: widget.pinned
                          ? Icons.vertical_align_center_rounded
                          : Icons.vertical_align_top_rounded,
                      label: widget.pinned ? '取消置顶' : '置顶',
                      color: BlinStyle.primary,
                      onTap: () => _runAction(widget.onTogglePin),
                    ),
                    const SizedBox(width: 8),
                    _ConversationSwipeButton(
                      icon: Icons.delete_outline_rounded,
                      label: '删除',
                      color: BlinStyle.danger,
                      onTap: () => _runAction(widget.onDelete),
                    ),
                  ],
                ),
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(-_offset, 0, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            child: widget.child,
          ),
        ),
      ],
    ),
  );
}

class _ConversationSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ConversationSwipeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        height: 58,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

DateTime? _parseConversationTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final now = DateTime.now();
  if (value == '刚刚') return now;
  final minutesAgo = RegExp(r'^(\d+)\s*分钟(?:前)?$').firstMatch(value);
  if (minutesAgo != null) {
    return now.subtract(
      Duration(minutes: int.tryParse(minutesAgo.group(1) ?? '') ?? 0),
    );
  }
  final hoursAgo = RegExp(r'^(\d+)\s*小时(?:前)?$').firstMatch(value);
  if (hoursAgo != null) {
    return now.subtract(
      Duration(hours: int.tryParse(hoursAgo.group(1) ?? '') ?? 0),
    );
  }
  final daysAgo = RegExp(r'^(\d+)\s*天(?:前)?$').firstMatch(value);
  if (daysAgo != null) {
    return now.subtract(
      Duration(days: int.tryParse(daysAgo.group(1) ?? '') ?? 0),
    );
  }
  final yesterdayTime = RegExp(r'^昨天\s*(\d{1,2}):(\d{1,2})$').firstMatch(value);
  if (yesterdayTime != null) {
    final yesterday = now.subtract(const Duration(days: 1));
    return DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
      int.tryParse(yesterdayTime.group(1) ?? '') ?? 0,
      int.tryParse(yesterdayTime.group(2) ?? '') ?? 0,
    );
  }
  final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed;
  final monthDayTime = RegExp(
    r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?$',
  ).firstMatch(value);
  if (monthDayTime != null) {
    return DateTime(
      now.year,
      int.tryParse(monthDayTime.group(1) ?? '') ?? now.month,
      int.tryParse(monthDayTime.group(2) ?? '') ?? now.day,
      int.tryParse(monthDayTime.group(3) ?? '') ?? 0,
      int.tryParse(monthDayTime.group(4) ?? '') ?? 0,
    );
  }
  final timestamp = int.tryParse(value);
  if (timestamp == null || timestamp <= 0) return null;
  if (timestamp > 1000000000000) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
  return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}

String _formatConversationTime(String raw) {
  final parsed = _parseConversationTime(raw);
  if (parsed == null) {
    return raw.length > 10 ? raw.substring(5, 16) : raw;
  }
  final now = DateTime.now();
  final local = parsed.toLocal();
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (now.year == local.year) {
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _firstNonEmpty(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
      return '$value'.trim();
    }
  }
  final nested = row['last_message'] ?? row['lastMessage'] ?? row['message'];
  if (nested is Map) {
    return _firstNonEmpty(Map<String, dynamic>.from(nested), keys);
  }
  return '';
}

class _ChatTile extends StatelessWidget {
  final VoidCallback onTap;
  final String avatar;
  final String name;
  final String subtitle;
  final ImOnlineStatus? online;
  final Widget trailing;
  final bool pinned;
  final IconData? fallbackIcon;
  const _ChatTile({
    required this.onTap,
    required this.avatar,
    required this.name,
    required this.subtitle,
    this.online,
    required this.trailing,
    this.pinned = false,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    return NativeListRow(
      onTap: onTap,
      selected: pinned,
      leading: AppAvatar(
        imageUrl: avatar,
        name: name,
        online: online?.online == true,
        showOnline: online != null,
        size: 52,
        fallbackIcon: fallbackIcon,
      ),
      title: name,
      subtitle: subtitle,
      trailing: trailing,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      minHeight: 78,
    );
  }
}

class _Empty extends StatelessWidget {
  final UserSession session;
  final VoidCallback onManual;
  const _Empty({required this.session, required this.onManual});

  @override
  Widget build(BuildContext context) => ProductEmptyState(
    icon: Icons.mark_chat_unread_outlined,
    title: '还没有会话',
    subtitle: '搜索用户名或从联系人里发起聊天。',
    actionLabel: '搜索用户名',
    onAction: onManual,
  );
}

String _groupCallRoomIdOf(UnifiedMessage message) =>
    '${message.content['room_id'] ?? message.content['call_id'] ?? message.raw['call_id'] ?? ''}'
        .trim();

int _groupCallStarterIdOf(UnifiedMessage message) =>
    int.tryParse(
      '${message.content['starter_user_id'] ?? message.content['inviter_id'] ?? message.fromUserId}',
    ) ??
    message.fromUserId;

int _groupCallActorIdOf(UnifiedMessage message) =>
    int.tryParse(
      '${message.content['user_id'] ?? message.content['from_user_id'] ?? message.raw['from_user_id'] ?? message.fromUserId}',
    ) ??
    message.fromUserId;

bool _isTerminalGroupCallStatus(Object? value) {
  final status = '${value ?? ''}'.toLowerCase().trim();
  return status == 'finished' ||
      status == 'canceled' ||
      status == 'cancelled' ||
      status == 'ended' ||
      status == 'failed' ||
      status == 'missed' ||
      status == 'rejected' ||
      status == 'busy';
}

bool _isGroupCallEndMessage(
  UnifiedMessage message, {
  required String roomId,
  required int inviterId,
}) {
  if (_groupCallRoomIdOf(message) != roomId) return false;
  final type = message.msgType.toLowerCase();
  if (type == 'group_call_record') return true;
  if (type == 'group_call_invite') {
    return _isTerminalGroupCallStatus(
      message.content['status'] ?? message.raw['status'],
    );
  }
  if (type == 'group_call_leave') {
    return _groupCallActorIdOf(message) == inviterId;
  }
  return false;
}

class _GroupChatScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final ImGroup group;
  final bool voiceMessageEnabled;
  final bool screenshotNoticeEnabled;
  const _GroupChatScreen({
    required this.session,
    required this.im,
    required this.group,
    this.voiceMessageEnabled = true,
    this.screenshotNoticeEnabled = false,
  });

  @override
  State<_GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<_GroupChatScreen>
    with WidgetsBindingObserver {
  final api = const ApiService();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  final imagePicker = ImagePicker();
  List<UnifiedMessage> messages = [];
  List<ImGroupMember> members = [];
  late ImGroup group = widget.group;
  StreamSubscription? sub;
  StreamSubscription? screenshotSub;
  StreamSubscription? groupProfileSub;
  Timer? refreshTimer;
  bool loading = true;
  bool sending = false;
  bool recordingVoice = false;
  bool sendingVoice = false;
  bool showEmojiPanel = false;
  bool voiceInputMode = false;
  bool showUserId = false;
  bool muteNotifications = false;
  bool pinnedChat = false;
  UserProfileSummary selfProfile = const UserProfileSummary();
  final Map<String, String> groupMessageSendStates = {};
  final Map<String, FailedMessageDraft> failedDrafts = {};
  bool mentionSheetOpen = false;
  bool stickToBottomDuringKeyboard = false;
  DateTime lastScreenshotNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int bottomScrollGeneration = 0;
  int keyboardSettleGeneration = 0;
  Timer? voiceTimer;
  DateTime? voiceStartedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadGroupPreferences());
    unawaited(loadSelfProfile());
    unawaited(loadGroupInfo(silent: true));
    load();
    unawaited(loadMembers());
    unawaited(ScreenshotMonitor.prepare());
    screenshotSub = ScreenshotMonitor.events.listen((_) {
      unawaited(_sendGroupScreenshotNotice());
    });
    refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && !loading) unawaited(load(silent: true));
    });
    inputFocus.addListener(_handleInputFocus);
    input.addListener(_handleGroupInputChanged);
    groupProfileSub = GroupProfileEvents.stream.listen((updated) {
      if (updated.id == group.id && mounted) {
        setState(() => group = updated);
      }
    });
    sub = widget.im.messages.listen((m) {
      if (m.toUid == group.groupNo || '${m.raw['group_id']}' == '${group.id}') {
        if (m.msgType == 'recall') {
          if (_applyRecallMessage(m)) _bottom();
          return;
        }
        if (m.msgType == 'screenshot') {
          if (mounted && !_hasMessage(m)) {
            setState(() => messages.add(m));
          }
          _bottom();
          return;
        }
        if (mounted && !_hasMessage(m)) {
          setState(() => messages.add(m));
        }
        _bottom();
      }
    });
  }

  Future<void> load({bool silent = false}) async {
    final firstLoad = messages.isEmpty && !silent;
    final shouldStickAfterLoad = _isNearBottom();
    try {
      final list = await api.getGroupChatLog(
        token: widget.session.token,
        groupId: group.id,
        myId: widget.session.id,
      );
      final failed = _pendingFailedMessages(list, await _loadFailedMessages());
      if (mounted) {
        final listWithFailed = _dedupeMessages([...list, ...failed]);
        final visible = messages.isEmpty
            ? listWithFailed
            : _mergeTimelineMessages(messages, listWithFailed);
        final changed = !_sameMessageTimeline(messages, visible);
        if (changed || loading) {
          setState(() {
            messages = visible;
            loading = false;
          });
        }
        if (firstLoad || (changed && shouldStickAfterLoad)) {
          _jumpToBottomAfterLayout();
        }
      }
    } finally {
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> loadMembers() async {
    try {
      final list = await api.getImGroupMembers(
        token: widget.session.token,
        groupId: group.id,
      );
      if (mounted) setState(() => members = list);
    } catch (_) {}
  }

  Future<void> loadGroupInfo({bool silent = false}) async {
    try {
      final latest = await api.getImGroupInfo(
        token: widget.session.token,
        groupId: group.id,
      );
      if (!mounted) return;
      setState(() => group = latest);
      GroupProfileEvents.notify(latest);
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('群资料刷新失败：$e')));
      }
    }
  }

  Future<void> loadSelfProfile() async {
    try {
      final next = await api.getUserOtherInformation(widget.session.token);
      if (mounted) setState(() => selfProfile = next);
    } catch (_) {}
  }

  String get _selfDisplayName => _firstText([
    selfProfile.nickname,
    _selfMember?.nickname,
    widget.session.nickname,
    selfProfile.username,
    _selfMember?.username,
    widget.session.username,
    '我',
  ]);

  String get _selfAvatar => _firstText([
    selfProfile.avatar,
    _selfMember?.avatar,
    widget.session.avatar,
  ]);

  ImGroupMember? get _selfMember {
    for (final member in members) {
      if (member.userId == widget.session.id) return member;
    }
    return null;
  }

  bool get _canMentionAll =>
      group.isOwner ||
      group.isAdmin ||
      group.ownerId == widget.session.id ||
      members.any(
        (member) =>
            member.userId == widget.session.id &&
            (member.isOwner || member.isAdmin),
      );

  bool get _effectiveScreenshotNotice =>
      widget.screenshotNoticeEnabled && group.screenshotNotifyEnabled;

  void _handleGroupInputChanged() {
    if (!inputFocus.hasFocus || mentionSheetOpen) return;
    final selection = input.selection;
    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > input.text.length) return;
    if (input.text.substring(cursor - 1, cursor) != '@') return;
    mentionSheetOpen = true;
    Future<void>.delayed(Duration.zero, () async {
      try {
        await showMentionPicker(replaceTriggerAt: true);
      } finally {
        mentionSheetOpen = false;
      }
    });
  }

  String get _conversationKey => ConversationPreferences.groupKey(group.id);
  String get _failedConversationKey => 'group:${widget.session.id}:${group.id}';

  Future<void> loadGroupPreferences() async {
    try {
      final results = await Future.wait<Set<String>>([
        ConversationPreferences.loadMuted(widget.session.id),
        ConversationPreferences.loadPinned(widget.session.id),
      ]);
      final config = await api.getUserInfoConfig();
      if (!mounted) return;
      setState(() {
        muteNotifications = results[0].contains(_conversationKey);
        pinnedChat = results[1].contains(_conversationKey);
        showUserId = config.showUserId;
      });
    } catch (_) {}
  }

  Future<void> setGroupMuted(bool value) async {
    setState(() => muteNotifications = value);
    await ConversationPreferences.setMuted(
      widget.session.id,
      _conversationKey,
      value,
    );
  }

  Future<void> setGroupPinned(bool value) async {
    setState(() => pinnedChat = value);
    await ConversationPreferences.setPinned(
      widget.session.id,
      _conversationKey,
      value,
    );
  }

  String _semanticMessageKey(UnifiedMessage message) {
    final seconds = message.createTime.millisecondsSinceEpoch ~/ 1000;
    return '${message.fromUserId}_${message.toUid}_${message.msgType}_${seconds}_${jsonEncode(message.content)}';
  }

  String _messageKey(UnifiedMessage message) {
    final raw = message.raw;
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
    if (direct.isNotEmpty && direct != '0' && direct != 'null') return direct;
    return _semanticMessageKey(message);
  }

  Set<String> _messageKeys(UnifiedMessage message) {
    final raw = message.raw;
    final keys = <String>{};
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
    if (direct.isNotEmpty && direct != '0') keys.add(direct);
    keys.add(_semanticMessageKey(message));
    return keys;
  }

  bool _hasMessage(UnifiedMessage message) {
    final keys = _messageKeys(message);
    return messages.any((m) => _messageKeys(m).any(keys.contains));
  }

  int _recallTargetMessageId(UnifiedMessage message) {
    return int.tryParse(
          '${message.content['message_id'] ?? message.raw['message_id'] ?? 0}',
        ) ??
        0;
  }

  UnifiedMessage _recalledMessage(UnifiedMessage source, {String? text}) {
    final content = {
      'message_id': source.messageId,
      'client_msg_no': source.raw['client_msg_no'] ?? '',
      'text': text ?? (source.isMe ? '你撤回了一条消息' : '撤回了一条消息'),
    };
    return source.copyWith(
      msgType: 'recall',
      content: content,
      raw: {
        ...source.raw,
        'msg_type': 'recall',
        'content': content,
        'is_recalled': 1,
      },
    );
  }

  bool _applyRecallMessage(UnifiedMessage recall) {
    final targetId = _recallTargetMessageId(recall);
    var changed = false;
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        final matchedId = targetId > 0 && message.messageId == targetId;
        final matchedClientNo =
            '${message.raw['client_msg_no'] ?? ''}'.isNotEmpty &&
            '${message.raw['client_msg_no'] ?? ''}' ==
                '${recall.content['client_msg_no'] ?? recall.raw['client_msg_no'] ?? ''}';
        if (matchedId || matchedClientNo) {
          messages[i] = _recalledMessage(
            message,
            text: '${recall.content['text'] ?? '消息已撤回'}',
          );
          changed = true;
          break;
        }
      }
    });
    return changed;
  }

  List<UnifiedMessage> _dedupeMessages(List<UnifiedMessage> source) {
    final seen = <String>{};
    final result = <UnifiedMessage>[];
    for (final message in source) {
      final keys = _messageKeys(message);
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      result.add(message);
    }
    return result;
  }

  List<UnifiedMessage> _mergeTimelineMessages(
    List<UnifiedMessage> current,
    List<UnifiedMessage> incoming,
  ) {
    final merged = _dedupeMessages([...incoming, ...current]);
    merged.sort((a, b) {
      final time = a.createTime.compareTo(b.createTime);
      if (time != 0) return time;
      return a.messageId.compareTo(b.messageId);
    });
    return merged;
  }

  String _messageVersion(UnifiedMessage message) => jsonEncode({
    'id': message.messageId,
    'type': message.msgType,
    'content': message.content,
    'read': message.read,
    'read_at': message.readAt?.toIso8601String(),
    'recalled': message.raw['is_recalled'],
  });

  bool _sameMessageTimeline(List<UnifiedMessage> a, List<UnifiedMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_messageKeys(a[i]).any(_messageKeys(b[i]).contains)) return false;
      if (_messageVersion(a[i]) != _messageVersion(b[i])) return false;
    }
    return true;
  }

  Future<List<UnifiedMessage>> _loadFailedMessages() async {
    final drafts = await FailedMessageStore.load(
      widget.session.id,
      _failedConversationKey,
    );
    failedDrafts
      ..clear()
      ..addEntries(drafts.map((draft) => MapEntry(draft.key, draft)));
    for (final draft in drafts) {
      groupMessageSendStates[draft.key] = 'failed';
    }
    return drafts
        .map(
          (draft) =>
              UnifiedMessage.fromPayload(draft.payload, widget.session.id),
        )
        .toList();
  }

  List<UnifiedMessage> _pendingFailedMessages(
    List<UnifiedMessage> serverMessages,
    List<UnifiedMessage> failedMessages,
  ) {
    final serverKeys = <String>{
      for (final message in serverMessages) ..._messageKeys(message),
    };
    final pending = <UnifiedMessage>[];
    for (final message in failedMessages) {
      final key = _messageKey(message);
      if (_messageKeys(message).any(serverKeys.contains)) {
        failedDrafts.remove(key);
        groupMessageSendStates.remove(key);
        unawaited(_removeFailedDraft(key));
      } else {
        pending.add(message);
      }
    }
    return pending;
  }

  Future<void> _saveFailedDraft(FailedMessageDraft draft) async {
    failedDrafts[draft.key] = draft;
    groupMessageSendStates[draft.key] = 'failed';
    await FailedMessageStore.upsert(
      widget.session.id,
      _failedConversationKey,
      draft,
    );
  }

  Future<void> _removeFailedDraft(String key) async {
    failedDrafts.remove(key);
    await FailedMessageStore.remove(
      widget.session.id,
      _failedConversationKey,
      key,
    );
  }

  Future<void> sendGroupPayload(
    Map<String, dynamic> payload, {
    required String fallbackContent,
    int messageType = 0,
    FailedMessageDraft? retryDraft,
  }) async {
    final draft =
        retryDraft ??
        FailedMessageDraft(
          payload: Map<String, dynamic>.from(payload),
          fallbackContent: fallbackContent,
          messageType: messageType,
        );
    final message = UnifiedMessage.fromPayload(
      draft.payload,
      widget.session.id,
    );
    final key = _messageKey(message);
    setState(() {
      sending = true;
      groupMessageSendStates[key] = 'pending';
      if (!_hasMessage(message)) messages.add(message);
    });
    _bottom();
    try {
      await api.sendGroupMessage(
        token: widget.session.token,
        groupId: group.id,
        content: draft.fallbackContent,
        messageType: draft.messageType,
        payload: draft.payload,
      );
      if (!mounted) return;
      setState(() {
        if (groupMessageSendStates[key] != 'read') {
          groupMessageSendStates[key] = 'success';
        }
        failedDrafts.remove(key);
      });
      unawaited(_removeFailedDraft(key));
    } catch (e) {
      if (!mounted) return;
      setState(() => groupMessageSendStates[key] = 'failed');
      unawaited(_saveFailedDraft(draft));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> retryFailedGroupMessage(UnifiedMessage message) async {
    final key = _messageKey(message);
    final draft = failedDrafts[key];
    if (draft == null) return;
    await sendGroupPayload(
      draft.payload,
      fallbackContent: draft.fallbackContent,
      messageType: draft.messageType,
      retryDraft: draft,
    );
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    input.clear();
    final mentionAll = _canMentionAll && _containsMentionAll(text);
    final mentionUserIds = _mentionedUserIds(text);
    final payload = {
      'msg_type': 'text',
      'client_msg_no':
          'group_${group.id}_${DateTime.now().microsecondsSinceEpoch}',
      'from_user_id': widget.session.id,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': group.groupNo,
      'group_id': group.id,
      'group_no': group.groupNo,
      'nickname': _selfDisplayName,
      'avatar': _selfAvatar,
      'content': {
        'text': text,
        if (mentionAll) 'mention_all': true,
        if (mentionUserIds.isNotEmpty) 'mention_user_ids': mentionUserIds,
      },
      'create_time': DateTime.now().toIso8601String(),
    };
    await sendGroupPayload(payload, fallbackContent: text);
  }

  bool _containsMentionAll(String text) =>
      RegExp(r'(^|\s)@所有人(\s|$)').hasMatch(text);

  List<int> _mentionedUserIds(String text) {
    final ids = <int>{};
    for (final member in members) {
      if (member.userId <= 0 || member.userId == widget.session.id) continue;
      final labels = <String>{member.nickname.trim(), member.username.trim()}
        ..removeWhere((value) => value.isEmpty);
      for (final label in labels) {
        if (text.contains('@$label')) ids.add(member.userId);
      }
    }
    return ids.toList()..sort();
  }

  Map<String, dynamic> _groupMessagePayload({
    required String type,
    required String clientMsgNo,
    required Map<String, dynamic> content,
  }) {
    final now = DateTime.now();
    return {
      'msg_type': type,
      'client_msg_no': clientMsgNo,
      'from_user_id': widget.session.id,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': group.groupNo,
      'group_id': group.id,
      'group_no': group.groupNo,
      'nickname': _selfDisplayName,
      'avatar': _selfAvatar,
      'content': {
        ...content,
        'nickname': _selfDisplayName,
        'avatar': _selfAvatar,
      },
      'create_time': now.toIso8601String(),
      'timestamp': now.millisecondsSinceEpoch,
    };
  }

  Future<void> _sendGroupCallMessage({
    required String contentText,
    required Map<String, dynamic> payload,
    bool optimistic = true,
  }) async {
    if (optimistic && mounted) {
      final message = UnifiedMessage.fromPayload(payload, widget.session.id);
      if (!_hasMessage(message)) setState(() => messages.add(message));
      _bottom();
    }
    await api.sendGroupMessage(
      token: widget.session.token,
      groupId: group.id,
      content: contentText,
      payload: payload,
    );
    unawaited(load(silent: true));
  }

  Future<void> showGroupCallSheet() async {
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.call_outlined,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '群语音通话',
              subtitle: '向群成员发送语音通话邀请',
              minHeight: 64,
              onTap: () => Navigator.pop(sheetContext, 'voice'),
            ),
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.videocam_outlined,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '群视频通话',
              subtitle: '向群成员发送视频通话邀请',
              minHeight: 64,
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'voice') {
      unawaited(startGroupCall(video: false));
    } else if (action == 'video') {
      unawaited(startGroupCall(video: true));
    }
  }

  Future<void> startGroupCall({required bool video}) async {
    if (members.isEmpty) await loadMembers();
    final now = DateTime.now().millisecondsSinceEpoch;
    final roomId = 'group_call_${group.id}_${widget.session.id}_$now';
    final media = video ? 'video' : 'audio';
    final payload = _groupMessagePayload(
      type: 'group_call_invite',
      clientMsgNo: '${roomId}_invite',
      content: {
        'room_id': roomId,
        'call_id': roomId,
        'media': media,
        'status': 'inviting',
        'starter_user_id': widget.session.id,
        'starter_nickname': widget.session.nickname ?? '我',
        'group_id': group.id,
        'group_no': group.groupNo,
        'member_count': group.memberCount,
      },
    );
    final label = video ? '视频' : '语音';
    try {
      await _sendGroupCallMessage(
        contentText: '[群$label通话] ${widget.session.nickname ?? '我'} 发起了群通话',
        payload: payload,
      );
      if (!mounted) return;
      await _openGroupCallRoom(
        roomId: roomId,
        video: video,
        inviterId: widget.session.id,
        inviterName: widget.session.nickname ?? '我',
      );
    } catch (e, st) {
      AppLogger.error('CALL', '群通话邀请发送失败 room=$roomId', error: e, stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('群通话发起失败：$e')));
    }
  }

  Future<void> joinGroupCall(UnifiedMessage message) async {
    final roomId =
        '${message.content['room_id'] ?? message.content['call_id'] ?? ''}'
            .trim();
    if (roomId.isEmpty) return;
    final media = '${message.content['media']}'.contains('video')
        ? 'video'
        : 'audio';
    await _openGroupCallRoom(
      roomId: roomId,
      video: media == 'video',
      inviterId:
          int.tryParse(
            '${message.content['starter_user_id'] ?? message.fromUserId}',
          ) ??
          message.fromUserId,
      inviterName:
          '${message.content['starter_nickname'] ?? message.content['nickname'] ?? _senderName(message)}',
    );
  }

  Future<void> _openGroupCallRoom({
    required String roomId,
    required bool video,
    required int inviterId,
    required String inviterName,
  }) async {
    final selfMember = ImGroupMember(
      userId: widget.session.id,
      nickname: widget.session.nickname ?? '我',
      avatar: widget.session.avatar,
    );
    final roomMembers = <ImGroupMember>[
      selfMember,
      for (final member in members)
        if (member.userId != widget.session.id) member,
    ];
    final result = await Navigator.push<_GroupCallRoomResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _GroupCallRoomScreen(
          session: widget.session,
          im: widget.im,
          api: api,
          group: group,
          members: roomMembers,
          roomId: roomId,
          video: video,
          inviterId: inviterId,
          inviterName: inviterName,
        ),
      ),
    );
    if (result == null) return;
    if (result.inviterId == widget.session.id) {
      await sendGroupCallRecord(result);
    } else {
      unawaited(load(silent: true));
    }
  }

  Future<void> sendGroupCallRecord(_GroupCallRoomResult result) async {
    final label = result.video ? '视频' : '语音';
    final payload = _groupMessagePayload(
      type: 'group_call_record',
      clientMsgNo:
          '${result.roomId}_${widget.session.id}_${result.endedAt.millisecondsSinceEpoch}_record',
      content: {
        'room_id': result.roomId,
        'call_id': result.roomId,
        'media': result.video ? 'video' : 'audio',
        'status': result.status,
        'duration': result.durationSeconds,
        'starter_user_id': result.inviterId,
        'starter_nickname': result.inviterName,
        'ended_user_id': widget.session.id,
        'ended_nickname': widget.session.nickname ?? '我',
        'participants': result.participantIds,
        'ended_at': result.endedAt.toIso8601String(),
        'call_record_key':
            '${result.roomId}_${widget.session.id}_${result.endedAt.millisecondsSinceEpoch}',
      },
    );
    try {
      await _sendGroupCallMessage(
        contentText:
            '[群$label通话] ${_groupCallStatusText(result.status, result.durationSeconds)}',
        payload: payload,
      );
    } catch (e, st) {
      AppLogger.error(
        'CALL',
        '群通话记录发送失败 room=${result.roomId}',
        error: e,
        stack: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('群通话记录发送失败：$e')));
      }
    }
  }

  String _groupCallStatusText(String status, int duration) {
    if (status == 'finished') return '通话时长 ${_formatDuration(duration)}';
    if (status == 'failed') return '连接失败';
    if (status == 'busy') return '对方忙线';
    if (status == 'missed') return '未接听';
    if (status == 'rejected') return '已拒绝';
    return '已取消';
  }

  String _formatDuration(int total) {
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }

  bool _isNearBottom({double distance = 160}) {
    if (!scroll.hasClients) return true;
    return scroll.position.maxScrollExtent - scroll.position.pixels <= distance;
  }

  void _bottom({Duration delay = const Duration(milliseconds: 80)}) {
    Future.delayed(delay, () {
      if (!mounted) return;
      unawaited(_settleToBottomAfterLayout());
    });
  }

  void _jumpToBottomAfterLayout() {
    unawaited(_settleToBottomAfterLayout(animated: false));
  }

  Future<void> _waitForLayoutFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<void> _settleToBottomAfterLayout({bool animated = true}) async {
    final generation = ++bottomScrollGeneration;
    for (var i = 0; i < 4; i++) {
      await _waitForLayoutFrame();
      if (!mounted || generation != bottomScrollGeneration) return;
      _stickToBottom(animated: animated && i == 3);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  void _handleInputFocus() {
    stickToBottomDuringKeyboard = _isNearBottom(distance: 260);
    if (inputFocus.hasFocus && stickToBottomDuringKeyboard) {
      _settleKeyboardBottom();
    }
  }

  void _settleKeyboardBottom() {
    final generation = ++keyboardSettleGeneration;
    void schedule(Duration delay) {
      Future.delayed(delay, () {
        if (!mounted || generation != keyboardSettleGeneration) return;
        _jumpToBottomAfterLayout();
      });
    }

    schedule(Duration.zero);
    schedule(const Duration(milliseconds: 80));
    schedule(const Duration(milliseconds: 180));
    schedule(const Duration(milliseconds: 320));
  }

  void _stickToBottom({bool animated = true}) {
    if (!scroll.hasClients) return;
    final target = scroll.position.maxScrollExtent;
    if (animated) {
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    } else {
      scroll.jumpTo(target);
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (inputFocus.hasFocus) {
      if (stickToBottomDuringKeyboard || _isNearBottom(distance: 260)) {
        stickToBottomDuringKeyboard = true;
        _settleKeyboardBottom();
      }
    } else {
      stickToBottomDuringKeyboard = false;
    }
  }

  Future<void> openGroupSettings() async {
    final updated = await Navigator.push<ImGroup?>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          session: widget.session,
          initialGroup: group,
          muteNotifications: muteNotifications,
          pinnedChat: pinnedChat,
          screenshotNoticeEnabled: widget.screenshotNoticeEnabled,
          onSearchHistory: openGroupHistorySearch,
          onMuteChanged: (value) => unawaited(setGroupMuted(value)),
          onPinChanged: (value) => unawaited(setGroupPinned(value)),
          onClearHistory: clearGroupChatHistory,
          onLocalSettingsChanged: () => unawaited(loadGroupPreferences()),
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => group = updated);
      GroupProfileEvents.notify(updated);
      unawaited(loadMembers());
    }
    unawaited(loadGroupInfo(silent: true));
    unawaited(loadGroupPreferences());
  }

  void _showGroupNotice(String notice) {
    showDialog<void>(
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
              const NativeIconBox(
                icon: Icons.campaign_outlined,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('群公告', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: _NoticeRichPreview(
                    text: notice,
                    richText: group.noticeRichText,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openGroupHistorySearch() async {
    final selected = await Navigator.push<UnifiedMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatHistorySearchScreen(
          title: group.name,
          subtitle: '查找 ${group.name} 的聊天记录',
          loadMessages: (keyword) async {
            final all = <UnifiedMessage>[];
            for (var page = 1; page <= 8; page++) {
              final list = await api.getGroupChatLog(
                token: widget.session.token,
                groupId: group.id,
                myId: widget.session.id,
                page: page,
                limit: 50,
              );
              if (list.isEmpty) break;
              all.addAll(list.where((m) => !_isHiddenGroupCallEvent(m)));
              if (list.length < 50) break;
            }
            return all;
          },
        ),
      ),
    );
    if (selected != null) await locateGroupMessage(selected);
  }

  Future<void> clearGroupChatHistory() async {
    final ok = await _showBlinConfirm(
      context,
      title: '清空群聊天记录',
      message: '确定要清空当前群聊记录吗？清空范围按后台应用配置生效，会话入口会继续保留。',
      icon: Icons.delete_sweep_outlined,
      confirmLabel: '清空',
    );
    if (!ok) return;
    try {
      final msg = await api.clearGroupChatHistory(
        token: widget.session.token,
        groupId: group.id,
      );
      if (!mounted) return;
      setState(() {
        messages = [];
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清空失败：$e')));
      }
    }
  }

  ImGroupMember? _memberOf(UnifiedMessage message) {
    if (message.isMe) {
      return ImGroupMember(
        userId: widget.session.id,
        nickname: _selfDisplayName,
        avatar: _selfAvatar,
      );
    }
    for (final member in members) {
      if (member.userId == message.fromUserId) return member;
    }
    return null;
  }

  String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  String _senderName(UnifiedMessage message) {
    final raw = message.raw;
    final content = message.content;
    final member = _memberOf(message);
    final fromUser = raw['fromUser'] is Map
        ? Map<String, dynamic>.from(raw['fromUser'])
        : raw['from_user'] is Map
        ? Map<String, dynamic>.from(raw['from_user'])
        : const <String, dynamic>{};
    final name = _firstText([
      member?.nickname,
      raw['nickname'],
      raw['from_nickname'],
      raw['sender_name'],
      fromUser['nickname'],
      fromUser['username'],
      content['nickname'],
      showUserId ? '用户${message.fromUserId}' : '群成员',
    ]);
    return name;
  }

  String _avatarOf(UnifiedMessage message) {
    final raw = message.raw;
    final content = message.content;
    final member = _memberOf(message);
    final fromUser = raw['fromUser'] is Map
        ? Map<String, dynamic>.from(raw['fromUser'])
        : raw['from_user'] is Map
        ? Map<String, dynamic>.from(raw['from_user'])
        : const <String, dynamic>{};
    return _firstText([
      member?.avatar,
      raw['avatar'],
      raw['from_avatar'],
      raw['user_avatar'],
      fromUser['avatar'],
      fromUser['usertx'],
      content['avatar'],
    ]);
  }

  bool _isGroupCallRoomFinishedIn(
    Iterable<UnifiedMessage> source, {
    required String roomId,
    required int inviterId,
  }) {
    if (roomId.isEmpty) return true;
    for (final message in source) {
      if (_isGroupCallEndMessage(message, roomId: roomId, inviterId: inviterId))
        return true;
    }
    return false;
  }

  bool _isGroupCallFinished(UnifiedMessage invite) {
    final roomId = _groupCallRoomIdOf(invite);
    return _isGroupCallRoomFinishedIn(
      messages,
      roomId: roomId,
      inviterId: _groupCallStarterIdOf(invite),
    );
  }

  Future<bool> _refreshGroupCallFinished(UnifiedMessage invite) async {
    final roomId = _groupCallRoomIdOf(invite);
    if (roomId.isEmpty) return true;
    final inviterId = _groupCallStarterIdOf(invite);
    try {
      final latest = await api.getGroupChatLog(
        token: widget.session.token,
        groupId: group.id,
        myId: widget.session.id,
        limit: 100,
      );
      if (mounted && latest.isNotEmpty) {
        setState(() => messages = _mergeTimelineMessages(messages, latest));
      }
      return _isGroupCallRoomFinishedIn(
        latest,
        roomId: roomId,
        inviterId: inviterId,
      );
    } catch (e) {
      AppLogger.warn('CALL', '群通话结束状态刷新失败 room=$roomId', data: e);
      return false;
    }
  }

  void _showGroupCallEndedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('群通话已结束')));
  }

  Future<void> _handleJoinGroupCall(UnifiedMessage message) async {
    if (_isGroupCallFinished(message) ||
        await _refreshGroupCallFinished(message)) {
      _showGroupCallEndedSnack();
      return;
    }
    await joinGroupCall(message);
  }

  List<_GroupTimelineItem> _timelineItems() {
    final items = <_GroupTimelineItem>[];
    String? lastDate;
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (_isHiddenGroupCallEvent(message)) continue;
      final date = _dateLabel(message.createTime);
      if (date != lastDate) {
        items.add(_GroupTimelineDate(date));
        lastDate = date;
      }
      if (_isSystemMessage(message)) {
        items.add(_GroupTimelineSystem(_systemText(message)));
      } else {
        items.add(_GroupTimelineMessage(message));
      }
      if (i == messages.length - 2) items.add(const _GroupTimelineNewDivider());
    }
    return items;
  }

  bool _isSystemMessage(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    final text = '${message.content['text'] ?? message.preview}';
    return type == 'system' ||
        type == 'notice' ||
        type == 'screenshot' ||
        type == 'recall' ||
        text.startsWith('欢迎 ') ||
        text.contains('加入') ||
        text.contains('退出群聊') ||
        text.contains('移除群聊') ||
        text.contains('撤回了一条');
  }

  bool _isHiddenGroupCallEvent(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    return type == 'group_call_join' || type == 'group_call_leave';
  }

  String _systemText(UnifiedMessage message) {
    final text = '${message.content['text'] ?? message.preview}'.trim();
    return text.isEmpty ? '群聊系统消息' : text;
  }

  String _dateLabel(DateTime time) {
    final now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return '今天';
    }
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  void insertQuickEmoji(String emoji) {
    final start = input.selection.start < 0
        ? input.text.length
        : input.selection.start;
    final end = input.selection.end < 0
        ? input.text.length
        : input.selection.end;
    input.text = input.text.replaceRange(start, end, emoji);
    input.selection = TextSelection.collapsed(offset: start + emoji.length);
    inputFocus.requestFocus();
  }

  void toggleEmojiPanel() {
    FocusScope.of(context).unfocus();
    setState(() {
      showEmojiPanel = !showEmojiPanel;
      if (showEmojiPanel) voiceInputMode = false;
    });
  }

  void toggleVoiceInputMode() {
    if (!widget.voiceMessageEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音消息已被后台关闭')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      voiceInputMode = !voiceInputMode;
      if (voiceInputMode) showEmojiPanel = false;
    });
  }

  Future<void> locateGroupMessage(UnifiedMessage target) async {
    final targetKeys = _messageKeys(target);
    final exists = messages.any(
      (m) => _messageKeys(m).any(targetKeys.contains),
    );
    if (!exists) {
      setState(() => messages = _mergeTimelineMessages(messages, [target]));
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !scroll.hasClients) return;
    final timeline = _timelineItems();
    final timelineIndex = timeline.indexWhere((item) {
      if (item is! _GroupTimelineMessage) return false;
      return _messageKeys(item.message).any(targetKeys.contains);
    });
    if (timelineIndex < 0) return;
    final targetOffset = (timelineIndex * 86.0).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    bottomScrollGeneration++;
    await scroll.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> showMentionPicker({bool replaceTriggerAt = false}) async {
    if (members.isEmpty) await loadMembers();
    if (!mounted) return;
    final selected = await showModalBottomSheet<_MentionSelection>(
      context: context,
      showDragHandle: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) {
        final visibleMembers =
            members
                .where((member) => member.userId != widget.session.id)
                .toList()
              ..sort((a, b) => a.nickname.compareTo(b.nickname));
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    '选择提醒的人',
                    style: TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_canMentionAll)
                  NativeListRow(
                    leading: const NativeIconBox(
                      icon: Icons.notifications_active_outlined,
                      color: BlinStyle.primary,
                      size: 40,
                    ),
                    title: '@所有人',
                    subtitle: '仅群主和管理员可用',
                    minHeight: 64,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      const _MentionSelection.all(),
                    ),
                  ),
                for (final member in visibleMembers)
                  NativeListRow(
                    leading: AppAvatar(
                      imageUrl: member.avatar,
                      name: member.nickname,
                      size: 40,
                    ),
                    title: member.nickname,
                    subtitle: member.username.isNotEmpty
                        ? '@${member.username}'
                        : member.role,
                    minHeight: 62,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      _MentionSelection.member(member),
                    ),
                  ),
                if (visibleMembers.isEmpty)
                  const NativeListRow(
                    leading: NativeIconBox(
                      icon: Icons.group_outlined,
                      color: BlinStyle.subtle,
                      size: 40,
                    ),
                    title: '暂无可提醒成员',
                    subtitle: '群成员加载后会显示在这里',
                    minHeight: 64,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    final label = selected.all ? '@所有人 ' : '@${selected.member!.nickname} ';
    _insertMentionText(label, replaceTriggerAt: replaceTriggerAt);
  }

  void _insertMentionText(String label, {required bool replaceTriggerAt}) {
    final selection = input.selection;
    var start = selection.start < 0 ? input.text.length : selection.start;
    var end = selection.end < 0 ? input.text.length : selection.end;
    if (replaceTriggerAt &&
        start > 0 &&
        input.text.substring(start - 1, start) == '@') {
      start -= 1;
    }
    input.text = input.text.replaceRange(start, end, label);
    input.selection = TextSelection.collapsed(offset: start + label.length);
    inputFocus.requestFocus();
  }

  Future<void> _sendGroupScreenshotNotice() async {
    if (!_effectiveScreenshotNotice) return;
    final now = DateTime.now();
    if (now.difference(lastScreenshotNoticeAt) < const Duration(seconds: 3)) {
      return;
    }
    lastScreenshotNoticeAt = now;
    final nickname = (widget.session.nickname ?? '').trim().isEmpty
        ? '我'
        : widget.session.nickname!.trim();
    final text = '$nickname 截屏了';
    final payload = _groupMessagePayload(
      type: 'screenshot',
      clientMsgNo:
          'group_screenshot_${group.id}_${widget.session.id}_${now.microsecondsSinceEpoch}',
      content: {'text': text, 'screenshot': true},
    );
    final message = UnifiedMessage.fromPayload(payload, widget.session.id);
    if (mounted && !_hasMessage(message)) {
      setState(() => messages.add(message));
      _bottom();
    }
    try {
      await api.sendGroupMessage(
        token: widget.session.token,
        groupId: group.id,
        content: text,
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> sendGroupAttachment({required String mediaType}) async {
    if (sending) return;
    final result = await FilePicker.platform.pickFiles(
      type: mediaType == 'image'
          ? FileType.image
          : mediaType == 'video'
          ? FileType.video
          : FileType.any,
      allowMultiple: false,
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    final bytes = file?.bytes;
    if (file == null) return;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前平台暂时无法读取这个文件')));
      }
      return;
    }
    await _sendGroupAttachmentBytes(
      mediaType: mediaType,
      bytes: bytes,
      filename: file.name,
      size: file.size,
    );
  }

  bool get _cameraCaptureSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> captureGroupAttachment() async {
    if (sending) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CaptureActionSheet(
        onPhoto: () => Navigator.pop(context, 'image'),
        onVideo: () => Navigator.pop(context, 'video'),
      ),
    );
    if (action == null || !mounted) return;
    if (!_cameraCaptureSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持直接拍摄，请使用图片或文件入口选择媒体')),
      );
      return;
    }
    try {
      final picked = action == 'image'
          ? await imagePicker.pickImage(
              source: ImageSource.camera,
              imageQuality: 88,
            )
          : await imagePicker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 3),
            );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw ApiException('拍摄文件为空');
      await _sendGroupAttachmentBytes(
        mediaType: action,
        bytes: bytes,
        filename: _captureFilename(picked, action),
        size: bytes.length,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'image' ? '拍照发送失败：$e' : '视频发送失败：$e')),
      );
    }
  }

  String _captureFilename(XFile file, String mediaType) {
    final raw = file.name.trim();
    if (raw.isNotEmpty && raw != 'null') return raw;
    final ext = mediaType == 'image' ? 'jpg' : 'mp4';
    return 'group_${mediaType}_${group.id}_${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  Future<void> _sendGroupAttachmentBytes({
    required String mediaType,
    required List<int> bytes,
    required String filename,
    required int size,
  }) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: filename,
      );
      final url = _pickUploadUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回文件地址');
      final type = mediaType == 'image'
          ? 'image'
          : mediaType == 'video'
          ? 'video'
          : 'file';
      final caption = input.text.trim();
      final payload = _groupMessagePayload(
        type: type,
        clientMsgNo:
            'group_${type}_${group.id}_${widget.session.id}_${DateTime.now().microsecondsSinceEpoch}',
        content: {
          'url': url,
          'file_url': url,
          if (type == 'image') 'image_path': url,
          if (type == 'video') ...{
            'video_url': url,
            'video_path': url,
            'file_path': url,
          },
          'name': filename,
          'file_name': filename,
          'size': size,
          if (caption.isNotEmpty && (type == 'image' || type == 'video'))
            'text': caption,
        },
      );
      input.clear();
      await sendGroupPayload(
        payload,
        fallbackContent: type == 'image'
            ? '[图片]'
            : type == 'video'
            ? '[视频] $filename'
            : '[文件] $filename',
        messageType: type == 'image'
            ? 1
            : type == 'video'
            ? 4
            : 3,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> toggleVoiceRecording() async {
    if (!widget.voiceMessageEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音消息已被后台关闭')));
      return;
    }
    if (recordingVoice) {
      await _finishVoiceRecording(send: true);
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (sending || sendingVoice) return;
    try {
      final allowed = await recorder.hasPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先允许麦克风权限')));
        return;
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      final path = await voiceRecordPath(
        'group_voice_${group.id}_${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        recordingVoice = true;
        voiceStartedAt = DateTime.now();
      });
      voiceTimer?.cancel();
      voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('录音启动失败：$e')));
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    voiceTimer?.cancel();
    final startedAt = voiceStartedAt;
    String? path;
    try {
      path = await recorder.stop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('录音结束失败：$e')));
      }
    }
    if (!mounted) return;
    final duration = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;
    setState(() {
      recordingVoice = false;
      voiceStartedAt = null;
    });
    if (!send || path == null || path.isEmpty) return;
    if (duration < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('说话时间太短')));
      return;
    }
    await sendVoiceFile(path: path, duration: duration);
  }

  Future<void> sendVoiceFile({
    required String path,
    required int duration,
  }) async {
    if (sendingVoice) return;
    setState(() => sendingVoice = true);
    try {
      final bytes = await readVoiceRecordBytes(path);
      if (bytes.isEmpty) throw ApiException('录音文件为空');
      final filename =
          'group_voice_${group.id}_${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: filename,
      );
      final url = _pickUploadUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回语音地址');
      final payload = _groupMessagePayload(
        type: 'voice',
        clientMsgNo:
            'group_voice_${group.id}_${widget.session.id}_${DateTime.now().microsecondsSinceEpoch}',
        content: {
          'url': url,
          'file_url': url,
          'name': filename,
          'duration': duration,
          'size': bytes.length,
          'mime': 'audio/mp4',
        },
      );
      await sendGroupPayload(
        payload,
        fallbackContent: '[语音] ${formatVoiceDuration(duration)}',
        messageType: 5,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('语音发送失败：$e')));
    } finally {
      if (mounted) setState(() => sendingVoice = false);
    }
  }

  String _pickUploadUrl(Map<String, dynamic> data) {
    for (final key in const [
      'url',
      'path',
      'file_url',
      'video_url',
      'video_path',
      'src',
      'image',
      'image_path',
      'audio',
      'file_path',
      'oss_path',
    ]) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return media_url.resolveMediaUrl(value);
      }
    }
    return '';
  }

  String _messagePlainText(UnifiedMessage message) {
    if (message.msgType == 'text') {
      return '${message.content['text'] ?? message.preview}';
    }
    if (message.msgType == 'emoji') {
      return '${message.content['emoji'] ?? message.content['text'] ?? ''}';
    }
    return message.preview;
  }

  bool _canCopyMessage(UnifiedMessage message) {
    return ![
      'image',
      'video',
      'voice',
      'file',
      'recall',
    ].contains(message.msgType);
  }

  Future<void> showGroupMessageActions(UnifiedMessage message) async {
    if (message.msgType == 'recall') return;
    final isFailed = groupMessageSendStates[_messageKey(message)] == 'failed';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFailed)
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.refresh_rounded,
                  color: BlinStyle.danger,
                  size: 40,
                ),
                title: '重新发送',
                subtitle: '再次发送这条失败消息',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'retry'),
              ),
            if (_canCopyMessage(message))
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.copy_rounded,
                  color: BlinStyle.primary,
                  size: 40,
                ),
                title: '复制',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.forward_rounded,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '转发给好友',
              minHeight: 58,
              onTap: () => Navigator.pop(sheetContext, 'forward'),
            ),
            if (message.isMe && message.messageId > 0)
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.undo_rounded,
                  color: Color(0xFFE05A47),
                  size: 40,
                ),
                title: '撤回',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'recall'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'retry') {
      await retryFailedGroupMessage(message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messagePlainText(message)));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制')));
      }
    } else if (action == 'forward') {
      await forwardGroupMessage(message);
    } else if (action == 'recall') {
      await recallGroupMessage(message);
    }
  }

  Future<void> forwardGroupMessage(UnifiedMessage message) async {
    try {
      final friends = await api.getFriends(widget.session.token);
      if (!mounted) return;
      final target = await showModalBottomSheet<UserSearchResult>(
        context: context,
        showDragHandle: true,
        backgroundColor: BlinStyle.surface(context),
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  '选择转发对象',
                  style: TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final friend in friends)
                NativeListRow(
                  leading: AppAvatar(
                    imageUrl: friend.avatar,
                    name: friend.nickname,
                    size: 40,
                  ),
                  title: friend.nickname,
                  subtitle: showUserId
                      ? 'ID ${friend.id}'
                      : '@${friend.username}',
                  minHeight: 62,
                  onTap: () => Navigator.pop(sheetContext, friend),
                ),
            ],
          ),
        ),
      );
      if (target == null) return;
      final payload = {
        'message_id': 0,
        'client_msg_no':
            '${widget.session.id}_${target.id}_${DateTime.now().microsecondsSinceEpoch}_group_forward',
        'from_user_id': widget.session.id,
        'to_user_id': target.id,
        'from_uid': ImService.uidForUser(widget.session.id),
        'to_uid': ImService.uidForUser(target.id),
        'msg_type': message.msgType,
        'content': Map<String, dynamic>.from(message.content),
        'create_time': DateTime.now().toIso8601String(),
      };
      await api.sendMessage(
        token: widget.session.token,
        receiverId: target.id,
        content: _messagePlainText(message),
        messageType: _legacyMessageType(message.msgType),
        payload: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已转发给 ${target.nickname}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('转发失败：$e')));
      }
    }
  }

  Future<void> recallGroupMessage(UnifiedMessage message) async {
    try {
      final msg = await api.recallMessage(
        token: widget.session.token,
        messageId: message.messageId,
        groupId: group.id,
      );
      if (!mounted) return;
      setState(() {
        final index = messages.indexWhere(
          (item) => item.messageId == message.messageId,
        );
        if (index >= 0) messages[index] = _recalledMessage(messages[index]);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('撤回失败：$e')));
      }
    }
  }

  int _legacyMessageType(String msgType) {
    if (msgType == 'image') return 1;
    if (msgType == 'transfer') return 2;
    if (msgType == 'file') return 3;
    if (msgType == 'video') return 4;
    if (msgType == 'voice') return 5;
    return 0;
  }

  String _messageFileUrl(UnifiedMessage message) => firstMediaUrl([
    message.content['url'],
    message.content['file_url'],
    message.content['video_url'],
    message.content['video_path'],
    message.content['file_path'],
    message.content['path'],
    message.content['src'],
    message.content['image_path'],
  ]);

  String _messageFilename(UnifiedMessage message) {
    final raw =
        '${message.content['name'] ?? message.content['file_name'] ?? ''}'
            .trim();
    if (raw.isNotEmpty) return raw;
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      return message.msgType == 'image' ? 'image.jpg' : 'download';
    }
    final path = Uri.tryParse(url)?.path ?? url;
    final parts = path.split('/').where((e) => e.isNotEmpty).toList();
    final name = parts.isEmpty ? '' : parts.last;
    if (name.trim().isEmpty) {
      return message.msgType == 'image' ? 'image.jpg' : 'download';
    }
    return name;
  }

  Future<void> downloadGroupMessageFile(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可下载的文件地址')));
      return;
    }
    try {
      final path = await downloadRemoteFile(
        url: url,
        filename: _messageFilename(message),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  int _messageFileSize(UnifiedMessage message) =>
      int.tryParse('${message.content['size'] ?? 0}') ?? 0;

  Future<void> openGroupImagePreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(
          url: url,
          onDownload: () => downloadGroupMessageFile(message),
          onForward: () => forwardGroupMessage(message),
        ),
      ),
    );
  }

  Future<void> openGroupFilePreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可打开的文件地址')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FilePreviewScreen(
          filename: _messageFilename(message),
          sizeBytes: _messageFileSize(message),
          onDownload: () => downloadGroupMessageFile(message),
          onForward: () => forwardGroupMessage(message),
        ),
      ),
    );
  }

  Future<void> openGroupVideoPreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可播放的视频地址')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPreviewScreen(
          url: url,
          title: _messageFilename(message),
          onDownload: () => downloadGroupMessageFile(message),
          onForward: () => forwardGroupMessage(message),
        ),
      ),
    );
  }

  Future<void> openGroupLink(Uri uri) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbeddedBrowserScreen(url: uri, title: uri.host),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sub?.cancel();
    screenshotSub?.cancel();
    groupProfileSub?.cancel();
    refreshTimer?.cancel();
    voiceTimer?.cancel();
    unawaited(recorder.dispose());
    input.removeListener(_handleGroupInputChanged);
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timelineItems();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
          children: [
            _GroupChatHeader(
              group: group,
              onBack: () => Navigator.pop(context),
              onOpenSettings: openGroupSettings,
              onMore: showGroupCallSheet,
            ),
            if (group.noticeEnabled &&
                group.noticePinned &&
                group.notice.trim().isNotEmpty)
              _GroupNoticeBanner(
                notice: group.notice.trim(),
                onTap: () => _showGroupNotice(group.notice.trim()),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        BlinStyle.pagePadding,
                        14,
                        BlinStyle.pagePadding,
                        18,
                      ),
                      itemCount: timeline.length,
                      itemBuilder: (_, index) {
                        final item = timeline[index];
                        if (item is _GroupTimelineDate) {
                          return _GroupDatePill(text: item.text);
                        }
                        if (item is _GroupTimelineSystem) {
                          return _GroupSystemPill(text: item.text);
                        }
                        if (item is _GroupTimelineNewDivider) {
                          return const _GroupNewMessageDivider();
                        }
                        final message = (item as _GroupTimelineMessage).message;
                        return _GroupMessageBubble(
                          message: message,
                          avatar: _avatarOf(message),
                          sender: _senderName(message),
                          time: _timeLabel(message.createTime),
                          groupCallEnded:
                              message.msgType == 'group_call_invite' &&
                              _isGroupCallFinished(message),
                          onPreviewImage: () => openGroupImagePreview(message),
                          onPreviewVideo: () => openGroupVideoPreview(message),
                          onDownloadFile: () => openGroupFilePreview(message),
                          onJoinGroupCall: _handleJoinGroupCall,
                          onStartGroupCall: (video) =>
                              unawaited(startGroupCall(video: video)),
                          onOpenLink: openGroupLink,
                          sendState:
                              groupMessageSendStates[_messageKey(message)],
                          onRetry: () =>
                              unawaited(retryFailedGroupMessage(message)),
                          onAction: showGroupMessageActions,
                        );
                      },
                    ),
            ),
            _GroupComposer(
              controller: input,
              focusNode: inputFocus,
              sending: sending,
              voiceEnabled: widget.voiceMessageEnabled,
              sendingVoice: sendingVoice,
              recordingVoice: recordingVoice,
              voiceDurationSeconds: voiceRecordingSeconds(voiceStartedAt),
              showEmojiPanel: showEmojiPanel,
              voiceInputMode: voiceInputMode,
              onSend: send,
              onEmoji: toggleEmojiPanel,
              onEmojiSelected: insertQuickEmoji,
              onImage: () => unawaited(sendGroupAttachment(mediaType: 'image')),
              onVideo: () => unawaited(sendGroupAttachment(mediaType: 'video')),
              onCapture: () => unawaited(captureGroupAttachment()),
              onFile: () => unawaited(sendGroupAttachment(mediaType: 'file')),
              onVoice: toggleVoiceInputMode,
              onVoicePressStart: () => unawaited(_startVoiceRecording()),
              onVoicePressEnd: () =>
                  unawaited(_finishVoiceRecording(send: true)),
              onVoicePressCancel: () =>
                  unawaited(_finishVoiceRecording(send: false)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupNoticeBanner extends StatelessWidget {
  final String notice;
  final VoidCallback onTap;
  const _GroupNoticeBanner({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: BlinStyle.surface(context),
    child: InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: BlinStyle.hairline(context).color),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.campaign_outlined,
              color: BlinStyle.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
          ],
        ),
      ),
    ),
  );
}

class _NoticeRichData {
  final String title;
  final String body;
  final String link;
  final bool important;
  const _NoticeRichData({
    required this.title,
    required this.body,
    required this.link,
    required this.important,
  });
}

_NoticeRichData _decodeNoticeRichText(String raw) {
  var source = raw.trim();
  if (source.startsWith('base64:')) {
    try {
      source = utf8.decode(base64Decode(source.substring(7)));
    } catch (_) {}
  }
  if (source.isEmpty) {
    return const _NoticeRichData(
      title: '',
      body: '',
      link: '',
      important: false,
    );
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) {
      return _NoticeRichData(
        title: '${decoded['title'] ?? ''}',
        body: '${decoded['body'] ?? decoded['content'] ?? ''}',
        link: '${decoded['link'] ?? decoded['url'] ?? ''}',
        important:
            decoded['important'] == true || '${decoded['important']}' == '1',
      );
    }
  } catch (_) {}
  return _NoticeRichData(title: '', body: source, link: '', important: false);
}

class _NoticeRichPreview extends StatelessWidget {
  final String text;
  final String richText;
  const _NoticeRichPreview({required this.text, required this.richText});

  @override
  Widget build(BuildContext context) {
    final data = _decodeNoticeRichText(richText);
    final title = data.title.trim();
    final body = data.body.trim().isEmpty ? text.trim() : data.body.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Row(
            children: [
              if (data.important) ...[
                const Icon(
                  Icons.priority_high_rounded,
                  color: BlinStyle.warning,
                  size: 18,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          body.isEmpty ? '暂无群公告' : body,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        if (data.link.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                size: 18,
                color: BlinStyle.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.link.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BlinStyle.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

sealed class _GroupTimelineItem {
  const _GroupTimelineItem();
}

class _GroupTimelineDate extends _GroupTimelineItem {
  final String text;
  const _GroupTimelineDate(this.text);
}

class _GroupTimelineSystem extends _GroupTimelineItem {
  final String text;
  const _GroupTimelineSystem(this.text);
}

class _GroupTimelineMessage extends _GroupTimelineItem {
  final UnifiedMessage message;
  const _GroupTimelineMessage(this.message);
}

class _GroupTimelineNewDivider extends _GroupTimelineItem {
  const _GroupTimelineNewDivider();
}

class _MentionSelection {
  final bool all;
  final ImGroupMember? member;
  const _MentionSelection._({required this.all, this.member});
  const _MentionSelection.all() : this._(all: true, member: null);
  const _MentionSelection.member(ImGroupMember member)
    : this._(all: false, member: member);
}

class _GroupChatHeader extends StatelessWidget {
  final ImGroup group;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final VoidCallback onMore;
  const _GroupChatHeader({
    required this.group,
    required this.onBack,
    required this.onOpenSettings,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15),
    decoration: BoxDecoration(color: BlinStyle.page(context)),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            TsddAssetIconButton(
              asset: 'assets/tsdd/common/ic_ab_back.png',
              onTap: onBack,
              tooltip: '返回',
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenSettings,
                child: Row(
                  children: [
                    AppAvatar(
                      imageUrl: group.avatar,
                      name: group.name,
                      size: 40,
                      fallbackIcon: Icons.groups_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.memberCount}个成员',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TsddAssetIconButton(
              asset: 'assets/tsdd/chat/icon_chat_toolbar_more.png',
              onTap: onMore,
              tooltip: '更多',
              color: BlinStyle.textPrimary(context),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupDatePill extends StatelessWidget {
  final String text;
  const _GroupDatePill({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BlinStyle.subtle,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
  );
}

class _GroupSystemPill extends StatelessWidget {
  final String text;
  const _GroupSystemPill({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .78,
      ),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: BlinStyle.muted,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
    ),
  );
}

class _GroupNewMessageDivider extends StatelessWidget {
  const _GroupNewMessageDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(child: Container(height: 1, color: BlinStyle.line)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '以下为新消息',
            style: TextStyle(
              color: BlinStyle.subtle,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: BlinStyle.line)),
      ],
    ),
  );
}

class _GroupMessageBubble extends StatelessWidget {
  final UnifiedMessage message;
  final String avatar;
  final String sender;
  final String time;
  final bool groupCallEnded;
  final VoidCallback? onPreviewImage;
  final VoidCallback? onPreviewVideo;
  final VoidCallback? onDownloadFile;
  final ValueChanged<UnifiedMessage>? onJoinGroupCall;
  final ValueChanged<bool>? onStartGroupCall;
  final ValueChanged<Uri>? onOpenLink;
  final String? sendState;
  final VoidCallback? onRetry;
  final ValueChanged<UnifiedMessage>? onAction;
  const _GroupMessageBubble({
    required this.message,
    required this.avatar,
    required this.sender,
    required this.time,
    required this.groupCallEnded,
    this.onPreviewImage,
    this.onPreviewVideo,
    this.onDownloadFile,
    this.onJoinGroupCall,
    this.onStartGroupCall,
    this.onOpenLink,
    this.sendState,
    this.onRetry,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (message.msgType == 'recall') {
      return _GroupSystemPill(text: '${message.content['text'] ?? '消息已撤回'}');
    }
    final me = message.isMe;
    final special = _specialContent();
    final isImage = message.msgType == 'image';
    final isVideo = message.msgType == 'video';
    final text = '${message.content['text'] ?? message.preview}';
    const contentColor = BlinStyle.ink;
    const metaColor = BlinStyle.subtle;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth:
            MediaQuery.sizeOf(context).width *
            (special == null ? (isImage ? .50 : .68) : .76),
      ),
      padding: special != null
          ? EdgeInsets.zero
          : (isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(14, 10, 14, 10)),
      decoration: BoxDecoration(
        color: me
            ? BlinStyle.primary.withValues(alpha: .11)
            : BlinStyle.surface(context),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(me ? 18 : 4),
          bottomRight: Radius.circular(me ? 4 : 18),
        ),
        border: Border.all(
          color: me
              ? BlinStyle.primary.withValues(alpha: .18)
              : BlinStyle.hairline(context, .62).color,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!me)
            Padding(
              padding: EdgeInsets.fromLTRB(
                special == null ? 0 : 12,
                special == null ? 0 : 9,
                special == null ? 0 : 12,
                5,
              ),
              child: Text(
                sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          if (special != null)
            special
          else if (message.msgType == 'voice')
            VoiceMessageBubble(message: message, me: me)
          else if (isImage)
            _GroupImageContent(message: message, onOpenLink: onOpenLink)
          else if (isVideo)
            _GroupVideoContent(
              message: message,
              onTap: onPreviewVideo,
              onOpenLink: onOpenLink,
            )
          else if (message.msgType == 'file')
            _GroupFileContent(message: message, onTap: onDownloadFile)
          else if (message.msgType == 'emoji')
            _MaybeGroupLinkText(
              text: text,
              style: TextStyle(
                color: contentColor,
                fontSize: text.runes.length <= 8 && text.trim().length <= 16
                    ? 34
                    : 14,
                height: text.runes.length <= 8 && text.trim().length <= 16
                    ? 1.1
                    : 1.35,
                fontWeight: FontWeight.w400,
              ),
              onOpenLink: onOpenLink,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: _MaybeGroupLinkText(
                    text: text,
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                    ),
                    onOpenLink: onOpenLink,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time,
                  style: TextStyle(
                    color: metaColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: sendState == 'failed'
          ? onRetry
          : isImage
          ? onPreviewImage
          : isVideo
          ? onPreviewVideo
          : null,
      onLongPress: onAction == null ? null : () => onAction!(message),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: me
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: me
              ? [
                  bubble,
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 2, top: 10),
                    child: _GroupSendStateIcon(state: sendState ?? 'success'),
                  ),
                  const SizedBox(width: 8),
                  _GroupAvatar(avatar: avatar, name: sender, size: 36),
                ]
              : [
                  _GroupAvatar(avatar: avatar, name: sender, size: 36),
                  const SizedBox(width: 8),
                  bubble,
                ],
        ),
      ),
    );
  }

  Widget? _specialContent() {
    final type = message.msgType.toLowerCase();
    if (type == 'group_call_invite') {
      return _GroupCallInviteCard(
        message: message,
        time: time,
        ended: groupCallEnded,
        onJoin: onJoinGroupCall == null
            ? null
            : () => onJoinGroupCall!(message),
      );
    }
    if (type == 'group_call_record') {
      return _GroupCallRecordCard(
        message: message,
        time: time,
        onStart: onStartGroupCall,
      );
    }
    return null;
  }
}

class _GroupSendStateIcon extends StatelessWidget {
  final String state;
  const _GroupSendStateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == 'pending') {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: BlinStyle.subtle,
        ),
      );
    }
    if (state == 'failed') {
      return const Icon(
        Icons.error_outline_rounded,
        color: BlinStyle.danger,
        size: 15,
      );
    }
    return const Icon(Icons.check_rounded, color: BlinStyle.subtle, size: 14);
  }
}

class _GroupImageContent extends StatelessWidget {
  final UnifiedMessage message;
  final ValueChanged<Uri>? onOpenLink;
  const _GroupImageContent({required this.message, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final url = firstMediaUrl([
      message.content['url'],
      message.content['file_url'],
      message.content['image_path'],
      message.content['path'],
      message.content['src'],
    ]);
    final text = '${message.content['text'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isNotEmpty) _GroupImagePreview(url: url),
        if (text.isNotEmpty && text != '[图片]') ...[
          const SizedBox(height: 6),
          _MaybeGroupLinkText(
            text: text,
            style: TextStyle(
              color: BlinStyle.ink,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            onOpenLink: onOpenLink,
          ),
        ],
      ],
    );
  }
}

class _MaybeGroupLinkText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final ValueChanged<Uri>? onOpenLink;

  const _MaybeGroupLinkText({
    required this.text,
    required this.style,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    if (onOpenLink == null) return Text(text, style: style);
    return LinkText(text: text, style: style, onOpenLink: onOpenLink!);
  }
}

class _GroupImagePreview extends StatelessWidget {
  final String url;
  const _GroupImagePreview({required this.url});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 170,
        maxHeight: 190,
        minWidth: 96,
        minHeight: 96,
      ),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return Container(
            width: 150,
            height: 150,
            color: BlinStyle.softFill,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          width: 150,
          height: 150,
          color: BlinStyle.softFill,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    ),
  );
}

class _GroupVideoContent extends StatelessWidget {
  final UnifiedMessage message;
  final VoidCallback? onTap;
  final ValueChanged<Uri>? onOpenLink;

  const _GroupVideoContent({
    required this.message,
    required this.onTap,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final rawName = '${message.content['name'] ?? '视频'}';
    final name = rawName.startsWith('[视频]')
        ? rawName.replaceFirst('[视频]', '').trim()
        : rawName;
    final url = firstMediaUrl([
      message.content['url'],
      message.content['file_url'],
      message.content['video_url'],
      message.content['video_path'],
      message.content['file_path'],
    ]);
    final text = '${message.content['text'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: url.isEmpty ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: _GroupVideoCover(url: url),
        ),
        if (name.isNotEmpty && name != '视频') ...[
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BlinStyle.subtle,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (text.isNotEmpty && text != '[视频]' && text != '[视频] $name') ...[
          const SizedBox(height: 6),
          _MaybeGroupLinkText(
            text: text,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            onOpenLink: onOpenLink,
          ),
        ],
      ],
    );
  }
}

class _GroupVideoCover extends StatefulWidget {
  final String url;
  const _GroupVideoCover({required this.url});

  @override
  State<_GroupVideoCover> createState() => _GroupVideoCoverState();
}

class _GroupVideoCoverState extends State<_GroupVideoCover> {
  VideoPlayerController? controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.url.isEmpty) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller = c;
    c
        .initialize()
        .then((_) {
          if (!mounted) return;
          c.pause();
          c.seekTo(Duration.zero);
          setState(() => ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: 220,
      height: 124,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ready && controller != null
                ? VideoPlayer(controller!)
                : Container(color: Colors.black.withValues(alpha: .16)),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .42),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ],
      ),
    ),
  );
}

class _GroupFileContent extends StatelessWidget {
  final UnifiedMessage message;
  final VoidCallback? onTap;
  const _GroupFileContent({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final me = message.isMe;
    final name =
        '${message.content['name'] ?? message.content['file_name'] ?? '文件'}';
    final size = int.tryParse('${message.content['size'] ?? 0}') ?? 0;
    final sizeText = size > 0 ? _formatSize(size) : '点击下载';
    const color = BlinStyle.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (me ? Colors.white : BlinStyle.primary).withValues(
                  alpha: me ? .18 : .12,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.insert_drive_file_outlined,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    sizeText,
                    style: const TextStyle(
                      color: BlinStyle.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int size) {
    if (size >= 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }
}

class _GroupCallInviteCard extends StatelessWidget {
  final UnifiedMessage message;
  final String time;
  final bool ended;
  final VoidCallback? onJoin;
  const _GroupCallInviteCard({
    required this.message,
    required this.time,
    required this.ended,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final video = '${message.content['media']}'.contains('video');
    final starter =
        '${message.content['starter_nickname'] ?? message.content['nickname'] ?? (message.isMe ? '我' : '群成员')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BlinStyle.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
                  border: Border.all(
                    color: BlinStyle.primary.withValues(alpha: .18),
                  ),
                ),
                child: Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  color: BlinStyle.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '群${video ? '视频' : '语音'}通话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$starter 发起了群通话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                time,
                style: const TextStyle(
                  color: BlinStyle.subtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (!ended)
                FilledButton.icon(
                  onPressed: onJoin,
                  icon: Icon(
                    video ? Icons.video_call_rounded : Icons.call_rounded,
                    size: 17,
                  ),
                  label: Text(message.isMe ? '进入' : '加入'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BlinStyle.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(76, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        BlinStyle.buttonRadius,
                      ),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: BlinStyle.page(context),
                    borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
                    border: Border.all(
                      color: BlinStyle.hairline(context).color,
                    ),
                  ),
                  child: const Text(
                    '已结束',
                    style: TextStyle(
                      color: BlinStyle.subtle,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupCallRecordCard extends StatelessWidget {
  final UnifiedMessage message;
  final String time;
  final ValueChanged<bool>? onStart;
  const _GroupCallRecordCard({
    required this.message,
    required this.time,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final video = '${message.content['media']}'.contains('video');
    final status = '${message.content['status']}';
    final text = _statusText(
      status,
      int.tryParse('${message.content['duration'] ?? 0}') ?? 0,
    );
    return InkWell(
      onTap: onStart == null ? null : () => onStart!(video),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              video ? Icons.videocam_rounded : Icons.call_rounded,
              color: BlinStyle.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '群${video ? '视频' : '语音'}通话 $text',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onStart != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.refresh_rounded,
                color: BlinStyle.subtle,
                size: 16,
              ),
            ],
            const SizedBox(width: 8),
            Text(
              time,
              style: const TextStyle(
                color: BlinStyle.subtle,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(String status, int duration) {
    if (status == 'finished') return _formatDuration(duration);
    if (status == 'failed') return '连接失败';
    if (status == 'busy') return '忙线';
    if (status == 'missed') return '未接听';
    if (status == 'rejected') return '已拒绝';
    return '已取消';
  }

  static String _formatDuration(int total) {
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
}

class _GroupCallRoomResult {
  final String roomId;
  final bool video;
  final String status;
  final int durationSeconds;
  final int inviterId;
  final String inviterName;
  final List<int> participantIds;
  final DateTime endedAt;

  const _GroupCallRoomResult({
    required this.roomId,
    required this.video,
    required this.status,
    required this.durationSeconds,
    required this.inviterId,
    required this.inviterName,
    required this.participantIds,
    required this.endedAt,
  });
}

class _GroupCallRoomScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final ApiService api;
  final ImGroup group;
  final List<ImGroupMember> members;
  final String roomId;
  final bool video;
  final int inviterId;
  final String inviterName;

  const _GroupCallRoomScreen({
    required this.session,
    required this.im,
    required this.api,
    required this.group,
    required this.members,
    required this.roomId,
    required this.video,
    required this.inviterId,
    required this.inviterName,
  });

  @override
  State<_GroupCallRoomScreen> createState() => _GroupCallRoomScreenState();
}

class _GroupCallRoomScreenState extends State<_GroupCallRoomScreen> {
  final CallMediaEngine previewMedia = CallMediaEngine();
  final Map<int, _GroupPeerSession> peers = <int, _GroupPeerSession>{};
  final Set<int> joinedUserIds = <int>{};
  final Set<String> seenRoomEvents = <String>{};
  StreamSubscription? messageSub;
  Timer? roomRefreshTimer;
  MediaStream? sharedStream;
  List<Map<String, dynamic>> groupIceServers = AppConfig.rtcIceServers;
  DateTime enteredAt = DateTime.now();
  DateTime? connectedAt;
  bool starting = true;
  bool closing = false;
  bool guardEntered = false;
  bool previewDisposed = false;
  bool roomEnded = false;
  String error = '';

  String get mediaText => widget.video ? '视频' : '语音';
  String get routeGuardKey => 'group:${widget.roomId}';

  @override
  void initState() {
    super.initState();
    unawaited(_startRoom());
  }

  Future<void> _startRoom() async {
    if (!CallRouteGuard.tryEnter(routeGuardKey)) {
      if (mounted) {
        setState(() {
          starting = false;
          error = '当前已有通话正在进行';
        });
      }
      return;
    }
    guardEntered = true;
    messageSub = widget.im.messages.listen(_handleRealtimeMessage);
    roomRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !closing) unawaited(_loadRoomEvents());
    });
    try {
      await _loadIceServers();
      if (await _loadRoomEvents()) {
        await _exitEndedRoom();
        return;
      }
      await previewMedia.openLocalMedia(video: widget.video);
      sharedStream = previewMedia.localStream;
      joinedUserIds.add(widget.session.id);
      if (widget.inviterId > 0 && widget.inviterId != widget.session.id) {
        joinedUserIds.add(widget.inviterId);
      }
      if (await _loadRoomEvents()) {
        await _exitEndedRoom();
        return;
      }
      await _sendRoomEvent('group_call_join', status: 'joined');
      await _connectToJoinedPeers();
      if (mounted) setState(() => starting = false);
    } catch (e, st) {
      AppLogger.error(
        'CALL',
        '群通话房间启动失败 room=${widget.roomId}',
        error: e,
        stack: st,
      );
      if (mounted) {
        setState(() {
          starting = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> _loadIceServers() async {
    try {
      final servers = await widget.api
          .getIceServers(widget.session.token)
          .timeout(const Duration(seconds: 3));
      if (servers.isNotEmpty) groupIceServers = servers;
      AppLogger.call(
        '群通话ICE服务器 count=${groupIceServers.length} room=${widget.roomId}',
      );
    } catch (e) {
      groupIceServers = AppConfig.rtcIceServers;
      AppLogger.warn(
        'CALL',
        '群通话ICE服务器获取超时，使用内置配置 room=${widget.roomId}',
        data: e,
      );
    }
  }

  Future<bool> _loadRoomEvents() async {
    try {
      final list = await widget.api.getGroupChatLog(
        token: widget.session.token,
        groupId: widget.group.id,
        myId: widget.session.id,
        limit: 100,
      );
      var ended = false;
      for (final message in list) {
        ended = _handleRoomMessage(message) || ended;
      }
      if (ended) {
        return true;
      }
      await _connectToJoinedPeers();
    } catch (e) {
      AppLogger.warn('CALL', '群通话房间事件拉取失败 room=${widget.roomId}', data: e);
    }
    return roomEnded;
  }

  void _handleRealtimeMessage(UnifiedMessage message) {
    if (closing || roomEnded) return;
    if (message.raw['group_id'] != null &&
        '${message.raw['group_id']}' != '${widget.group.id}') {
      return;
    }
    if (message.toUid.isNotEmpty && message.toUid != widget.group.groupNo) {
      return;
    }
    if (_handleRoomMessage(message)) {
      unawaited(_exitEndedRoom());
      return;
    }
    unawaited(_connectToJoinedPeers());
  }

  bool _handleRoomMessage(UnifiedMessage message) {
    if (closing || roomEnded) return roomEnded;
    final roomId = _groupCallRoomIdOf(message);
    if (roomId != widget.roomId) return false;
    final key =
        '${message.raw['client_msg_no'] ?? message.messageId}_${message.msgType}_${message.fromUserId}_${message.createTime.millisecondsSinceEpoch}';
    if (!seenRoomEvents.add(key)) return roomEnded;
    final type = message.msgType.toLowerCase();
    if (_isGroupCallEndMessage(
      message,
      roomId: widget.roomId,
      inviterId: widget.inviterId,
    )) {
      roomEnded = true;
      error = '群通话已结束';
      if (mounted) setState(() {});
      return true;
    }
    final userId = _groupCallActorIdOf(message);
    if (type == 'group_call_join') {
      if (userId > 0 && userId != widget.session.id) {
        joinedUserIds.add(userId);
      }
    } else if (type == 'group_call_leave') {
      if (userId > 0 && userId != widget.session.id) {
        joinedUserIds.remove(userId);
        unawaited(_removePeer(userId));
      }
    }
    if (mounted) setState(() {});
    return false;
  }

  Future<void> _connectToJoinedPeers() async {
    if (sharedStream == null || closing) return;
    final ids =
        joinedUserIds.where((id) => id > 0 && id != widget.session.id).toList()
          ..sort();
    for (final userId in ids) {
      final member = _memberFor(userId);
      if (member != null) await _ensurePeer(member);
    }
  }

  ImGroupMember? _memberFor(int userId) {
    for (final member in widget.members) {
      if (member.userId == userId) return member;
    }
    if (userId == widget.inviterId) {
      return ImGroupMember(
        userId: userId,
        nickname: widget.inviterName,
        avatar: '',
      );
    }
    if (userId > 0) {
      return ImGroupMember(userId: userId, nickname: '用户$userId', avatar: '');
    }
    return null;
  }

  Future<void> _ensurePeer(ImGroupMember member) async {
    if (member.userId <= 0 ||
        member.userId == widget.session.id ||
        peers.containsKey(member.userId) ||
        sharedStream == null) {
      return;
    }
    final selfId = widget.session.id;
    final peerId = member.userId;
    final low = selfId < peerId ? selfId : peerId;
    final high = selfId < peerId ? peerId : selfId;
    final incoming = selfId > peerId;
    final callId = '${widget.roomId}_p2p_${low}_$high';
    final media = CallMediaEngine()..iceServers = groupIceServers;
    final signaling = CallSignalingAdapter(
      api: widget.api,
      im: widget.im,
      token: widget.session.token,
      selfId: selfId,
      peerId: peerId,
      extraContent: {
        'group_call_internal': true,
        'group_call_room_id': widget.roomId,
        'group_call_id': widget.roomId,
        'group_id': widget.group.id,
        'group_no': widget.group.groupNo,
        'nickname': widget.session.nickname ?? widget.session.username,
        'avatar': widget.session.avatar,
      },
    );
    final controller = CallSessionController(
      media: media,
      signaling: signaling,
      callId: callId,
      video: widget.video,
      incoming: incoming,
      sharedLocalStream: sharedStream,
      autoAccept: incoming,
    );
    final peer = _GroupPeerSession(
      member: member,
      media: media,
      controller: controller,
    );
    peers[peerId] = peer;
    peer.sub = controller.states.listen((state) {
      peer.state = state;
      if (state == CallFlowState.connected) connectedAt ??= DateTime.now();
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
    try {
      await controller.start();
    } catch (e, st) {
      AppLogger.error(
        'CALL',
        '群通话成员连接失败 room=${widget.roomId} peer=$peerId',
        error: e,
        stack: st,
      );
      peer.state = CallFlowState.failed;
      if (mounted) setState(() {});
    }
  }

  Future<void> _removePeer(int userId) async {
    final peer = peers.remove(userId);
    if (peer == null) return;
    await peer.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _sendRoomEvent(String type, {required String status}) async {
    if (roomEnded) return;
    final now = DateTime.now();
    final userName = widget.session.nickname ?? widget.session.username;
    final payload = {
      'msg_type': type,
      'client_msg_no':
          '${widget.roomId}_${widget.session.id}_${now.microsecondsSinceEpoch}_$status',
      'from_user_id': widget.session.id,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': widget.group.groupNo,
      'group_id': widget.group.id,
      'group_no': widget.group.groupNo,
      'nickname': userName,
      'avatar': widget.session.avatar,
      'device': 'Android',
      'content': {
        'room_id': widget.roomId,
        'call_id': widget.roomId,
        'media': widget.video ? 'video' : 'audio',
        'status': status,
        'user_id': widget.session.id,
        'nickname': userName,
        'avatar': widget.session.avatar,
        'device': 'Android',
      },
      'create_time': now.toIso8601String(),
      'timestamp': now.millisecondsSinceEpoch,
    };
    final actionText = status == 'joined' ? '加入' : '离开';
    try {
      await widget.api.sendGroupMessage(
        token: widget.session.token,
        groupId: widget.group.id,
        content: '$userName $actionText了群$mediaText通话',
        payload: payload,
      );
    } catch (e) {
      AppLogger.warn('CALL', '群通话房间事件发送失败 room=${widget.roomId}', data: e);
    }
  }

  void _toggleMic() {
    previewMedia.toggleMic();
    setState(() {});
  }

  void _toggleCamera() {
    previewMedia.toggleCamera();
    setState(() {});
  }

  Future<void> _switchCamera() => previewMedia.switchCamera();

  Future<void> _leave({String? forcedStatus}) async {
    if (closing) return;
    closing = true;
    final status = forcedStatus ?? _resultStatus();
    await _sendRoomEvent('group_call_leave', status: 'left');
    for (final peer in peers.values.toList()) {
      try {
        await peer.controller.hangup();
      } catch (_) {}
      await peer.dispose();
    }
    peers.clear();
    await previewMedia.dispose();
    previewDisposed = true;
    if (guardEntered) {
      CallRouteGuard.exit(routeGuardKey);
      guardEntered = false;
    }
    final now = DateTime.now();
    final started = connectedAt ?? enteredAt;
    final duration = status == 'finished'
        ? now.difference(started).inSeconds.clamp(0, 24 * 60 * 60).toInt()
        : 0;
    if (!mounted) return;
    Navigator.pop(
      context,
      _GroupCallRoomResult(
        roomId: widget.roomId,
        video: widget.video,
        status: status,
        durationSeconds: duration,
        inviterId: widget.inviterId,
        inviterName: widget.inviterName,
        participantIds: joinedUserIds.toList()..sort(),
        endedAt: now,
      ),
    );
  }

  Future<void> _exitEndedRoom() async {
    if (closing) return;
    closing = true;
    roomEnded = true;
    roomRefreshTimer?.cancel();
    for (final peer in peers.values.toList()) {
      try {
        await peer.controller.hangup();
      } catch (_) {}
      await peer.dispose();
    }
    peers.clear();
    await previewMedia.dispose();
    previewDisposed = true;
    if (guardEntered) {
      CallRouteGuard.exit(routeGuardKey);
      guardEntered = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('群通话已结束')));
    Navigator.pop(context);
  }

  String _resultStatus() {
    if (roomEnded) return 'canceled';
    if (error.isNotEmpty) return 'failed';
    if (connectedAt != null || peers.values.any((peer) => peer.connected)) {
      return 'finished';
    }
    return 'canceled';
  }

  @override
  void dispose() {
    messageSub?.cancel();
    roomRefreshTimer?.cancel();
    for (final peer in peers.values.toList()) {
      unawaited(peer.dispose());
    }
    peers.clear();
    if (!previewDisposed) unawaited(previewMedia.dispose());
    if (guardEntered) {
      CallRouteGuard.exit(routeGuardKey);
      guardEntered = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: () async {
      await _leave();
      return false;
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildStage()),
            _buildStatusLine(),
            _buildControls(),
          ],
        ),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => unawaited(_leave()),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          color: Colors.white,
          style: IconButton.styleFrom(backgroundColor: Colors.white12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.group.name} 群$mediaText通话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _roomStateText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xBFFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildStage() {
    if (starting) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      );
    }
    if (!widget.video) return _buildAudioStage();
    final connectedPeers = peers.values.toList()
      ..sort((a, b) => a.member.userId.compareTo(b.member.userId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: GridView.builder(
        itemCount: connectedPeers.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .78,
        ),
        itemBuilder: (_, index) {
          if (index == 0) return _localVideoTile();
          return _remoteVideoTile(connectedPeers[index - 1]);
        },
      ),
    );
  }

  Widget _buildAudioStage() {
    final activeMembers = <ImGroupMember>[
      ImGroupMember(
        userId: widget.session.id,
        nickname: widget.session.nickname ?? '我',
        avatar: widget.session.avatar,
      ),
      for (final peer in peers.values) peer.member,
    ];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
      itemCount: activeMembers.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 22,
        crossAxisSpacing: 16,
        childAspectRatio: .76,
      ),
      itemBuilder: (_, index) {
        final member = activeMembers[index];
        final peer = peers[member.userId];
        final connected =
            member.userId == widget.session.id || peer?.connected == true;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                _GroupAvatar(
                  avatar: member.avatar,
                  name: member.nickname,
                  size: 68,
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: connected
                        ? BlinStyle.green
                        : const Color(0xFF6B7280),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF101418),
                      width: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              member.userId == widget.session.id ? '我' : member.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              connected ? '已连接' : '连接中',
              style: const TextStyle(
                color: Color(0xBFFFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _localVideoTile() => _VideoTile(
    name: '我',
    child: RTCVideoView(
      previewMedia.localRenderer,
      mirror: true,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    ),
    connected: true,
  );

  Widget _remoteVideoTile(_GroupPeerSession peer) => _VideoTile(
    name: peer.member.nickname,
    connected: peer.connected,
    child: peer.connected
        ? RTCVideoView(
            peer.media.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GroupAvatar(
                  avatar: peer.member.avatar,
                  name: peer.member.nickname,
                  size: 62,
                ),
                const SizedBox(height: 10),
                const Text(
                  '连接中',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _buildStatusLine() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    child: Text(
      _roomStateText(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xBFFFFFFF),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _roomStateText() {
    if (roomEnded) return '群通话已结束';
    if (error.isNotEmpty) return '启动失败';
    if (starting) return '正在打开本地媒体';
    final connected = peers.values.where((peer) => peer.connected).length;
    if (connected > 0) return '$connected 人已连接';
    if (joinedUserIds.length > 1) return '正在连接群成员';
    return '等待群成员加入';
  }

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _GroupCallControlButton(
          icon: previewMedia.micEnabled
              ? Icons.mic_rounded
              : Icons.mic_off_rounded,
          color: Colors.white24,
          label: '麦克风',
          onTap: starting ? null : _toggleMic,
        ),
        if (widget.video)
          _GroupCallControlButton(
            icon: Icons.cameraswitch_rounded,
            color: Colors.white24,
            label: '翻转',
            onTap: starting ? null : () => unawaited(_switchCamera()),
          ),
        if (widget.video)
          _GroupCallControlButton(
            icon: previewMedia.cameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            color: Colors.white24,
            label: '摄像头',
            onTap: starting ? null : _toggleCamera,
          ),
        _GroupCallControlButton(
          icon: Icons.call_end_rounded,
          color: Colors.redAccent,
          label: '挂断',
          onTap: () => unawaited(_leave()),
        ),
      ],
    ),
  );
}

class _GroupPeerSession {
  final ImGroupMember member;
  final CallMediaEngine media;
  final CallSessionController controller;
  StreamSubscription? sub;
  CallFlowState state;

  _GroupPeerSession({
    required this.member,
    required this.media,
    required this.controller,
  }) : state = controller.state;

  bool get connected => state == CallFlowState.connected;

  Future<void> dispose() async {
    await sub?.cancel();
    await controller.dispose();
  }
}

class _VideoTile extends StatelessWidget {
  final String name;
  final Widget child;
  final bool connected;
  const _VideoTile({
    required this.name,
    required this.child,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF1F2937), child: child),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: connected ? BlinStyle.green : const Color(0xFF9CA3AF),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GroupCallControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _GroupCallControlButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(31),
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: onTap == null ? Colors.white10 : color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _GroupAvatar extends StatelessWidget {
  final String avatar;
  final String name;
  final double size;
  const _GroupAvatar({
    required this.avatar,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) =>
      AppAvatar(imageUrl: avatar, name: name, size: size);
}

class _GroupComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool voiceEnabled;
  final bool sendingVoice;
  final bool recordingVoice;
  final int voiceDurationSeconds;
  final bool showEmojiPanel;
  final bool voiceInputMode;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onCapture;
  final VoidCallback onFile;
  final VoidCallback onVoice;
  final VoidCallback onVoicePressStart;
  final VoidCallback onVoicePressEnd;
  final VoidCallback onVoicePressCancel;
  const _GroupComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.voiceEnabled,
    required this.sendingVoice,
    required this.recordingVoice,
    required this.voiceDurationSeconds,
    required this.showEmojiPanel,
    required this.voiceInputMode,
    required this.onSend,
    required this.onEmoji,
    required this.onEmojiSelected,
    required this.onImage,
    required this.onVideo,
    required this.onCapture,
    required this.onFile,
    required this.onVoice,
    required this.onVoicePressStart,
    required this.onVoicePressEnd,
    required this.onVoicePressCancel,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BlinStyle.cardShadow],
        border: Border.all(color: BlinStyle.hairline(context, .58).color),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recordingVoice) VoiceRecordingBar(seconds: voiceDurationSeconds),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (voiceEnabled) ...[
                _GroupInputModeButton(
                  icon: voiceInputMode
                      ? Icons.keyboard_alt_outlined
                      : Icons.keyboard_voice_outlined,
                  active: voiceInputMode,
                  onTap: sending || sendingVoice ? null : onVoice,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: voiceInputMode
                    ? _GroupVoiceHoldButton(
                        recording: recordingVoice,
                        sending: sendingVoice,
                        onStart: onVoicePressStart,
                        onEnd: onVoicePressEnd,
                        onCancel: onVoicePressCancel,
                      )
                    : Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: BlinStyle.softFill,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => onSend(),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '输入消息',
                            hintStyle: TextStyle(color: BlinStyle.subtle),
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: BlinStyle.textPrimary(context),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 35,
                height: 35,
                child: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BlinStyle.primary,
                        ),
                      )
                    : TsddAssetIconButton(
                        asset: 'assets/tsdd/chat/icon_chat_send.png',
                        onTap: onSend,
                        tooltip: '发送',
                        size: 40,
                        iconSize: 25,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ComposerAction(
                  icon: Icons.mood_outlined,
                  label: '表情',
                  onTap: onEmoji,
                ),
                _ComposerAction(
                  icon: Icons.photo_outlined,
                  label: '图片',
                  onTap: onImage,
                ),
                _ComposerAction(
                  icon: Icons.video_library_outlined,
                  label: '视频',
                  onTap: sending ? null : onVideo,
                ),
                _ComposerAction(
                  icon: Icons.photo_camera_outlined,
                  label: '拍摄',
                  onTap: sending ? null : onCapture,
                ),
                _ComposerAction(
                  icon: Icons.attach_file_rounded,
                  label: '文件',
                  onTap: onFile,
                ),
              ],
            ),
          ),
          if (showEmojiPanel) _GroupInlineEmojiPanel(onEmoji: onEmojiSelected),
        ],
      ),
    ),
  );
}

class _GroupInlineEmojiPanel extends StatelessWidget {
  final ValueChanged<String> onEmoji;
  const _GroupInlineEmojiPanel({required this.onEmoji});

  static const emojis = [
    '😀',
    '😂',
    '😊',
    '😍',
    '🥰',
    '😭',
    '😎',
    '👍',
    '👏',
    '🙏',
    '🎉',
    '🔥',
    '❤️',
    '💪',
    '🤔',
    '😅',
    '😡',
    '😴',
    '😋',
    '👌',
    '🌹',
    '🍻',
    '✨',
    '💯',
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: 146,
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    decoration: BoxDecoration(
      color: BlinStyle.bg,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BlinStyle.hairline(context, .45).color),
    ),
    child: GridView.builder(
      itemCount: emojis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, i) => InkWell(
        onTap: () => onEmoji(emojis[i]),
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
        ),
      ),
    ),
  );
}

class _ComposerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ComposerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: BlinStyle.iconSurface(context),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: BlinStyle.textPrimary(context),
                size: 20,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: BlinStyle.muted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupInputModeButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _GroupInputModeButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: active ? '切换输入' : '语音输入',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          color: active
              ? BlinStyle.primary.withValues(alpha: .10)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: active ? BlinStyle.primary : BlinStyle.textPrimary(context),
        ),
      ),
    ),
  );
}

class _GroupVoiceHoldButton extends StatelessWidget {
  final bool recording;
  final bool sending;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  const _GroupVoiceHoldButton({
    required this.recording,
    required this.sending,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final label = recording
        ? '松开 结束'
        : sending
        ? '准备中...'
        : '按住 说话';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => onStart(),
      onLongPressEnd: (_) => onEnd(),
      onLongPressCancel: onCancel,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BlinStyle.iconSurface(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: recording
                ? BlinStyle.primary
                : BlinStyle.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
