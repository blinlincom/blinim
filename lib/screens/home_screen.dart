import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../models/community.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
import '../widgets/gradient_shell.dart';
import '../widgets/post_card.dart';
import 'chat_list_screen.dart';

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

  @override
  void dispose() {
    imSub?.cancel();
    im.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await im.disconnect();
    await AuthStore().clear();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ForumFeed(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        connectionError: im.connectionError,
        onReconnect: _connect,
      ),
      const _Discover(),
      ChatListScreen(session: widget.session, im: im),
      _Mine(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        connectionError: im.connectionError,
        onReconnect: _connect,
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: GradientShell(child: SafeArea(bottom: false, child: pages[index])),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: NavigationBar(
            height: 68,
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: '论坛',
              ),
              NavigationDestination(
                icon: Icon(Icons.travel_explore_outlined),
                selectedIcon: Icon(Icons.travel_explore_rounded),
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
        ),
      ),
    );
  }
}

class _ForumFeed extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;

  const _ForumFeed({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final posts = _mockPosts(session);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ForumHero(
                  username: session.username,
                  connected: connected,
                  connecting: connecting,
                  connectionError: connectionError,
                  onReconnect: onReconnect,
                ),
                const SizedBox(height: 16),
                _ComposePrompt(username: session.username),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _ForumTabs()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: _TopicStrip(),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (c, i) => PostCard(post: posts[i], featured: i == 0),
            childCount: posts.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  List<CommunityPost> _mockPosts(UserSession session) => [
    const CommunityPost(
      id: 1,
      author: '春色园社区',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '实时 IM 已接入 Flutter，论坛消息现在可以真正动起来了',
      content:
          '历史消息走 PHP，实时接收走 WuKongIM。安卓、网页、iOS 共用一套 Flutter 渲染，后续可以把帖子评论和私信联动起来。',
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
      title: '社区 UI 进入暖色论坛风格',
      content: '保留玻璃质感，但减少 Demo 感。强化发帖入口、话题卡、内容层级和底部四栏导航，让产品更像真实可运营社区。',
      image: 'https://images.unsplash.com/photo-1557683316-973673baf926?w=1200',
      likes: 86,
      comments: 19,
      time: '10分钟前',
    ),
    CommunityPost(
      id: 3,
      author: session.username,
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '欢迎回来，${session.username}',
      content: '你可以从论坛看动态，在发现页找话题，在消息页聊天，在我的页面管理资料和退出登录。',
      likes: 42,
      comments: 8,
      time: '今天',
    ),
  ];
}

class _ForumHero extends StatelessWidget {
  final String username;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;

  const _ForumHero({
    required this.username,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? '实时在线' : (connecting ? '连接中' : '未连接');
    final statusColor = connected
        ? const Color(0xFF1D9A63)
        : (connecting ? const Color(0xFFE98222) : const Color(0xFFE54848));

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4).withOpacity(.82),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(.72)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF24160D).withOpacity(.08),
            blurRadius: 34,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22150F),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Blinlin Forum',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              _LiveBadge(text: statusText, color: statusColor),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '论坛',
            style: TextStyle(
              color: const Color(0xFF20130D),
              fontSize: 46,
              height: .95,
              letterSpacing: -2.4,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.white.withOpacity(.8),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Hi，$username，今天也有新的连接发生。',
            style: TextStyle(
              color: const Color(0xFF4E4037).withOpacity(.82),
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!connected && !connecting) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(connectionError == null ? '重试实时连接' : '实时连接异常，点击重试'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _LiveBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withOpacity(.10),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withOpacity(.26)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _ComposePrompt extends StatelessWidget {
  final String username;
  const _ComposePrompt({required this.username});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('发帖功能开发中'))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.72),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(.76)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF22150F),
              child: Text(
                username.isEmpty ? 'B' : username[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '今天想分享什么？',
                style: TextStyle(
                  color: Color(0xFF7A6B60),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A59),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7A59).withOpacity(.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ForumTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tabs = ['推荐', '关注 · 3', '同城', '技术', '旅行', '生活'];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemBuilder: (_, i) {
          final selected = i == 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF22150F)
                  : Colors.white.withOpacity(.68),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : Colors.white.withOpacity(.7),
              ),
            ),
            child: Text(
              tabs[i],
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF4C4038),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: tabs.length,
      ),
    );
  }
}

class _TopicStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF22150F), Color(0xFF6D3F2D)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF22150F).withOpacity(.18),
          blurRadius: 26,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.13),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFFFFC267),
          ),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日热议',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '#实时聊天 #跨端发布 #社区体验',
                style: TextStyle(
                  color: Color(0xFFE8D8C8),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.arrow_forward_rounded, color: Colors.white),
      ],
    ),
  );
}

class _Discover extends StatelessWidget {
  const _Discover();

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const BouncingScrollPhysics(),
    slivers: [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 24, 22, 10),
          child: Text(
            '发现',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
              color: Color(0xFF20130D),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .98,
          children: const [
            _DiscoverCard(
              icon: Icons.tag_rounded,
              title: '热门话题',
              desc: '正在讨论的内容',
            ),
            _DiscoverCard(
              icon: Icons.groups_rounded,
              title: '推荐圈子',
              desc: '找到同频的人',
            ),
            _DiscoverCard(
              icon: Icons.place_rounded,
              title: '同城动态',
              desc: '附近的新鲜事',
            ),
            _DiscoverCard(
              icon: Icons.notifications_active_rounded,
              title: '系统公告',
              desc: '版本和活动通知',
            ),
          ],
        ),
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
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.72),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withOpacity(.75)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF22150F),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: const Color(0xFFFFD0A5)),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF20130D),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          desc,
          style: TextStyle(
            color: const Color(0xFF20130D).withOpacity(.55),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Mine extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;
  final Future<void> Function() onLogout;

  const _Mine({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? '实时在线' : (connecting ? '连接中' : '未连接');
    final statusColor = connected
        ? const Color(0xFF1D9A63)
        : (connecting ? const Color(0xFFE98222) : const Color(0xFFE54848));
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.76),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withOpacity(.8)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xFF22150F),
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
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.username,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF20130D),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'ID ${session.id}',
                          style: TextStyle(
                            color: const Color(0xFF20130D).withOpacity(.55),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _LiveBadge(text: statusText, color: statusColor),
                ],
              ),
              if (!connected && !connecting) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onReconnect,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(connectionError == null ? '重试连接' : '实时连接异常'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _MineTile(
          icon: Icons.article_rounded,
          title: '我的帖子',
          desc: '查看我发布过的内容',
        ),
        const _MineTile(
          icon: Icons.favorite_rounded,
          title: '我的收藏',
          desc: '保存的帖子和话题',
        ),
        const _MineTile(
          icon: Icons.settings_rounded,
          title: '设置',
          desc: '账号、安全和通知',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22150F),
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text(
            '退出登录',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
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
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.68),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF6D3F2D)),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF20130D),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: TextStyle(
                  color: const Color(0xFF20130D).withOpacity(.52),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}
