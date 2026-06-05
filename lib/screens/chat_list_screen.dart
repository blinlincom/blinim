import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import 'chat_screen.dart';

const _forumBlue = Color(0xFF2F6BFF);
const _bg = Color(0xFFF4F7FB);
const _ink = Color(0xFF17233D);
const _muted = Color(0xFF778399);

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
      if (mounted) {
        setState(
          () => users = r.where((u) => u.id != widget.session.id).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '搜索失败：$e。也可以直接输入用户ID开聊。');
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
    if (id != null && id > 0 && id != widget.session.id) {
      openChat(id, '用户$id', '');
    }
  }

  @override
  void dispose() {
    search.dispose();
    presenceSub?.cancel();
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _forumBlue,
      foregroundColor: Colors.white,
      title: const Text('消息', style: TextStyle(fontWeight: FontWeight.w900)),
      actions: [
        IconButton(
          onPressed: manualOpenDialog,
          icon: const Icon(Icons.person_add_alt_1_rounded),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
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
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (users.isNotEmpty) ...[
            const _SectionTitle('搜索结果'),
            ...users.map(
              (u) => _UserTile(
                user: u,
                onTap: () => openChat(u.id, u.nickname, u.avatar),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const _SectionTitle('最近会话'),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
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
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _UserTile extends StatelessWidget {
  final UserSearchResult user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});
  @override
  Widget build(BuildContext context) => _WhiteTile(
    onTap: onTap,
    leading: CircleAvatar(
      backgroundImage: user.avatar.isNotEmpty
          ? CachedNetworkImageProvider(user.avatar)
          : null,
      child: user.avatar.isEmpty ? Text(user.nickname.characters.first) : null,
    ),
    title: user.nickname,
    subtitle: 'ID: ${user.id}  @${user.username}',
    trailing: const Icon(Icons.chat_bubble_rounded, color: _forumBlue),
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
  Widget build(BuildContext context) => _WhiteTile(
    onTap: onTap,
    leading: Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 25,
          backgroundImage: item.avatar.isNotEmpty
              ? CachedNetworkImageProvider(item.avatar)
              : null,
          child: item.avatar.isEmpty
              ? Text(item.nickname.characters.first)
              : null,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online == true ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    ),
    title: item.nickname,
    subtitle: item.preview,
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          item.msgTime.length > 10
              ? item.msgTime.substring(5, 16)
              : item.msgTime,
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (item.unread > 0) Badge(label: Text('${item.unread}')),
      ],
    ),
  );
}

class _WhiteTile extends StatelessWidget {
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _WhiteTile({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(Icons.mark_chat_unread_rounded, size: 56, color: _forumBlue),
        const SizedBox(height: 12),
        const Text(
          '暂无会话',
          style: TextStyle(
            color: _ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '当前用户 ID：${session.id}。可以搜索用户，或直接输入对方用户ID开始聊天。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
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
