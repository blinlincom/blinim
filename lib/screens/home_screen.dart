import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../models/community.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
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
      _ForumPage(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        onReconnect: _connect,
      ),
      const _DiscoverPage(),
      ChatListScreen(session: widget.session, im: im),
      _MinePage(
        session: widget.session,
        connected: im.connected,
        connecting: im.connecting,
        connectionError: im.connectionError,
        onReconnect: _connect,
        onLogout: _logout,
      ),
    ];
    return Scaffold(
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

class _ForumPage extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final VoidCallback onReconnect;
  const _ForumPage({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final posts = _posts(session);
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('论坛'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _ConnectionChip(
                  connected: connected,
                  connecting: connecting,
                ),
              ),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _ComposeCard(username: session.username),
                const SizedBox(height: 12),
                const _TopicCard(),
                const SizedBox(height: 12),
                _FilterChips(),
              ],
            ),
          ),
        ),
        SliverList.separated(
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PostCard(post: posts[i], featured: i == 0),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: posts.length,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<CommunityPost> _posts(UserSession session) => [
    const CommunityPost(
      id: 1,
      author: '春色园社区',
      avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
      title: '实时 IM 已接入 Flutter，论坛消息现在可以真正动起来了',
      content: '历史消息走 PHP，实时接收走 WuKongIM。安卓、网页、iOS 共用一套 Flutter 渲染。',
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
      title: '社区 UI 统一为 Material Design 3',
      content: '统一颜色、卡片、输入框、导航和聊天气泡，减少不同页面之间的风格割裂。',
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
      content: '论坛、发现、消息、我的都已收敛到同一套 MD3 视觉语言。',
      likes: 42,
      comments: 8,
      time: '今天',
    ),
  ];
}

class _ComposeCard extends StatelessWidget {
  final String username;
  const _ComposeCard({required this.username});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('发帖功能开发中'))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(username.isEmpty ? 'B' : username[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '今天想分享什么？',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: null,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('发帖'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.local_fire_department_rounded,
          color: scheme.onPrimaryContainer,
        ),
        title: Text(
          '今日热议',
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '#实时聊天 #跨端发布 #社区体验',
          style: TextStyle(color: scheme.onPrimaryContainer.withOpacity(.78)),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = ['推荐', '关注', '同城', '技术', '旅行', '生活'];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => i == 0
            ? ChoiceChip(selected: true, label: Text(items[i]))
            : FilterChip(
                selected: false,
                label: Text(items[i]),
                onSelected: (_) {},
              ),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _ConnectionChip({required this.connected, required this.connecting});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = connected ? '实时在线' : (connecting ? '连接中' : '未连接');
    final color = connected
        ? Colors.green
        : (connecting ? Colors.orange : scheme.error);
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DiscoverPage extends StatelessWidget {
  const _DiscoverPage();
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverAppBar.large(title: Text('发现')),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: const [
            _DiscoverCard(icon: Icons.tag_rounded, title: '热门话题', desc: '正在讨论'),
            _DiscoverCard(
              icon: Icons.groups_rounded,
              title: '推荐圈子',
              desc: '找到同频',
            ),
            _DiscoverCard(
              icon: Icons.place_rounded,
              title: '同城动态',
              desc: '附近新鲜事',
            ),
            _DiscoverCard(
              icon: Icons.notifications_rounded,
              title: '系统公告',
              desc: '版本与活动',
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary, size: 32),
            const Spacer(),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _MinePage extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;
  final Future<void> Function() onLogout;
  const _MinePage({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 16),
      children: [
        Card(
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    session.username.isEmpty
                        ? 'B'
                        : session.username[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.username,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'ID ${session.id}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      _ConnectionChip(
                        connected: connected,
                        connecting: connecting,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
        if (!connected && !connecting) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(connectionError == null ? '重试实时连接' : '实时连接异常，点击重试'),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('退出登录'),
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
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(desc),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}
