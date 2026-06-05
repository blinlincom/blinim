import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  const ChatListScreen({super.key, required this.session, required this.im});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final api = const ApiService();
  final search = TextEditingController();
  List<ConversationItem> items = [];
  List<UserSearchResult> users = [];
  bool loading = true;
  bool searching = false;
  String? error;
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  final Map<int, bool> peerOnline = {};

  @override
  void initState() {
    super.initState();
    load();
    sub = widget.im.messages.listen((_) => load());
    presenceSub = widget.im.presences.listen((p) {
      if (mounted) setState(() => peerOnline[p.userId] = p.online);
    });
  }

  Future<void> refreshPeerOnlineForItems(List<ConversationItem> list) async {
    for (final item in list) {
      try {
        final online = await api.getImOnlineStatus(
          token: widget.session.token,
          userId: item.userId,
        );
        if (mounted) setState(() => peerOnline[item.userId] = online);
      } catch (_) {
        if (mounted) setState(() => peerOnline[item.userId] = false);
      }
    }
  }

  Future<void> load() async {
    try {
      final r = await api.getMessageList(widget.session.token);
      if (mounted) setState(() => items = r);
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
      setState(() => users = []);
      return;
    }
    if (int.tryParse(kw) != null) {
      final id = int.parse(kw);
      if (id == widget.session.id) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('不能和自己聊天')));
        return;
      }
      openChat(id, '用户$id', '');
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final r = await api.searchUsers(widget.session.token, kw);
      if (mounted)
        setState(
          () => users = r.where((u) => u.id != widget.session.id).toList(),
        );
    } catch (e) {
      if (mounted) setState(() => error = '搜索失败：$e。你也可以直接输入用户ID开聊。');
    } finally {
      if (mounted) setState(() => searching = false);
    }
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
    if (id != null && id > 0 && id != widget.session.id)
      openChat(id, '用户$id', '');
  }

  @override
  void dispose() {
    search.dispose();
    presenceSub?.cancel();
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('消息'),
          actions: [
            IconButton.filledTonal(
              onPressed: manualOpenDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            const SizedBox(width: 12),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => doSearch(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜索用户或输入用户ID',
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: doSearch,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
              ),
            ),
          ),
        ),
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (users.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionTitle('搜索结果')),
          SliverList.separated(
            itemBuilder: (_, i) => _UserTile(
              user: users[i],
              onTap: () =>
                  openChat(users[i].id, users[i].nickname, users[i].avatar),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: users.length,
          ),
        ],
        const SliverToBoxAdapter(child: _SectionTitle('最近会话')),
        if (loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          SliverFillRemaining(
            child: _Empty(session: widget.session, onManual: manualOpenDialog),
          )
        else
          SliverList.separated(
            itemBuilder: (_, i) => _ConversationTile(
              item: items[i],
              online: peerOnline[items[i].userId],
              onTap: () =>
                  openChat(items[i].userId, items[i].nickname, items[i].avatar),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: items.length,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _UserTile extends StatelessWidget {
  final UserSearchResult user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundImage: user.avatar.isNotEmpty
              ? CachedNetworkImageProvider(user.avatar)
              : null,
          child: user.avatar.isEmpty
              ? Text(user.nickname.characters.first)
              : null,
        ),
        title: Text(
          user.nickname,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('ID: ${user.id}  @${user.username}'),
        trailing: const Icon(Icons.chat_bubble_rounded),
      ),
    ),
  );
}

class _ConversationTile extends StatelessWidget {
  final ConversationItem item;
  final bool? online;
  final VoidCallback onTap;
  const _ConversationTile({
    required this.item,
    required this.online,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 26,
          backgroundImage: item.avatar.isNotEmpty
              ? CachedNetworkImageProvider(item.avatar)
              : null,
          child: item.avatar.isEmpty
              ? Text(item.nickname.characters.first)
              : null,
        ),
        title: Text(
          item.nickname,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            _PeerOnlineChip(online: online),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.msgTime.length > 10
                  ? item.msgTime.substring(5, 16)
                  : item.msgTime,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (item.unread > 0) Badge(label: Text('${item.unread}')),
          ],
        ),
      ),
    ),
  );
}

class _PeerOnlineChip extends StatelessWidget {
  final bool? online;
  const _PeerOnlineChip({required this.online});
  @override
  Widget build(BuildContext context) {
    final text = online == null ? '检测在线状态...' : (online! ? '对方在线' : '对方离线');
    final color = online == null
        ? Colors.grey
        : (online! ? Colors.green : Colors.orange);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final UserSession session;
  final VoidCallback onManual;
  const _Empty({required this.session, required this.onManual});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mark_chat_unread_rounded, size: 64),
          const SizedBox(height: 12),
          Text(
            '暂无会话',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '当前用户 ID：${session.id}。可以搜索用户，或直接输入对方用户ID开始聊天。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('按用户ID开聊'),
          ),
        ],
      ),
    ),
  );
}
