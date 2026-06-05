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
  List<UserSearchResult> users = [];
  bool loading = true;
  bool searching = false;
  String? error;
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  StreamSubscription? connectionSub;
  Timer? onlineTimer;
  final Map<int, ImOnlineStatus> peerOnline = {};

  @override
  void initState() {
    super.initState();
    load();
    sub = widget.im.messages.listen((_) => load());
    presenceSub = widget.im.presences.listen((p) {
      if (mounted) {
        setState(() => peerOnline[p.userId] = ImOnlineStatus(online: p.online, device: p.device));
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
  }

  Future<void> refreshPeerOnlineForItems(List<ConversationItem> list) async {
    for (final item in list) {
      try {
        final status = await api.getImOnlineStatus(
          token: widget.session.token,
          userId: item.userId,
        );
        if (mounted) setState(() => peerOnline[item.userId] = status);
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
      final unreadTotal = r.fold<int>(0, (sum, item) => sum + item.unread);
      widget.onUnreadChanged?.call(unreadTotal);
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
          error = filtered.isEmpty ? '没有找到「$kw」相关用户' : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '搜索暂时不可用，请稍后再试');
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
    connectionSub?.cancel();
    presenceSub?.cancel();
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
              _MessageActions(onManual: manualOpenDialog),
              const SizedBox(height: 18),
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
  const _MessageActions({required this.onManual});
  @override
  Widget build(BuildContext context) {
    final items = [
      ('邀请我', Icons.person_add_alt_1_rounded),
      ('我邀请', Icons.waving_hand_rounded),
      ('欣赏我', Icons.favorite_rounded),
      ('我欣赏', Icons.thumb_up_rounded),
      ('联系人', Icons.groups_rounded),
    ];
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map(
              (e) => InkWell(
                onTap: e.$1 == '联系人' ? onManual : null,
                child: Column(
                  children: [
                    GradientIcon(icon: e.$2, size: 42, iconSize: 21),
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
  const _UserTile({required this.user, required this.onTap});
  @override
  Widget build(BuildContext context) => _ChatTile(
    onTap: onTap,
    avatar: user.avatar,
    name: user.nickname,
    subtitle: 'ID: ${user.id}  @${user.username}',
    trailing: const Icon(Icons.chat_bubble_rounded, color: BlinStyle.blue),
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
                  color: online?.online == true ? BlinStyle.green : BlinStyle.orange,
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
