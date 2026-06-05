import 'dart:async';
import 'package:flutter/material.dart';
import '../models/community.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
import '../widgets/post_card.dart';
import 'chat_list_screen.dart';

const _forumBlue = Color(0xFF2F6BFF);
const _bg = Color(0xFFF4F7FB);
const _ink = Color(0xFF17233D);
const _muted = Color(0xFF778399);

class HomeScreen extends StatefulWidget {
  final UserSession session;
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.session, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  late final ImService im;
  StreamSubscription? imSub;

  @override
  void initState() {
    super.initState();
    im = ImService();
    imSub = im.connectionChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _connect();
  }

  Future<void> _connect() async {
    try {
      final info = await const ApiService().getImConnectInfo(
        widget.session.token,
      );
      await im.connect(info: info, myId: widget.session.id);
    } catch (e) {
      im.connectionError = 'IM 连接信息获取失败：$e';
      im.connecting = false;
      im.connected = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _logout() async {
    await im.disconnect();
    await AuthStore().clear();
    widget.onLogout();
  }

  @override
  void dispose() {
    imSub?.cancel();
    im.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ForumTab(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        onReconnect: _connect,
      ),
      const _DiscoverTab(),
      ChatListScreen(session: widget.session, im: im),
      _MineTab(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        connectionError: im.connectionError,
        onReconnect: _connect,
        onLogout: _logout,
      ),
    ];
    return Scaffold(
      backgroundColor: _bg,
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: '论坛',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: '消息',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _ForumTab extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final VoidCallback onReconnect;
  const _ForumTab({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final posts = _posts(session);
    return RefreshIndicator(
      onRefresh: () async {},
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _forumBlue,
            foregroundColor: Colors.white,
            titleSpacing: 14,
            title: const Text(
              'Blinlin 吧',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              _ImBadge(connected: connected, connecting: connecting),
              const SizedBox(width: 10),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(58),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: _SearchBarLike(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前 PHP 接口支持搜索用户，帖子搜索接口待接入')),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                children: [
                  _BarHeader(
                    session: session,
                    connected: connected,
                    connecting: connecting,
                    onReconnect: onReconnect,
                  ),
                  const SizedBox(height: 10),
                  _ForumChannels(),
                  const SizedBox(height: 10),
                  _PublishEntry(username: session.username),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: _SectionHeader(title: '吧内热帖', action: '按回复排序'),
          ),
          SliverList.separated(
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: PostCard(post: posts[i], featured: i == 0),
            ),
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemCount: posts.length,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
      ),
    );
  }

  List<CommunityPost> _posts(UserSession session) => [
    const CommunityPost(
      id: 1,
      author: '系统吧务',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '【置顶】当前版本已接入登录、私信、实时在线和会话列表',
      content: '这条是基于现有 PHP/IM 能力展示的论坛贴样式。帖子列表接口后续接入后，可以直接替换这里的占位数据源。',
      image:
          'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=1200',
      likes: 128,
      comments: 36,
      time: '刚刚',
    ),
    const CommunityPost(
      id: 2,
      author: 'Blinlin Lab',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '【精华】为什么这版 UI 不直接复刻贴吧，而是做蓝白论坛产品化',
      content: '风格借鉴贴吧的信息密度、吧头、热帖、回复结构，但功能严格围绕现有 PHP API：登录、搜索用户、私信、在线状态。',
      image: null,
      likes: 86,
      comments: 19,
      time: '10分钟前',
    ),
    CommunityPost(
      id: 3,
      author: session.username,
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '欢迎回来，${session.username}，你可以先从消息页测试实时聊天',
      content: '论坛首页目前是商业化 UI 骨架，消息页已经接入真实会话、搜索用户和聊天接口。',
      likes: 42,
      comments: 8,
      time: '今天',
    ),
  ];
}

class _SearchBarLike extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBarLike({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, color: _muted),
          SizedBox(width: 8),
          Text(
            '搜索吧内内容 / 用户',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _BarHeader extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final VoidCallback onReconnect;
  const _BarHeader({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _forumBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blinlin 吧',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '吧友 ${session.username} · UID ${session.id}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('签到功能待 PHP 接口接入'))),
              child: const Text('签到'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const _Stat(value: '3', label: '热帖'),
            const _Stat(value: '2', label: '测试账号'),
            const _Stat(value: '实时', label: 'IM 状态'),
            if (!connected && !connecting)
              TextButton(onPressed: onReconnect, child: const Text('重连')),
          ],
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ForumChannels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = const [
      ('全部', Icons.grid_view_rounded),
      ('精华', Icons.workspace_premium_rounded),
      ('热议', Icons.local_fire_department_rounded),
      ('吧务', Icons.verified_user_rounded),
    ];
    return Row(
      children: items
          .map(
            (e) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Icon(e.$2, color: _forumBlue),
                      const SizedBox(height: 5),
                      Text(
                        e.$1,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PublishEntry extends StatelessWidget {
  final String username;
  const _PublishEntry({required this.username});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: _forumBlue.withValues(alpha: .12),
          child: Text(
            username.isEmpty ? 'B' : username[0].toUpperCase(),
            style: const TextStyle(
              color: _forumBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '发一条帖子，和吧友聊聊...',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton(
          onPressed: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('发帖接口待接入'))),
          child: const Text('发帖'),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  const _SectionHeader({required this.title, required this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        Text(
          action,
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _ImBadge extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _ImBadge({required this.connected, required this.connecting});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      connected ? '在线' : (connecting ? '连接中' : '离线'),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 58, 14, 18),
    children: const [
      Text(
        '发现',
        style: TextStyle(
          color: _ink,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
      SizedBox(height: 12),
      _DiscoverCard(
        icon: Icons.search_rounded,
        title: '找人聊天',
        desc: '基于 PHP 搜索用户接口，可以搜索用户名或直接输入用户 ID',
      ),
      _DiscoverCard(
        icon: Icons.forum_rounded,
        title: '吧内热帖',
        desc: '当前为前端占位数据，等待后端帖子接口接入',
      ),
      _DiscoverCard(
        icon: Icons.chat_bubble_rounded,
        title: '实时私信',
        desc: 'WuKongIM 长连接 + PHP 历史消息',
      ),
      _DiscoverCard(
        icon: Icons.campaign_rounded,
        title: '系统公告',
        desc: '版本、接口、部署状态说明',
      ),
    ],
  );
}

class _DiscoverCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _DiscoverCard({
    required this.icon,
    required this.title,
    required this.desc,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: _forumBlue, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: _muted, height: 1.35)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: _muted),
      ],
    ),
  );
}

class _MineTab extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;
  final Future<void> Function() onLogout;
  const _MineTab({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 58, 14, 18),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _forumBlue,
              child: Text(
                session.username.isEmpty
                    ? 'B'
                    : session.username[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.username,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'UID ${session.id} · ${connected ? '实时在线' : (connecting ? '连接中' : '离线')}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const _MineTile(
        icon: Icons.article_rounded,
        title: '我的帖子',
        desc: '帖子接口接入后展示真实发帖',
      ),
      const _MineTile(
        icon: Icons.message_rounded,
        title: '我的消息',
        desc: '查看真实私信会话',
      ),
      const _MineTile(
        icon: Icons.settings_rounded,
        title: '设置',
        desc: '账号、安全和通知',
      ),
      if (!connected && !connecting)
        OutlinedButton.icon(
          onPressed: onReconnect,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(connectionError == null ? '重试实时连接' : '实时连接异常，点击重试'),
        ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('退出登录'),
      ),
    ],
  );
}

class _MineTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _MineTile({
    required this.icon,
    required this.title,
    required this.desc,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: ListTile(
      leading: Icon(icon, color: _forumBlue),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, color: _ink),
      ),
      subtitle: Text(desc),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}
