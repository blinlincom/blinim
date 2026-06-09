import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';
import 'chat_screen.dart';

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

class _ChatListScreenState extends State<ChatListScreen> {
  final api = const ApiService();
  final search = TextEditingController();
  List<ConversationItem> items = [];
  List<Map<String, dynamic>> systemNotifications = [];
  int systemUnreadCount = 0;
  List<UserSearchResult> users = [];
  List<UserSearchResult> friends = [];
  List<ImGroup> groups = [];
  bool loading = true;
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

  @override
  void initState() {
    super.initState();
    load();
    sub = widget.im.messages.listen((_) => load());
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
          final hasFreshRealtime = realtimeAt != null &&
              DateTime.now().difference(realtimeAt) < const Duration(seconds: 45);
          if (!hasFreshRealtime) setState(() => peerOnline[item.userId] = status);
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

  Future<void> load() async {
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
      final unreadTotal = r.fold<int>(0, (sum, item) => sum + item.unread);
      widget.onUnreadChanged?.call(unreadTotal + unreadNotifications.length);
      if (mounted) {
        setState(() {
          items = r;
          friends = friendList;
          groups = groupList;
          systemNotifications = notifications;
          systemUnreadCount = unreadNotifications.length;
        });
      }
      unawaited(refreshPeerOnlineForItems(r));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
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
    try {
      await widget.im.sendDirect(
        channelId: ImService.uidForUser(user.id),
        payload: {
          'msg_type': 'friend',
          'from_user_id': widget.session.id,
          'to_user_id': user.id,
          'from_uid': ImService.uidForUser(widget.session.id),
          'to_uid': ImService.uidForUser(user.id),
          'content': {
            'action': action,
            'message': message,
            'user_id': widget.session.id,
            'nickname': widget.session.nickname,
            'avatar': widget.session.avatar,
          },
          'create_time': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {}
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
      await widget.im.sendDirect(
        channelId: ImService.uidForUser(fromId),
        payload: {
          'msg_type': 'friend',
          'from_user_id': widget.session.id,
          'to_user_id': fromId,
          'from_uid': ImService.uidForUser(widget.session.id),
          'to_uid': ImService.uidForUser(fromId),
          'content': {
            'action': 'accepted',
            'message': '我通过了你的好友申请',
            'user_id': widget.session.id,
            'nickname': widget.session.nickname,
            'avatar': widget.session.avatar,
          },
          'create_time': DateTime.now().toIso8601String(),
        },
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
          onOpen: (u) => openChat(u.id, u.nickname, u.avatar),
        ),
      ),
    );
  }

  Future<void> createGroup() async {
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先添加好友后再建群')));
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
    final memberIds = (result['members'] as List?)?.cast<int>() ?? const <int>[];
    if (name.isEmpty || memberIds.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写群名并选择成员')));
      return;
    }
    try {
      final group = await api.createImGroup(token: widget.session.token, name: name, memberIds: memberIds);
      await load();
      if (mounted) openGroupChat(group);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('建群失败：$e')));
    }
  }

  void openGroupChat(ImGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GroupChatScreen(session: widget.session, im: widget.im, group: group),
      ),
    ).then((_) => load());
  }

  void openChat(int userId, String name, String avatar) {
    Navigator.push(
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
    ).then((_) => load());
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
                  gradient: BlinStyle.brandGradient,
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
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.4,
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

  @override
  void dispose() {
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
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            children: [
              Row(
                children: [
                  const Text(
                    '消息',
                    style: TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: createGroup,
                    icon: const Icon(Icons.group_add_rounded),
                  ),
                  IconButton(
                    onPressed: manualOpenDialog,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                  IconButton(
                    onPressed: showSearchDialog,
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _MessageActions(
                onManual: manualOpenDialog,
                onSystem: openSystemNotifications,
                onFriends: openFriends,
                onCreateGroup: createGroup,
                onSearch: showSearchDialog,
                systemUnreadCount: systemUnreadCount,
              ),
              const SizedBox(height: 18),
              if (groups.isNotEmpty) ...[
                const _SectionTitle('我的群聊'),
                const SizedBox(height: 8),
                for (final group in groups)
                  _ChatTile(
                    name: group.name,
                    subtitle: '${group.memberCount}人 · 群号 ${group.groupNo}',
                    avatar: group.avatar,
                    trailing: const Icon(Icons.groups_rounded, color: BlinStyle.blue),
                    onTap: () => openGroupChat(group),
                  ),
                const SizedBox(height: 12),
              ],
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
              const _SectionTitle('消息通知'),
              if (loading)
                const _ChatSkeletonList()
              else if (items.isEmpty)
                _Empty(session: widget.session, onManual: manualOpenDialog)
              else
                ...items.map(
                  (it) => _ConversationTile(
                    item: it,
                    online: peerOnline[it.userId],
                    onTap: () => openChat(it.userId, it.nickname, it.avatar),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SystemNotificationTile extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  const _SystemNotificationTile({required this.items, required this.onTap});

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

  @override
  Widget build(BuildContext context) {
    final latest = items.isNotEmpty ? items.first : const <String, dynamic>{};
    final preview = latest.isEmpty
        ? '点赞、收藏、评论等互动会在这里展示'
        : _pick(latest, const [
            'content',
            'message',
            'title',
            'msg',
          ], '你有新的系统通知');
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      radius: 22,
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: BlinStyle.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BlinStyle.softShadow(.10)],
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        title: const Text(
          '系统通知',
          style: TextStyle(color: BlinStyle.ink, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (items.isNotEmpty) Badge(label: Text('${items.length}')),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: BlinStyle.muted),
          ],
        ),
      ),
    );
  }
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
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '系统通知',
                      style: TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    TextButton.icon(
                      onPressed: clearing ? null : markAllRead,
                      icon: clearing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all_rounded, size: 18),
                      label: Text('一键已读 · $unreadCount'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (loading && items.isEmpty)
                const _ChatSkeletonList()
              else if (items.isEmpty)
                const SoftCard(
                  child: Text(
                    '暂无系统通知，点赞、收藏、评论等互动会显示在这里。',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
                  ], '你有一条新的互动通知');
                  final time = _pick(row, const [
                    'create_time',
                    'time',
                    'created_at',
                    'time_ago',
                  ]);
                  final unread = _isUnread(row);
                  return SoftCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    onTap: () => openNotification(row),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GradientIcon(
                              icon: Icons.favorite_rounded,
                              size: 42,
                              iconSize: 20,
                            ),
                            if (unread)
                              Positioned(
                                right: -1,
                                top: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF6B6B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
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
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF42526A),
                                  height: 1.45,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (time.isNotEmpty) ...[
                                const SizedBox(height: 6),
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
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: BlinStyle.muted,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
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
      'postid',
      'post_id',
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
        await widget.im.sendDirect(
          channelId: ImService.uidForUser(friendRequesterId),
          payload: {
            'msg_type': 'text',
            'from_user_id': widget.session.id,
            'to_user_id': friendRequesterId,
            'from_uid': ImService.uidForUser(widget.session.id),
            'to_uid': ImService.uidForUser(friendRequesterId),
            'content': {'text': defaultText},
            'create_time': DateTime.now().toIso8601String(),
          },
        );
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
    if (type.contains('like') || text.contains('赞'))
      return Icons.favorite_rounded;
    if (type.contains('collect') || text.contains('收藏'))
      return Icons.bookmark_rounded;
    if (type.contains('comment') || text.contains('评论') || text.contains('回复'))
      return Icons.mode_comment_rounded;
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
                gradient: BlinStyle.brandGradient,
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
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.3,
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
      (i) => SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _ChatSkeletonBox(width: 48, height: 48, radius: 18),
            const SizedBox(width: 12),
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
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: .88)),
    ),
  );
}

class _MessageActions extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onSystem;
  final VoidCallback onFriends;
  final VoidCallback onCreateGroup;
  final VoidCallback onSearch;
  final int systemUnreadCount;
  const _MessageActions({
    required this.onManual,
    required this.onSystem,
    required this.onFriends,
    required this.onCreateGroup,
    required this.onSearch,
    required this.systemUnreadCount,
  });
  @override
  Widget build(BuildContext context) {
    final items = [
      ('系统通知', Icons.notifications_active_rounded, onSystem),
      ('我的好友', Icons.groups_rounded, onFriends),
      ('创建群聊', Icons.group_add_rounded, onCreateGroup),
      ('添加好友', Icons.person_add_alt_1_rounded, onSearch),
      ('联系人', Icons.contacts_rounded, onManual),
    ];
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map(
              (e) => InkWell(
                onTap: e.$3,
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GradientIcon(icon: e.$2, size: 42, iconSize: 21),
                        if (e.$1 == '系统通知' && systemUnreadCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Badge(
                              label: Text(
                                systemUnreadCount > 99
                                    ? '99+'
                                    : '$systemUnreadCount',
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      e.$1,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
    child: Text(
      text,
      style: const TextStyle(
        color: BlinStyle.ink,
        fontSize: 18,
        fontWeight: FontWeight.w900,
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

class _FriendsScreen extends StatelessWidget {
  final List<UserSearchResult> friends;
  final ValueChanged<UserSearchResult> onOpen;
  const _FriendsScreen({required this.friends, required this.onOpen});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 6),
                const Text(
                  '我的好友',
                  style: TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
  );
}

class _ConversationTile extends StatelessWidget {
  final ConversationItem item;
  final ImOnlineStatus? online;
  final VoidCallback onTap;
  const _ConversationTile({
    required this.item,
    required this.online,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => _ChatTile(
    onTap: onTap,
    avatar: item.avatar,
    name: item.nickname,
    subtitle: '${online?.label ?? '检测在线状态'} · ${item.preview}',
    online: online,
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          item.msgTime.length > 10
              ? item.msgTime.substring(5, 16)
              : item.msgTime,
          style: const TextStyle(
            color: BlinStyle.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (item.unread > 0) Badge(label: Text('${item.unread}')),
      ],
    ),
  );
}

class _ChatTile extends StatelessWidget {
  final VoidCallback onTap;
  final String avatar;
  final String name;
  final String subtitle;
  final ImOnlineStatus? online;
  final Widget trailing;
  const _ChatTile({
    required this.onTap,
    required this.avatar,
    required this.name,
    required this.subtitle,
    this.online,
    required this.trailing,
  });
  @override
  Widget build(BuildContext context) => SoftCard(
    margin: const EdgeInsets.only(bottom: 10),
    padding: EdgeInsets.zero,
    radius: 22,
    onTap: onTap,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundImage: avatar.isNotEmpty
                ? CachedNetworkImageProvider(avatar)
                : null,
            child: avatar.isEmpty ? Text(name.characters.first) : null,
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: online?.online == true
                      ? BlinStyle.green
                      : BlinStyle.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: BlinStyle.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    ),
  );
}

class _Empty extends StatelessWidget {
  final UserSession session;
  final VoidCallback onManual;
  const _Empty({required this.session, required this.onManual});
  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      children: [
        const GradientIcon(
          icon: Icons.mark_chat_unread_rounded,
          size: 58,
          iconSize: 30,
        ),
        const SizedBox(height: 12),
        const Text(
          '暂无会话',
          style: TextStyle(
            color: BlinStyle.ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '当前用户 ID：${session.id}。可以搜索用户，或直接输入对方用户ID开始聊天。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: BlinStyle.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('按用户ID开聊'),
        ),
      ],
    ),
  );
}

class _GroupChatScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final ImGroup group;
  const _GroupChatScreen({required this.session, required this.im, required this.group});

  @override
  State<_GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<_GroupChatScreen> {
  final api = const ApiService();
  final input = TextEditingController();
  final scroll = ScrollController();
  List<UnifiedMessage> messages = [];
  StreamSubscription? sub;
  Timer? refreshTimer;
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !loading) unawaited(load(silent: true));
    });
    sub = widget.im.messages.listen((m) {
      if (m.toUid == widget.group.groupNo || '${m.raw['group_id']}' == '${widget.group.id}') {
        if (mounted && !messages.map(_messageKey).contains(_messageKey(m))) setState(() => messages.add(m));
        _bottom();
      }
    });
  }

  Future<void> load({bool silent = false}) async {
    try {
      final list = await api.getGroupChatLog(token: widget.session.token, groupId: widget.group.id, myId: widget.session.id);
      if (mounted) {
        final existing = messages.map(_messageKey).toSet();
        final merged = <UnifiedMessage>[...messages];
        for (final item in list) {
          if (existing.add(_messageKey(item))) merged.add(item);
        }
        setState(() => messages = silent ? merged : list);
      }
      _bottom();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _messageKey(UnifiedMessage message) {
    final raw = message.raw;
    return '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.createTime.toIso8601String()}';
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    input.clear();
    final payload = {
      'msg_type': 'text',
      'client_msg_no': 'group_${widget.group.id}_${DateTime.now().microsecondsSinceEpoch}',
      'from_user_id': widget.session.id,
      'from_uid': ImService.uidForUser(widget.session.id),
      'to_uid': widget.group.groupNo,
      'group_id': widget.group.id,
      'group_no': widget.group.groupNo,
      'content': {'text': text},
      'create_time': DateTime.now().toIso8601String(),
    };
    setState(() {
      sending = true;
      messages.add(UnifiedMessage.fromPayload(payload, widget.session.id));
    });
    _bottom();
    try {
      try {
        await widget.im.sendGroup(channelId: widget.group.groupNo, payload: payload);
      } catch (_) {}
      await api.sendGroupMessage(token: widget.session.token, groupId: widget.group.id, content: text, payload: payload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _bottom() => Future.delayed(const Duration(milliseconds: 80), () {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  });

  @override
  void dispose() {
    sub?.cancel();
    refreshTimer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
              title: Text(widget.group.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${widget.group.memberCount}人 · ${widget.group.groupNo}'),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        final me = m.isMe;
                        return Align(
                          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .74),
                            decoration: BoxDecoration(color: me ? BlinStyle.green : Colors.white, borderRadius: BorderRadius.circular(18)),
                            child: Text('${m.content['text'] ?? m.preview}', style: TextStyle(color: me ? Colors.white : BlinStyle.ink, fontWeight: FontWeight.w700)),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: input, decoration: const InputDecoration(hintText: '发消息到群聊'), onSubmitted: (_) => send())),
                  IconButton(onPressed: sending ? null : send, icon: const Icon(Icons.send_rounded, color: BlinStyle.green)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
