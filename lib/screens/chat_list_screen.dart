import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:record/record.dart';
import '../calls/call_media_engine.dart';
import '../calls/call_session.dart';
import '../calls/call_signaling_adapter.dart';
import '../core/app_logger.dart';
import '../models/call_signal.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/conversation_preferences.dart';
import '../services/file_download/file_downloader.dart';
import '../services/group_profile_events.dart';
import '../services/im_service.dart';
import '../services/screenshot_monitor.dart';
import '../widgets/blin_style.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'group_settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final bool voiceMessageEnabled;
  final bool screenshotNoticeEnabled;
  final ValueChanged<int>? onUnreadChanged;
  const ChatListScreen({
    super.key,
    required this.session,
    required this.im,
    this.voiceMessageEnabled = true,
    this.screenshotNoticeEnabled = false,
    this.onUnreadChanged,
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
  Set<int> savedGroupIds = {};
  Map<int, String> groupRemarks = {};
  bool showUserId = false;
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
      if (mounted) setState(() => showUserId = config.showUserId);
    } catch (_) {}
  }

  String userSubtitle(UserSearchResult user) =>
      showUserId ? 'ID: ${user.id}  @${user.username}' : '@${user.username}';

  String groupSubtitle(ImGroup group) {
    final count = '${group.memberCount}人';
    if (!showUserId) return count;
    final no = group.groupNo.isEmpty ? '${group.id}' : group.groupNo;
    return '$count · 群号 $no';
  }

  bool _isHiddenRealtimeGroupCallEvent(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    return type == 'group_call_join' || type == 'group_call_leave';
  }

  Future<void> _loadPinnedConversations() async {
    final saved = await ConversationPreferences.loadPinned(widget.session.id);
    if (!mounted) return;
    setState(() {
      pinnedConversationKeys = saved;
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
    return _sortedConversations(result);
  }

  Future<_UnifiedConversation> _groupConversation(
    ImGroup group, {
    required int order,
  }) async {
    var preview = showUserId
        ? '${group.memberCount}人 · 群号 ${group.groupNo}'
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
          .where((item) => !locallyDeletedFriendIds.contains(item.userId))
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
    final avatar = '${content['avatar'] ?? ''}';
    final message = '${content['message'] ?? '请求添加你为好友'}';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('好友申请'),
        content: Row(
          children: [
            CircleAvatar(
              backgroundImage: avatar.isNotEmpty
                  ? CachedNetworkImageProvider(avatar)
                  : null,
              child: avatar.isEmpty ? Text(name.characters.first) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('$name\n$message')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('通过'),
          ),
        ],
      ),
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

  void openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FriendsScreen(
          friends: friends,
          showUserId: showUserId,
          onOpen: (u) => openChat(u.id, u.nickname, u.avatar),
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
    final nameController = TextEditingController();
    final selected = <int>{};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建群聊'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: '群名称',
                    hintText: fallbackName,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'name': nameController.text.trim(),
                'members': selected.toList(),
              }),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
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

  void openSystemNotifications() {
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
    final selected = await Navigator.push<UserSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserScreen(
          session: widget.session,
          initialKeyword: search.text,
          showUserId: showUserId,
          onAddFriend: addFriend,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await openChat(selected.id, selected.nickname, selected.avatar);
  }

  Future<void> manualOpenDialog() async {
    final c = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('搜索用户名'),
        content: TextField(
          controller: c,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '例如：abcd12',
            labelText: '用户名',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    c.dispose();
    if (keyword == null || keyword.trim().isEmpty) return;
    search.text = keyword.trim();
    await showSearchDialog();
  }

  Future<void> showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BlinStyle.surface(context),
      showDragHandle: false,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.person_add_alt_1_outlined,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '添加联系人',
              subtitle: '按用户名搜索',
              minHeight: 64,
              onTap: () => Navigator.pop(context, 'user'),
            ),
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.groups_outlined,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '创建群聊',
              subtitle: '选择好友发起群聊',
              minHeight: 64,
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'user') {
      await manualOpenDialog();
    } else if (action == 'group') {
      await createGroup();
    }
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
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '消息',
            subtitle: widget.im.connected
                ? '实时消息已连接'
                : (widget.im.connecting ? '正在连接消息服务' : '消息服务离线，正在重试'),
            actions: [
              TsddAssetIconButton(
                asset: 'assets/tsdd/common/ic_ab_search.png',
                onTap: showSearchDialog,
                tooltip: '搜索',
              ),
              TsddAssetIconButton(
                asset: 'assets/tsdd/common/msg_add.png',
                onTap: showCreateMenu,
                tooltip: '新建',
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
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
  Set<int> savedGroupIds = {};
  Map<int, String> groupRemarks = {};
  bool showUserId = false;
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
      if (mounted) setState(() => showUserId = config.showUserId);
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

  Future<void> showSearchDialog() async {
    final selected = await Navigator.push<UserSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserScreen(
          session: widget.session,
          showUserId: showUserId,
          onAddFriend: addFriend,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await openChat(selected);
  }

  Future<void> manualOpenDialog() async {
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('搜索用户名'),
        content: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '用户名',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (keyword == null || keyword.trim().isEmpty) return;
    if (!mounted) return;
    final selected = await Navigator.push<UserSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchUserScreen(
          session: widget.session,
          initialKeyword: keyword.trim(),
          showUserId: showUserId,
          onAddFriend: addFriend,
        ),
      ),
    );
    if (selected != null && mounted) await openChat(selected);
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
    final nameController = TextEditingController();
    final selected = <int>{};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建群聊'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: '群名称',
                    hintText: fallbackName,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'name': nameController.text.trim(),
                'members': selected.toList(),
              }),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
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
              TsddAssetIconButton(
                asset: 'assets/tsdd/common/ic_ab_search.png',
                onTap: showSearchDialog,
                tooltip: '搜索用户',
              ),
              TsddAssetIconButton(
                asset: 'assets/tsdd/common/msg_add.png',
                onTap: createGroup,
                tooltip: '创建群聊',
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                  _ContactActionTile(
                    icon: Icons.tag_outlined,
                    title: '搜索用户名',
                    subtitle: '按用户名添加联系人或进入私聊',
                    onTap: manualOpenDialog,
                  ),
                  if (momentsConfig.enabled)
                    _ContactActionTile(
                      icon: Icons.auto_graph_outlined,
                      title: '朋友圈',
                      subtitle: momentsConfig.visibilityLabel,
                      onTap: openMoments,
                    ),
                  const _SectionTitle('好友'),
                  if (loading)
                    const SizedBox.shrink()
                  else if (friends.isEmpty)
                    _ContactEmptyTile(
                      icon: Icons.person_search_outlined,
                      text: '暂无好友，可以搜索账号添加联系人。',
                      onTap: showSearchDialog,
                    )
                  else
                    ...friends.map(
                      (user) => _ChatTile(
                        onTap: () => openChat(user),
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

class _MyGroupsScreen extends StatefulWidget {
  final List<ImGroup> groups;
  final bool loading;
  final bool showUserId;
  final String Function(ImGroup) displayNameFor;
  final Future<List<ImGroup>> Function() onRefresh;
  final ValueChanged<ImGroup> onOpenGroup;
  final VoidCallback onCreateGroup;

  const _MyGroupsScreen({
    required this.groups,
    required this.loading,
    required this.showUserId,
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
    if (!widget.showUserId) return count;
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
            child: RefreshIndicator(
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
            child: RefreshIndicator(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除记录'),
        content: Text('删除 ${item.nickname} 的好友申请记录？'),
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
    if (confirmed != true) return;
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
            child: RefreshIndicator(
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
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
          boxShadow: [BlinStyle.softShadow(.22)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: BlinStyle.primary,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.white, size: 25),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            time,
                            style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              content,
              style: const TextStyle(
                color: Color(0xFF314056),
                fontSize: 15,
                height: 1.55,
                fontWeight: FontWeight.w800,
              ),
            ),
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

class _SearchUserScreen extends StatefulWidget {
  final UserSession session;
  final String initialKeyword;
  final bool showUserId;
  final Future<void> Function(UserSearchResult user) onAddFriend;

  const _SearchUserScreen({
    required this.session,
    required this.onAddFriend,
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
    await widget.onAddFriend(user);
  }

  Future<void> scanQr() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (raw == null || raw.trim().isEmpty) return;
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
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: TsddAssetIconButton(
                        asset: 'assets/tsdd/common/ic_ab_back.png',
                        onTap: () => Navigator.pop(context),
                        tooltip: '返回',
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 38,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: BlinStyle.iconSurface(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TextField(
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
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: '搜索(精确搜索)',
                            hintStyle: TextStyle(
                              color: BlinStyle.subtle,
                              fontSize: 14,
                            ),
                            contentPadding: EdgeInsets.symmetric(vertical: 11),
                          ),
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: scanQr,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            tooltip: '扫一扫',
                          ),
                          TextButton(
                            onPressed: canSearch
                                ? () => unawaited(search())
                                : null,
                            style: TextButton.styleFrom(
                              foregroundColor: BlinStyle.primary,
                              disabledForegroundColor: BlinStyle.primary
                                  .withValues(alpha: .28),
                              minimumSize: const Size(52, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              '搜索',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: .5,
              color: BlinStyle.hairline(context, .70).color,
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (message != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                            child: Text(
                              message!,
                              style: const TextStyle(
                                color: BlinStyle.subtle,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        for (final user in users)
                          _SearchUserResultRow(
                            user: user,
                            showUserId: widget.showUserId,
                            onOpen: () => Navigator.pop(context, user),
                            onAdd: () => unawaited(addFriend(user)),
                          ),
                      ],
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
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const _SearchUserResultRow({
    required this.user,
    required this.showUserId,
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
      onPressed: onAdd,
      style: TextButton.styleFrom(
        backgroundColor: BlinStyle.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(54, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text(
        '申请',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('输入二维码内容'),
        content: TextField(
          controller: input,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '粘贴二维码文本'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    input.dispose();
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
  List<MomentItem> items = [];
  bool loading = true;
  bool posting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
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
        limit: 30,
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

  Future<void> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final urls = <String>[];
    for (final file in result.files.take(9 - selectedImages.length)) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final uploaded = await widget.api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: file.name,
      );
      final url =
          '${uploaded['url'] ?? uploaded['path'] ?? uploaded['file_url'] ?? uploaded['src'] ?? ''}'
              .trim();
      if (url.isNotEmpty) urls.add(url);
    }
    if (!mounted || urls.isEmpty) return;
    setState(() => selectedImages.addAll(urls));
  }

  Future<void> post() async {
    final text = input.text.trim();
    if (text.isEmpty && selectedImages.isEmpty) return;
    setState(() => posting = true);
    try {
      await widget.api.createMoment(
        token: widget.session.token,
        content: text,
        images: selectedImages,
      );
      input.clear();
      selectedImages.clear();
      await load();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
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
              IconButton(
                onPressed: posting ? null : post,
                icon: posting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: input,
                            minLines: 2,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              hintText: '这一刻的想法...',
                              border: InputBorder.none,
                            ),
                          ),
                          if (selectedImages.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _MomentImageGrid(
                              images: selectedImages,
                              onRemove: (url) =>
                                  setState(() => selectedImages.remove(url)),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: BlinStyle.softFill,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.config.allVisible
                                          ? Icons.public_rounded
                                          : Icons.people_outline_rounded,
                                      size: 16,
                                      color: BlinStyle.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      widget.config.visibilityLabel,
                                      style: const TextStyle(
                                        color: BlinStyle.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: selectedImages.length >= 9
                                    ? null
                                    : pickImages,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('图片'),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: posting ? null : post,
                                child: const Text('发布'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  else if (loading)
                    const _ChatSkeletonList()
                  else if (items.isEmpty)
                    const NativeListRow(
                      leading: NativeIconBox(
                        icon: Icons.auto_graph_outlined,
                        color: BlinStyle.subtle,
                        size: 40,
                      ),
                      title: '暂无朋友圈',
                      subtitle: '好友发布的动态会显示在这里',
                    )
                  else
                    for (final item in items)
                      _MomentTile(item: item, timeText: timeText(item.createTime)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MomentTile extends StatelessWidget {
  final MomentItem item;
  final String timeText;
  const _MomentTile({required this.item, required this.timeText});

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: AppAvatar(imageUrl: item.avatar, name: item.nickname, size: 44),
    title: item.nickname,
    subtitle: item.content.isEmpty ? '[图片]' : item.content,
    meta: '${item.visibility == 'all' ? '全员可见' : '仅好友'} · $timeText',
    minHeight: item.images.isEmpty ? 74 : 172,
    trailing: item.images.isEmpty
        ? null
        : SizedBox(
            width: 112,
            child: _MomentImageGrid(images: item.images.take(4).toList()),
          ),
  );
}

class _MomentImageGrid extends StatelessWidget {
  final List<String> images;
  final ValueChanged<String>? onRemove;
  const _MomentImageGrid({required this.images, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final count = images.length.clamp(1, 9);
    final columns = count == 1 ? 1 : (count <= 4 ? 2 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: images.length,
      itemBuilder: (_, index) {
        final url = images[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: BlinStyle.softFill,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
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
  }
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
  final ImOnlineStatus? online;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  const _UnifiedConversationTile({
    required this.conversation,
    required this.online,
    required this.onTap,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) => _ChatTile(
    onTap: onTap,
    onLongPress: conversation.isSystem ? null : onTogglePin,
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conversation.unread > 0)
              Badge(
                label: Text(
                  conversation.unread > 99 ? '99+' : '${conversation.unread}',
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              onPressed: conversation.isSystem ? null : onTogglePin,
              icon: Icon(
                conversation.pinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 18,
                color: conversation.pinned
                    ? BlinStyle.primary
                    : (conversation.isSystem
                          ? Colors.transparent
                          : BlinStyle.subtle),
              ),
              tooltip: conversation.pinned ? '取消置顶' : '置顶聊天',
            ),
          ],
        ),
      ],
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
  final VoidCallback? onLongPress;
  final String avatar;
  final String name;
  final String subtitle;
  final ImOnlineStatus? online;
  final Widget trailing;
  final bool pinned;
  final IconData? fallbackIcon;
  const _ChatTile({
    required this.onTap,
    this.onLongPress,
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
    final leading = Stack(
      clipBehavior: Clip.none,
      children: [
        AppAvatar(
          imageUrl: avatar,
          name: name,
          online: online?.online == true,
          showOnline: online != null,
          size: 50,
          fallbackIcon: fallbackIcon,
        ),
        if (pinned)
          Positioned(
            left: -3,
            top: -3,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: BlinStyle.primary,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: BlinStyle.surface(context)),
              ),
              child: const Icon(
                Icons.push_pin_rounded,
                color: Colors.white,
                size: 11,
              ),
            ),
          ),
      ],
    );
    return NativeListRow(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: pinned,
      leading: leading,
      title: name,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}

class _Empty extends StatelessWidget {
  final UserSession session;
  final VoidCallback onManual;
  const _Empty({required this.session, required this.onManual});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: BlinStyle.surface(context),
    padding: const EdgeInsets.fromLTRB(15, 38, 15, 34),
    child: Column(
      children: [
        const NativeIconBox(
          icon: Icons.mark_chat_unread_outlined,
          color: BlinStyle.subtle,
          size: 54,
        ),
        const SizedBox(height: 12),
        const Text(
          '暂无会话',
          style: TextStyle(
            color: BlinStyle.ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '当前用户名：@${session.username}',
          style: const TextStyle(color: BlinStyle.subtle, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: onManual, child: const Text('搜索用户名')),
      ],
    ),
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

class _GroupChatScreenState extends State<_GroupChatScreen> {
  final api = const ApiService();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
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
  bool mentionSheetOpen = false;
  DateTime lastScreenshotNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int bottomScrollGeneration = 0;
  Timer? voiceTimer;
  DateTime? voiceStartedAt;

  @override
  void initState() {
    super.initState();
    unawaited(loadGroupPreferences());
    load();
    unawaited(loadMembers());
    unawaited(ScreenshotMonitor.prepare());
    screenshotSub = ScreenshotMonitor.events.listen((_) {
      unawaited(_sendGroupScreenshotNotice());
    });
    refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && !loading) unawaited(load(silent: true));
    });
    inputFocus.addListener(() {
      if (inputFocus.hasFocus) {
        _bottom(delay: const Duration(milliseconds: 280));
      }
    });
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
      if (mounted) {
        final visible = messages.isEmpty
            ? _dedupeMessages(list)
            : _mergeTimelineMessages(messages, list);
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
      'nickname': widget.session.nickname ?? '我',
      'avatar': widget.session.avatar,
      'content': {
        'text': text,
        if (mentionAll) 'mention_all': true,
        if (mentionUserIds.isNotEmpty) 'mention_user_ids': mentionUserIds,
      },
      'create_time': DateTime.now().toIso8601String(),
    };
    setState(() {
      sending = true;
      messages.add(UnifiedMessage.fromPayload(payload, widget.session.id));
    });
    _bottom();
    try {
      await api.sendGroupMessage(
        token: widget.session.token,
        groupId: group.id,
        content: text,
        payload: payload,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
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
      'nickname': widget.session.nickname ?? '我',
      'avatar': widget.session.avatar,
      'content': {
        ...content,
        'nickname': widget.session.nickname ?? '我',
        'avatar': widget.session.avatar,
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
    final generation = ++bottomScrollGeneration;
    Future.delayed(delay, () {
      if (!mounted ||
          !scroll.hasClients ||
          generation != bottomScrollGeneration) {
        return;
      }
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _jumpToBottomAfterLayout() {
    final generation = ++bottomScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !scroll.hasClients ||
          generation != bottomScrollGeneration) {
        return;
      }
      scroll.jumpTo(scroll.position.maxScrollExtent);
    });
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
      builder: (_) => AlertDialog(
        title: const Text('群公告'),
        content: SizedBox(
          width: double.maxFinite,
          child: _NoticeRichPreview(
            text: notice,
            richText: group.noticeRichText,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空群聊天记录'),
        content: const Text('确定要清空当前群聊记录吗？清空范围按后台应用配置生效，会话入口会继续保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
        nickname: widget.session.nickname ?? '我',
        avatar: widget.session.avatar,
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
      raw['nickname'],
      raw['from_nickname'],
      raw['sender_name'],
      fromUser['nickname'],
      fromUser['username'],
      content['nickname'],
      member?.nickname,
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
      raw['avatar'],
      raw['from_avatar'],
      raw['user_avatar'],
      fromUser['avatar'],
      fromUser['usertx'],
      content['avatar'],
      member?.avatar,
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

  Future<void> insertMention() => showMentionPicker();

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
      type: mediaType == 'image' ? FileType.image : FileType.any,
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
    setState(() => sending = true);
    try {
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: file.name,
      );
      final url = _pickUploadUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回文件地址');
      final type = mediaType == 'image' ? 'image' : 'file';
      final caption = input.text.trim();
      final payload = _groupMessagePayload(
        type: type,
        clientMsgNo:
            'group_${type}_${group.id}_${widget.session.id}_${DateTime.now().microsecondsSinceEpoch}',
        content: {
          'url': url,
          'file_url': url,
          'name': file.name,
          'size': file.size,
          if (caption.isNotEmpty && type == 'image') 'text': caption,
        },
      );
      input.clear();
      if (mounted) {
        setState(() {
          messages.add(UnifiedMessage.fromPayload(payload, widget.session.id));
        });
        _bottom();
      }
      await api.sendGroupMessage(
        token: widget.session.token,
        groupId: group.id,
        content: type == 'image' ? '[图片]' : '[文件] ${file.name}',
        payload: payload,
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
      if (mounted) {
        setState(() {
          messages.add(UnifiedMessage.fromPayload(payload, widget.session.id));
        });
        _bottom();
      }
      await api.sendGroupMessage(
        token: widget.session.token,
        groupId: group.id,
        content: '[语音] ${formatVoiceDuration(duration)}',
        payload: payload,
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
      'src',
      'audio',
      'file_path',
    ]) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    if (action == 'copy') {
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

  String _messageFileUrl(UnifiedMessage message) =>
      '${message.content['url'] ?? message.content['file_url'] ?? message.content['path'] ?? ''}'
          .trim();

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

  @override
  void dispose() {
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
                      padding: const EdgeInsets.fromLTRB(
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
                          onDownloadFile: () => openGroupFilePreview(message),
                          onJoinGroupCall: _handleJoinGroupCall,
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
              onFile: () => unawaited(sendGroupAttachment(mediaType: 'file')),
              onVoice: toggleVoiceInputMode,
              onVoicePressStart: () => unawaited(_startVoiceRecording()),
              onVoicePressEnd: () =>
                  unawaited(_finishVoiceRecording(send: true)),
              onVoicePressCancel: () =>
                  unawaited(_finishVoiceRecording(send: false)),
              onMention: insertMention,
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
  final VoidCallback? onDownloadFile;
  final ValueChanged<UnifiedMessage>? onJoinGroupCall;
  final ValueChanged<UnifiedMessage>? onAction;
  const _GroupMessageBubble({
    required this.message,
    required this.avatar,
    required this.sender,
    required this.time,
    required this.groupCallEnded,
    this.onPreviewImage,
    this.onDownloadFile,
    this.onJoinGroupCall,
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
    final text = '${message.content['text'] ?? message.preview}';
    const contentColor = BlinStyle.ink;
    const metaColor = BlinStyle.subtle;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth:
            MediaQuery.sizeOf(context).width *
            (special == null ? (isImage ? .54 : .70) : .76),
      ),
      padding: special != null
          ? EdgeInsets.zero
          : (isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(12, 9, 12, 8)),
      decoration: BoxDecoration(
        color: me ? BlinStyle.sentBubble : BlinStyle.surface(context),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(me ? 0 : 20),
          topRight: Radius.circular(me ? 20 : 0),
          bottomLeft: const Radius.circular(0),
          bottomRight: const Radius.circular(0),
        ),
        border: Border.all(
          color: me
              ? BlinStyle.sentBubbleBorder.withValues(alpha: .78)
              : BlinStyle.hairline(context, .82).color,
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
            _GroupImageContent(message: message)
          else if (message.msgType == 'file')
            _GroupFileContent(message: message, onTap: onDownloadFile)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                    ),
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
      onTap: isImage ? onPreviewImage : null,
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
      return _GroupCallRecordCard(message: message, time: time);
    }
    return null;
  }
}

class _GroupImageContent extends StatelessWidget {
  final UnifiedMessage message;
  const _GroupImageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    final url =
        '${message.content['url'] ?? message.content['file_url'] ?? ''}';
    final text = '${message.content['text'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isNotEmpty) _GroupImagePreview(url: url),
        if (text.isNotEmpty && text != '[图片]') ...[
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: message.isMe ? Colors.white : BlinStyle.ink,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
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
  const _GroupCallRecordCard({required this.message, required this.time});

  @override
  Widget build(BuildContext context) {
    final video = '${message.content['media']}'.contains('video');
    final status = '${message.content['status']}';
    final text = _statusText(
      status,
      int.tryParse('${message.content['duration'] ?? 0}') ?? 0,
    );
    return Padding(
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
    final media = CallMediaEngine();
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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .28),
    child: Container(
      width: size,
      height: size,
      color: const Color(0xFFECEFF7),
      child: avatar.isNotEmpty
          ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
          : Center(
              child: Text(
                name.characters.isEmpty ? '?' : name.characters.first,
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: size * .36,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    ),
  );
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
  final VoidCallback onFile;
  final VoidCallback onVoice;
  final VoidCallback onVoicePressStart;
  final VoidCallback onVoicePressEnd;
  final VoidCallback onVoicePressCancel;
  final VoidCallback onMention;
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
    required this.onFile,
    required this.onVoice,
    required this.onVoicePressStart,
    required this.onVoicePressEnd,
    required this.onVoicePressCancel,
    required this.onMention,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        border: Border(
          top: BorderSide(color: BlinStyle.hairline(context, .82).color),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
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
                        constraints: const BoxConstraints(minHeight: 35),
                        padding: const EdgeInsets.fromLTRB(5, 0, 5, 3),
                        decoration: BoxDecoration(
                          color: BlinStyle.iconSurface(context),
                          borderRadius: BorderRadius.circular(14),
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
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 9,
                            ),
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
                        size: 35,
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
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_emoji.png',
                  label: '表情',
                  onTap: onEmoji,
                ),
                _ComposerAction(
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_album.png',
                  label: '图片',
                  onTap: onImage,
                ),
                _ComposerAction(
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_more.png',
                  label: '文件',
                  onTap: onFile,
                ),
                _ComposerAction(
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_aite.png',
                  label: '@',
                  onTap: onMention,
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
    decoration: const BoxDecoration(color: BlinStyle.bg),
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
  final String asset;
  final String label;
  final VoidCallback? onTap;
  const _ComposerAction({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              asset,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: 4),
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
