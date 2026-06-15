import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../calls/call_media_engine.dart';
import '../calls/call_session.dart';
import '../calls/call_signaling_adapter.dart';
import '../core/app_logger.dart';
import '../models/call_signal.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'group_settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final ValueChanged<int>? onUnreadChanged;
  const ChatListScreen({
    super.key,
    required this.session,
    required this.im,
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
  List<UserSearchResult> users = [];
  List<UserSearchResult> friends = [];
  List<ImGroup> groups = [];
  List<_UnifiedConversation> conversations = [];
  Set<String> pinnedConversationKeys = {};
  bool loading = true;
  bool loadingList = false;
  bool searching = false;
  String? error;
  StreamSubscription? sub;
  StreamSubscription? friendSub;
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
      final content = payload['content'];
      final action = content is Map ? '${content['action']}' : '';
      if (action == 'accepted' && mounted) {
        final name = content is Map ? '${content['nickname'] ?? '对方'}' : '对方';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 已通过你的好友申请')));
      }
      unawaited(load());
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

  bool _isHiddenRealtimeGroupCallEvent(UnifiedMessage message) {
    final type = message.msgType.toLowerCase();
    return type == 'group_call_join' || type == 'group_call_leave';
  }

  String get _pinStorageKey => 'pinned_conversations_${widget.session.id}';

  Future<void> _loadPinnedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_pinStorageKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      pinnedConversationKeys = saved.toSet();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinStorageKey, next.toList()..sort());
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
    var preview = '${group.memberCount}人 · 群号 ${group.groupNo}';
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
    );
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

  Future<void> doSearch() async {
    final kw = search.text.trim();
    if (kw.isEmpty) {
      setState(() {
        users = [];
        error = null;
      });
      return;
    }
    setState(() {
      searching = true;
      error = null;
      users = [];
    });
    try {
      final r = await api.searchUsers(widget.session.token, kw);
      final filtered = r.where((u) => u.id != widget.session.id).toList();
      if (mounted) {
        setState(() {
          users = filtered;
          error = filtered.isEmpty ? '没有该用户，请检查账号或用户ID' : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '搜索暂时不可用，请稍后再试');
    } finally {
      if (mounted) setState(() => searching = false);
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
    final content = payload['content'];
    if (content is! Map) return;
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
      await api.addFriend(widget.session.token, fromId, message: '我通过了你的好友申请');
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
          onOpen: (u) => openChat(u.id, u.nickname, u.avatar),
        ),
      ),
    );
  }

  Future<void> createGroup() async {
    if (friends.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先添加好友后再建群')));
      return;
    }
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
                  decoration: const InputDecoration(labelText: '群名称'),
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
                          subtitle: Text('ID ${friend.id}'),
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
    final name = '${result['name'] ?? ''}'.trim();
    final memberIds =
        (result['members'] as List?)?.cast<int>() ?? const <int>[];
    if (name.isEmpty || memberIds.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请填写群名并选择成员')));
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

  Future<void> showSearchDialog() async {
    final c = TextEditingController(text: search.text);
    final keyword = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BlinStyle.softShadow(.20)],
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
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '搜索用户',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '通过接口返回的真实用户发起聊天',
                            style: TextStyle(
                              color: Color(0xE6FFFFFF),
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
              const SizedBox(height: 16),
              TextField(
                controller: c,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  hintText: '昵称 / 账号 / 用户ID',
                  labelText: '搜索关键词',
                  filled: true,
                  fillColor: const Color(0xFFF5F8F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                autofocus: true,
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
              ),
              const SizedBox(height: 12),
              const Text(
                '不会再直接跳转到不存在的用户；必须搜索到用户后，点击结果才进入聊天。',
                style: TextStyle(
                  color: BlinStyle.muted,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, c.text.trim()),
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('搜索'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    c.dispose();
    if (keyword == null) return;
    search.text = keyword;
    await doSearch();
  }

  Future<void> manualOpenDialog() async {
    final c = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('按用户 ID 发起聊天'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '例如：2',
            labelText: '对方用户ID',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(c.text.trim())),
            child: const Text('开始聊天'),
          ),
        ],
      ),
    );
    c.dispose();
    if (id != null && id > 0 && id != widget.session.id) {
      openChat(id, '用户$id', '');
    }
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
              subtitle: '按用户 ID 进入私聊',
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
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (users.isNotEmpty) ...[
                    const _SectionTitle('搜索结果'),
                    ...users.map(
                      (u) => _UserTile(
                        user: u,
                        onTap: () => openChat(u.id, u.nickname, u.avatar),
                        onAdd: () => addFriend(u),
                      ),
                    ),
                  ],
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
  const ContactsScreen({super.key, required this.session, required this.im});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final api = const ApiService();
  List<UserSearchResult> friends = [];
  List<ImGroup> groups = [];
  List<Map<String, dynamic>> notifications = [];
  int unreadCount = 0;
  bool loading = true;
  bool refreshing = false;
  String? error;
  StreamSubscription? friendSub;
  StreamSubscription? messageSub;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    friendSub = widget.im.friendEvents.listen((_) => unawaited(load()));
    messageSub = widget.im.messages.listen(
      (_) => unawaited(load(silent: true)),
    );
  }

  @override
  void dispose() {
    friendSub?.cancel();
    messageSub?.cancel();
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
        api.getMessageNotifications(
          widget.session.token,
          page: 1,
          limit: 50,
          unreadOnly: true,
        ),
      ]);
      final nextFriends = (result[0] as List<UserSearchResult>).toList()
        ..sort((a, b) => a.nickname.compareTo(b.nickname));
      final nextGroups = (result[1] as List<ImGroup>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        friends = nextFriends;
        groups = nextGroups;
        notifications = (result[2] as List<Map<String, dynamic>>).toList();
        unreadCount = (result[3] as List<Map<String, dynamic>>).length;
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
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('搜索用户'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: '昵称 / 账号 / 用户ID',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
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
    try {
      final result = await api.searchUsers(widget.session.token, keyword);
      final users = result.where((u) => u.id != widget.session.id).toList();
      if (!mounted) return;
      if (users.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有找到该用户')));
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: BlinStyle.surface(context),
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('搜索结果', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final user in users)
                        _UserTile(
                          user: user,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            unawaited(openChat(user));
                          },
                          onAdd: () {
                            Navigator.pop(sheetContext);
                            unawaited(addFriend(user));
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('搜索暂时不可用：$e')));
    }
  }

  Future<void> manualOpenDialog() async {
    final controller = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('按用户 ID 发起聊天'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '对方用户ID',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('开始聊天'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (id == null || id <= 0 || id == widget.session.id) return;
    await openChat(
      UserSearchResult(id: id, username: '$id', nickname: '用户$id', avatar: ''),
    );
  }

  Future<void> createGroup() async {
    if (friends.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先添加好友后再建群')));
      return;
    }
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
                  decoration: const InputDecoration(labelText: '群名称'),
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
                          subtitle: Text('ID ${friend.id}'),
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
    final name = '${result['name'] ?? ''}'.trim();
    final memberIds =
        (result['members'] as List?)?.cast<int>() ?? const <int>[];
    if (name.isEmpty || memberIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写群名并选择成员')));
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
                    subtitle: unreadCount > 0
                        ? '$unreadCount 条待处理通知'
                        : '好友申请和系统提醒',
                    badge: unreadCount,
                    onTap: openSystemNotifications,
                  ),
                  _ContactActionTile(
                    icon: Icons.tag_outlined,
                    title: '按用户 ID 开聊',
                    subtitle: '输入 ID 直接进入私聊',
                    onTap: manualOpenDialog,
                  ),
                  const _SectionTitle('群聊'),
                  if (loading)
                    const _ChatSkeletonList()
                  else if (groups.isEmpty)
                    _ContactEmptyTile(
                      icon: Icons.groups_outlined,
                      text: '暂无群聊，可以从右上角创建群聊。',
                      onTap: createGroup,
                    )
                  else
                    ...groups.map(
                      (group) => _ChatTile(
                        onTap: () => openGroupChat(group),
                        avatar: group.avatar,
                        name: group.name,
                        subtitle:
                            '${group.memberCount}人 · 群号 ${group.groupNo.isEmpty ? group.id : group.groupNo}',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.subtle,
                        ),
                      ),
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
                        subtitle: 'ID: ${user.id}  @${user.username}',
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
            subtitle: '好友申请、系统提醒和账号消息',
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
                      subtitle: '好友申请和系统提醒会显示在这里',
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
  bool handling = false;

  String _pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = widget.row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  bool get isFriendRequest {
    final type = _pick(const [
      'type',
      'notification_type',
      'action',
      'category',
    ]).toLowerCase();
    final text =
        '${_pick(const ['title', 'type_name'])} ${_pick(const ['content', 'message', 'msg', 'text'])}';
    return type.contains('friend') ||
        type.contains('好友') ||
        text.contains('好友申请') ||
        text.contains('添加你为好友');
  }

  bool get isHandledFriendRequest {
    final raw = _pick(const [
      'friend_status',
      'handle_status',
      'request_status',
      'status_text',
    ]).toLowerCase();
    final status =
        '${widget.row['friend_status'] ?? widget.row['handle_status'] ?? widget.row['request_status'] ?? widget.row['status_text'] ?? ''}'
            .toLowerCase();
    return raw.contains('已通过') ||
        raw.contains('已拒绝') ||
        status == 'accepted' ||
        status == 'rejected' ||
        status == 'reject' ||
        status == 'refuse';
  }

  int get friendRequesterId {
    for (final key in const [
      'from_user_id',
      'sender_id',
      'apply_user_id',
      'request_user_id',
      'friend_id',
      'user_id',
    ]) {
      final value = int.tryParse('${widget.row[key] ?? ''}') ?? 0;
      if (value > 0) return value;
    }
    return 0;
  }

  Future<void> handleFriendRequest(bool accept) async {
    if (handling || friendRequesterId <= 0) return;
    setState(() => handling = true);
    try {
      final msg = await widget.api.handleFriendRequest(
        widget.token,
        userId: friendRequesterId,
        accept: accept,
      );
      if (accept) {
        const defaultText = '我已通过你的好友申请，现在我们可以开始聊天了';
        await widget.api.sendMessage(
          token: widget.token,
          receiverId: friendRequesterId,
          content: defaultText,
          messageType: 0,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => handling = false);
    }
  }

  IconData get icon {
    final type = _pick(const [
      'type',
      'notification_type',
      'action',
    ]).toLowerCase();
    final text =
        '${_pick(const ['title', 'type_name'])} ${_pick(const ['content', 'message', 'msg', 'text'])}';
    if (type.contains('friend') || text.contains('好友'))
      return Icons.person_add_alt_1_rounded;
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
            if (isFriendRequest &&
                !isHandledFriendRequest &&
                friendRequesterId > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: handling
                          ? null
                          : () => handleFriendRequest(false),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('拒绝'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: handling
                          ? null
                          : () => handleFriendRequest(true),
                      icon: handling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('同意'),
                    ),
                  ),
                ],
              ),
            ] else
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

class _UserTile extends StatelessWidget {
  final UserSearchResult user;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  const _UserTile({
    required this.user,
    required this.onTap,
    required this.onAdd,
  });
  @override
  Widget build(BuildContext context) => _ChatTile(
    onTap: onTap,
    avatar: user.avatar,
    name: user.nickname,
    subtitle: 'ID: ${user.id}  @${user.username}',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onAdd,
          icon: const Icon(
            Icons.person_add_alt_1_rounded,
            color: BlinStyle.green,
          ),
        ),
        const Icon(Icons.chat_bubble_rounded, color: BlinStyle.blue),
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
  final ValueChanged<UserSearchResult> onOpen;
  const _FriendsScreen({required this.friends, required this.onOpen});

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
                        subtitle: 'ID: ${u.id}  @${u.username}',
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
  }) => _UnifiedConversation(
    kind: _ConversationKind.group,
    peer: null,
    group: group,
    notifications: const [],
    key: 'group:${group.id}',
    title: group.name,
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
          : (title.isNotEmpty ? title : '系统提醒和好友申请'),
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
    String? preview,
    String? timeText,
    int? unread,
    bool? pinned,
  }) => _UnifiedConversation(
    kind: kind,
    peer: peer,
    group: group,
    notifications: notifications,
    key: key,
    title: title,
    avatar: avatar,
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
              : '${online?.label ?? '检测在线状态'} · ${conversation.preview}'),
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
          '当前用户 ID：${session.id}',
          style: const TextStyle(color: BlinStyle.subtle, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: onManual, child: const Text('按用户ID开聊')),
      ],
    ),
  );
}

class _GroupChatScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final ImGroup group;
  const _GroupChatScreen({
    required this.session,
    required this.im,
    required this.group,
  });

  @override
  State<_GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<_GroupChatScreen> {
  final api = const ApiService();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  List<UnifiedMessage> messages = [];
  List<ImGroupMember> members = [];
  late ImGroup group = widget.group;
  StreamSubscription? sub;
  Timer? refreshTimer;
  bool loading = true;
  bool sending = false;
  bool showEmojiPanel = false;
  int bottomScrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    load();
    unawaited(loadMembers());
    refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && !loading) unawaited(load(silent: true));
    });
    inputFocus.addListener(() {
      if (inputFocus.hasFocus) {
        _bottom(delay: const Duration(milliseconds: 280));
      }
    });
    sub = widget.im.messages.listen((m) {
      if (m.toUid == group.groupNo || '${m.raw['group_id']}' == '${group.id}') {
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

  bool _sameMessageTimeline(List<UnifiedMessage> a, List<UnifiedMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_messageKeys(a[i]).any(_messageKeys(b[i]).contains)) return false;
    }
    return true;
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    input.clear();
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
      'device': 'Android',
      'content': {'text': text},
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
      'device': 'Android',
      'content': {
        ...content,
        'nickname': widget.session.nickname ?? '我',
        'avatar': widget.session.avatar,
        'device': 'Android',
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发起群通话',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _GroupCallSheetAction(
                icon: Icons.call_rounded,
                title: '群语音通话',
                subtitle: '向群成员发送语音通话邀请',
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(startGroupCall(video: false));
                },
              ),
              const SizedBox(height: 8),
              _GroupCallSheetAction(
                icon: Icons.video_call_rounded,
                title: '群视频通话',
                subtitle: '向群成员发送视频通话邀请',
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(startGroupCall(video: true));
                },
              ),
            ],
          ),
        ),
      ),
    );
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
    await sendGroupCallRecord(result);
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
        builder: (_) =>
            GroupSettingsScreen(session: widget.session, initialGroup: group),
      ),
    );
    if (updated != null && mounted) {
      setState(() => group = updated);
      unawaited(loadMembers());
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

  String _senderName(UnifiedMessage message) {
    final raw = message.raw;
    final content = message.content;
    final member = _memberOf(message);
    final name =
        '${raw['nickname'] ?? raw['from_nickname'] ?? raw['sender_name'] ?? raw['fromUser']?['nickname'] ?? content['nickname'] ?? member?.nickname ?? '用户${message.fromUserId}'}';
    final device =
        '${raw['device'] ?? raw['platform'] ?? raw['from_device'] ?? content['device'] ?? 'Android'}';
    return '$name/$device';
  }

  String _avatarOf(UnifiedMessage message) {
    final raw = message.raw;
    final content = message.content;
    final member = _memberOf(message);
    return '${raw['avatar'] ?? raw['from_avatar'] ?? raw['user_avatar'] ?? raw['fromUser']?['avatar'] ?? raw['fromUser']?['usertx'] ?? content['avatar'] ?? member?.avatar ?? ''}';
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
    setState(() => showEmojiPanel = !showEmojiPanel);
  }

  void insertMention() {
    final start = input.selection.start < 0
        ? input.text.length
        : input.selection.start;
    final end = input.selection.end < 0
        ? input.text.length
        : input.selection.end;
    input.text = input.text.replaceRange(start, end, '@');
    input.selection = TextSelection.collapsed(offset: start + 1);
    inputFocus.requestFocus();
  }

  void showImageComingSoon() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('群聊图片发送入口已预留，后续可接上传接口')));
  }

  void showVoiceComingSoon() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('群语音输入入口已预留，后续可接录音接口')));
  }

  @override
  void dispose() {
    sub?.cancel();
    refreshTimer?.cancel();
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
              onMore: openGroupSettings,
              onGroupVideo: showGroupCallSheet,
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
                          onJoinGroupCall: joinGroupCall,
                        );
                      },
                    ),
            ),
            _GroupComposer(
              controller: input,
              focusNode: inputFocus,
              sending: sending,
              showEmojiPanel: showEmojiPanel,
              onSend: send,
              onEmoji: toggleEmojiPanel,
              onEmojiSelected: insertQuickEmoji,
              onImage: showImageComingSoon,
              onVoice: showVoiceComingSoon,
              onMention: insertMention,
              onMore: openGroupSettings,
            ),
          ],
        ),
      ),
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

class _GroupChatHeader extends StatelessWidget {
  final ImGroup group;
  final VoidCallback onBack;
  final VoidCallback onMore;
  final VoidCallback onGroupVideo;
  const _GroupChatHeader({
    required this.group,
    required this.onBack,
    required this.onMore,
    required this.onGroupVideo,
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
            TsddAssetIconButton(
              asset: 'assets/tsdd/chat/icon_chat_toolbar_more.png',
              onTap: onGroupVideo,
              tooltip: '群视频',
            ),
            TsddAssetIconButton(
              asset: 'assets/tsdd/chat/icon_chat_toolbar_more.png',
              onTap: onMore,
              tooltip: '更多',
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
  final ValueChanged<UnifiedMessage>? onJoinGroupCall;
  const _GroupMessageBubble({
    required this.message,
    required this.avatar,
    required this.sender,
    required this.time,
    this.onJoinGroupCall,
  });

  @override
  Widget build(BuildContext context) {
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
        color: me ? const Color(0xFFFDDED6) : BlinStyle.surface(context),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(me ? 0 : 20),
          topRight: Radius.circular(me ? 20 : 0),
          bottomLeft: const Radius.circular(0),
          bottomRight: const Radius.circular(0),
        ),
        border: Border.all(
          color: me
              ? const Color(0xFFF8937B).withValues(alpha: .35)
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
          else if (isImage)
            _GroupImageContent(message: message)
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
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
    );
  }

  Widget? _specialContent() {
    final type = message.msgType.toLowerCase();
    if (type == 'group_call_invite') {
      return _GroupCallInviteCard(
        message: message,
        time: time,
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
  Widget build(BuildContext context) => InkWell(
    onTap: () => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .86),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .8,
                maxScale: 4,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    borderRadius: BorderRadius.circular(14),
    child: ClipRRect(
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
    ),
  );
}

class _GroupCallInviteCard extends StatelessWidget {
  final UnifiedMessage message;
  final String time;
  final VoidCallback? onJoin;
  const _GroupCallInviteCard({
    required this.message,
    required this.time,
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
                    borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
                  ),
                  textStyle: const TextStyle(
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

class _GroupCallSheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _GroupCallSheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
        border: Border.all(color: BlinStyle.hairline(context, .76).color),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: BlinStyle.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
            ),
            child: Icon(icon, color: BlinStyle.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: BlinStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: BlinStyle.subtle),
        ],
      ),
    ),
  );
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
      await previewMedia.openLocalMedia(video: widget.video);
      sharedStream = previewMedia.localStream;
      joinedUserIds.add(widget.session.id);
      if (widget.inviterId > 0 && widget.inviterId != widget.session.id) {
        joinedUserIds.add(widget.inviterId);
      }
      await _loadRoomEvents();
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

  Future<void> _loadRoomEvents() async {
    try {
      final list = await widget.api.getGroupChatLog(
        token: widget.session.token,
        groupId: widget.group.id,
        myId: widget.session.id,
        limit: 100,
      );
      for (final message in list) {
        _handleRoomMessage(message);
      }
      await _connectToJoinedPeers();
    } catch (e) {
      AppLogger.warn('CALL', '群通话房间事件拉取失败 room=${widget.roomId}', data: e);
    }
  }

  void _handleRealtimeMessage(UnifiedMessage message) {
    if (message.raw['group_id'] != null &&
        '${message.raw['group_id']}' != '${widget.group.id}') {
      return;
    }
    if (message.toUid.isNotEmpty && message.toUid != widget.group.groupNo) {
      return;
    }
    _handleRoomMessage(message);
    unawaited(_connectToJoinedPeers());
  }

  void _handleRoomMessage(UnifiedMessage message) {
    final roomId =
        '${message.content['room_id'] ?? message.content['call_id'] ?? ''}';
    if (roomId != widget.roomId) return;
    final key =
        '${message.raw['client_msg_no'] ?? message.messageId}_${message.msgType}_${message.fromUserId}_${message.createTime.millisecondsSinceEpoch}';
    if (!seenRoomEvents.add(key)) return;
    final type = message.msgType.toLowerCase();
    final userId =
        int.tryParse('${message.content['user_id'] ?? message.fromUserId}') ??
        message.fromUserId;
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

  String _resultStatus() {
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
  final bool showEmojiPanel;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onImage;
  final VoidCallback onVoice;
  final VoidCallback onMention;
  final VoidCallback onMore;
  const _GroupComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.showEmojiPanel,
    required this.onSend,
    required this.onEmoji,
    required this.onEmojiSelected,
    required this.onImage,
    required this.onVoice,
    required this.onMention,
    required this.onMore,
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BlinStyle.iconSurface(context),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: BlinStyle.hairline(context, .76).color,
                    ),
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
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
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
                height: 42,
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
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
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
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_voice.png',
                  label: '语音',
                  onTap: onVoice,
                ),
                _ComposerAction(
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_aite.png',
                  label: '@',
                  onTap: onMention,
                ),
                _ComposerAction(
                  asset: 'assets/tsdd/chat/icon_chat_toolbar_more.png',
                  label: '更多',
                  onTap: onMore,
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
  final VoidCallback onTap;
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
