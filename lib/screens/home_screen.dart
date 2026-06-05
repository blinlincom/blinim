import 'dart:async';
import 'package:flutter/material.dart';
import '../models/community.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';
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
      _FeedTab(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
      ),
      const _DiscoverTab(),
      _PartnerTab(session: widget.session, im: im),
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
      body: PageBackdrop(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: '搭子',
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

class _FeedTab extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  const _FeedTab({
    required this.session,
    required this.connected,
    required this.connecting,
  });

  @override
  Widget build(BuildContext context) {
    final posts = _posts(session);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 56, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '动态',
                      style: TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 18),
                    const Text(
                      '欣赏',
                      style: TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _StatusDot(connected: connected, connecting: connecting),
                  ],
                ),
                const SizedBox(height: 14),
                _QuickSearch(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('帖子搜索接口待接入；用户搜索在搭子/消息页可用')),
                  ),
                ),
                const SizedBox(height: 14),
                const _StoryRail(),
              ],
            ),
          ),
        ),
        SliverList.separated(
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: PostCard(post: posts[i], featured: i == 0),
          ),
          separatorBuilder: (_, index) => const SizedBox(height: 14),
          itemCount: posts.length,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
      ],
    );
  }

  List<CommunityPost> _posts(UserSession session) => [
    const CommunityPost(
      id: 1,
      author: '叶子',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '7月12日—7月17日去云南6天5晚旅游，差一个成团，免费，有意者联系',
      content: '当前动态流是为了后续帖子接口预留的商业化布局；真实可用能力已在消息、搭子页接入 PHP 用户搜索和 IM。',
      image:
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200',
      likes: 1236,
      comments: 7,
      time: '1天前 · 广州市',
    ),
    const CommunityPost(
      id: 2,
      author: '小羊薄贝',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '网球搭子 AA 的有吗？周末深圳湾练球',
      content:
          '这类卡片后续可由 /get_forum_posts 或 /get_partner_posts 提供数据，现在先按现有功能做 UI 骨架。',
      image:
          'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?w=1200',
      likes: 86,
      comments: 19,
      time: '2天前 · 深圳市',
    ),
    CommunityPost(
      id: 3,
      author: session.username,
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '欢迎回来，${session.username}，先去消息页测试实时聊天',
      content: 'PHP 登录、用户搜索、会话列表、聊天记录、发送消息、在线状态已经接入。',
      likes: 42,
      comments: 8,
      time: '今天',
    ),
  ];
}

class _QuickSearch extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickSearch({required this.onTap});
  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    radius: 18,
    onTap: onTap,
    child: const Row(
      children: [
        Icon(Icons.search_rounded, color: BlinStyle.muted),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            '搜索搭子 / 动态 / 用户',
            style: TextStyle(
              color: BlinStyle.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Icon(Icons.tune_rounded, color: BlinStyle.ink),
      ],
    ),
  );
}

class _StatusDot extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _StatusDot({required this.connected, required this.connecting});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      boxShadow: [BlinStyle.softShadow(.06)],
    ),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: connected
                ? BlinStyle.green
                : (connecting ? BlinStyle.orange : Colors.redAccent),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? '实时' : (connecting ? '连接' : '离线'),
          style: const TextStyle(
            color: BlinStyle.ink,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _StoryRail extends StatelessWidget {
  const _StoryRail();
  @override
  Widget build(BuildContext context) {
    final items = const [
      ('日常', Icons.tag_faces_rounded),
      ('全国', Icons.public_rounded),
      ('旅行', Icons.flight_takeoff_rounded),
      ('运动', Icons.sports_tennis_rounded),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BlinStyle.softShadow(.04)],
          ),
          child: Row(
            children: [
              Icon(items[i].$2, color: BlinStyle.ink, size: 18),
              const SizedBox(width: 6),
              Text(
                items[i].$1,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        separatorBuilder: (_, index) => const SizedBox(width: 9),
        itemCount: items.length,
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 56, 18, 20),
    children: const [
      Text(
        '发现',
        style: TextStyle(
          color: BlinStyle.ink,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
      SizedBox(height: 14),
      _BannerCard(),
      SizedBox(height: 14),
      _DiscoverGrid(),
    ],
  );
}

class _BannerCard extends StatelessWidget {
  const _BannerCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: BlinStyle.brandGradient,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [BlinStyle.softShadow(.18)],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '今日推荐',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '基于现有 PHP 用户搜索与 IM 能力，先把找搭子和聊天体验做扎实。',
          style: TextStyle(
            color: Color(0xEEFFFFFF),
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DiscoverGrid extends StatelessWidget {
  const _DiscoverGrid();
  @override
  Widget build(BuildContext context) {
    final items = const [
      ('找搭子', '搜索用户/输入ID', Icons.groups_rounded),
      ('实时消息', '会话与在线状态', Icons.chat_rounded),
      ('热门动态', '待帖子接口接入', Icons.local_fire_department_rounded),
      ('系统公告', '版本与部署说明', Icons.campaign_rounded),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: .98,
      ),
      itemBuilder: (_, i) => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientIcon(icon: items[i].$3),
            const Spacer(),
            Text(
              items[i].$1,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              items[i].$2,
              style: const TextStyle(
                color: BlinStyle.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerTab extends StatelessWidget {
  final UserSession session;
  final ImService im;
  const _PartnerTab({required this.session, required this.im});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 56, 18, 20),
    children: [
      const Text(
        '搭子',
        style: TextStyle(
          color: BlinStyle.ink,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 12),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '找一个能聊的人',
              style: TextStyle(
                color: BlinStyle.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '当前按现有 PHP 接口：用户搜索、输入用户 ID、打开聊天。',
              style: TextStyle(
                color: BlinStyle.muted,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatListScreen(session: session, im: im),
                ),
              ),
              icon: const Icon(Icons.search_rounded),
              label: const Text('搜索/输入ID开聊'),
            ),
          ],
        ),
      ),
    ],
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
    padding: const EdgeInsets.fromLTRB(18, 56, 18, 20),
    children: [
      SoftCard(
        radius: 30,
        child: Column(
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: BlinStyle.green.withValues(alpha: .16),
              child: Text(
                session.username.isEmpty
                    ? 'B'
                    : session.username[0].toUpperCase(),
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              session.username,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'UID ${session.id} · ${connected ? '实时在线' : (connecting ? '连接中' : '离线')}',
              style: const TextStyle(
                color: BlinStyle.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const _MineTile(
        icon: Icons.article_rounded,
        title: '我的动态',
        desc: '帖子接口接入后展示',
      ),
      const _MineTile(
        icon: Icons.chat_rounded,
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
          label: Text(connectionError == null ? '重试连接' : '实时连接异常'),
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
  Widget build(BuildContext context) => SoftCard(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        GradientIcon(icon: icon, size: 42, iconSize: 21),
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
              const SizedBox(height: 3),
              Text(
                desc,
                style: const TextStyle(
                  color: BlinStyle.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: BlinStyle.muted),
      ],
    ),
  );
}
