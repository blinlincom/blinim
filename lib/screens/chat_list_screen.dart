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
    // 支持直接输入数字用户ID开聊，不依赖后端搜索接口。
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '即时消息',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.1,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: manualOpenDialog,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                    ),
                  ],
                ),
                Text(
                  '搜索用户名/昵称，或直接输入用户ID发起聊天',
                  style: TextStyle(
                    color: Colors.black.withOpacity(.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _SearchBox(
                  controller: search,
                  loading: searching,
                  onSubmit: doSearch,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (users.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 4),
              child: Text(
                '搜索结果',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((c, i) {
              final u = users[i];
              return _UserTile(
                user: u,
                onTap: () => openChat(u.id, u.nickname, u.avatar),
              );
            }, childCount: users.length),
          ),
        ],
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 22, 4),
            child: Text(
              '最近会话',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        if (loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          SliverFillRemaining(
            child: _Empty(session: widget.session, onManual: manualOpenDialog),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((c, i) {
              final it = items[i];
              return _ConversationTile(
                item: it,
                online: peerOnline[it.userId],
                onTap: () => openChat(it.userId, it.nickname, it.avatar),
              );
            }, childCount: items.length),
          ),
      ],
    ),
  );
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSubmit;
  const _SearchBox({
    required this.controller,
    required this.loading,
    required this.onSubmit,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.82),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: onSubmit,
              ),
        hintText: '搜索用户或输入用户ID',
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    ),
  );
}

class _UserTile extends StatelessWidget {
  final UserSearchResult user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.78),
      borderRadius: BorderRadius.circular(24),
    ),
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
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('ID: ${user.id}  @${user.username}'),
      trailing: const Icon(Icons.chat_bubble_rounded),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.78),
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
        style: const TextStyle(fontWeight: FontWeight.w900),
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
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withOpacity(.42),
            ),
          ),
          if (item.unread > 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF5A5F),
              ),
              child: Text(
                '${item.unread}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
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
        ? Colors.grey.shade600
        : (online! ? Colors.green.shade700 : Colors.orange.shade700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w800,
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
          const Text(
            '暂无会话',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
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
