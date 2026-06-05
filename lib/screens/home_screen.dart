import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_config.dart';
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
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onLogout;
  const HomeScreen({
    super.key,
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  final visitedTabs = <int>{0};
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
      _LazyTab(
        loaded: visitedTabs.contains(0),
        child: _FeedTab(
          session: widget.session,
          connected: im.connected,
          connecting: im.connecting,
        ),
      ),
      _LazyTab(loaded: visitedTabs.contains(1), child: const _DiscoverTab()),
      _LazyTab(
        loaded: visitedTabs.contains(2),
        child: ChatListScreen(session: widget.session, im: im),
      ),
      _LazyTab(
        loaded: visitedTabs.contains(3),
        child: _MineTab(
          session: widget.session,
          connected: im.connected,
          connecting: im.connecting,
          connectionError: im.connectionError,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onReconnect: _connect,
          onLogout: _logout,
        ),
      ),
    ];
    return Scaffold(
      body: PageBackdrop(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() {
          index = i;
          visitedTabs.add(i);
        }),
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

class _LazyTab extends StatelessWidget {
  final bool loaded;
  final Widget child;
  const _LazyTab({required this.loaded, required this.child});

  @override
  Widget build(BuildContext context) => loaded
      ? child
      : const SizedBox.expand();
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
                    const SnackBar(content: Text('帖子搜索接口待接入；用户搜索在消息页可用')),
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
      content: '当前动态流是为了后续帖子接口预留的商业化布局；真实可用能力已在消息页接入 PHP 用户搜索和 IM。',
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
      title: '周末深圳湾网球局，缺一位同城球友',
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
            '搜索动态 / 用户 / 帖子',
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
          '基于现有 PHP 用户搜索、论坛、积分与 IM 能力，先把社区内容和聊天体验做扎实。',
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
      ('粉丝关注', '粉丝/关注列表', Icons.favorite_rounded),
      ('积分排行', '金币/经验/积分', Icons.emoji_events_rounded),
      ('热门动态', '推荐帖子列表', Icons.local_fire_department_rounded),
      ('账单会员', '账单/会员/签到', Icons.workspace_premium_rounded),
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

// 原独立找人一级页已移除；找人/输入用户 ID 的能力合并到消息页。
class _MineTab extends StatefulWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onReconnect;
  final Future<void> Function() onLogout;
  const _MineTab({
    required this.session,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onReconnect,
    required this.onLogout,
  });

  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> {
  final api = const ApiService();
  UserProfileSummary profile = const UserProfileSummary();
  bool loadingProfile = true;
  bool hasLoadedProfile = false;
  String? profileError;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    setState(() {
      loadingProfile = !hasLoadedProfile;
      profileError = null;
    });
    try {
      final r = await api.getUserOtherInformation(widget.session.token);
      if (mounted) {
        setState(() {
          profile = r;
          hasLoadedProfile = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => profileError = '$e');
    } finally {
      if (mounted) setState(() => loadingProfile = false);
    }
  }

  Future<void> signIn() async {
    try {
      final msg = await api.userSignIn(widget.session.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('签到失败：$e')));
    }
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsScreen(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: loadProfile,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 48, 18, 22),
      children: [
        if (loadingProfile && !hasLoadedProfile)
          const _ProfileSkeleton()
        else
          _ProfileHero(
            session: widget.session,
            profile: profile,
            connected: widget.connected,
            connecting: widget.connecting,
            onSignIn: signIn,
            onSettings: openSettings,
            loading: false,
          ),
        if (profileError != null) ...[
          const SizedBox(height: 10),
          Text(
            '用户信息加载失败：$profileError',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _QuickCirclePanel(session: widget.session),
        const SizedBox(height: 14),
        _FunctionGridPanel(session: widget.session),
        const SizedBox(height: 14),
        _InterfaceRecordPanel(profile: profile),
        const SizedBox(height: 14),
        if (!widget.connected && !widget.connecting)
          OutlinedButton.icon(
            onPressed: widget.onReconnect,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(widget.connectionError == null ? '重试连接' : '实时连接异常'),
          ),
      ],
    ),
  );
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const _SkeletonBox(width: 78, height: 78, radius: 999),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBox(width: 150, height: 28, radius: 12),
                SizedBox(height: 10),
                _SkeletonBox(width: 210, height: 14, radius: 8),
              ],
            ),
          ),
          const _SkeletonBox(width: 72, height: 36, radius: 999),
        ],
      ),
      const SizedBox(height: 16),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SkeletonBox(width: 92, height: 34, radius: 999),
          _SkeletonBox(width: 76, height: 34, radius: 999),
          _SkeletonBox(width: 76, height: 34, radius: 999),
        ],
      ),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(child: _SkeletonBox(height: 84, radius: 24)),
          SizedBox(width: 10),
          Expanded(child: _SkeletonBox(height: 84, radius: 24)),
          SizedBox(width: 10),
          Expanded(child: _SkeletonBox(height: 84, radius: 24)),
        ],
      ),
    ],
  );
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkeletonBox({this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        colors: [
          Colors.white.withValues(alpha: .72),
          Colors.white.withValues(alpha: .42),
          Colors.white.withValues(alpha: .72),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .86)),
    ),
  );
}

class _ProfileHero extends StatelessWidget {
  final UserSession session;
  final UserProfileSummary profile;
  final bool connected;
  final bool connecting;
  final VoidCallback onSignIn;
  final VoidCallback onSettings;
  final bool loading;
  const _ProfileHero({
    required this.session,
    required this.profile,
    required this.connected,
    required this.connecting,
    required this.onSignIn,
    required this.onSettings,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isNotEmpty
        ? profile.nickname
        : (session.nickname ?? '');
    final displayName = nickname.isNotEmpty ? nickname : session.username;
    final state = connected ? '实时在线' : (connecting ? '连接中' : '离线');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: BlinStyle.brandGradient,
                boxShadow: [BlinStyle.softShadow(.12)],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: profile.avatar.isNotEmpty
                    ? NetworkImage(profile.avatar)
                    : null,
                child: profile.avatar.isEmpty
                    ? Text(
                        displayName.isEmpty
                            ? 'B'
                            : displayName[0].toUpperCase(),
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 27,
                            height: 1.05,
                            letterSpacing: -.6,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: BlinStyle.blue.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Lv.1',
                          style: TextStyle(
                            color: BlinStyle.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'UID ${session.id}  |  $state',
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BlinStyle.softShadow(.06)],
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.settings_rounded,
                        size: 17,
                        color: BlinStyle.ink,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '设置',
                        style: TextStyle(
                          color: BlinStyle.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: '每日签到', value: '领积分', onTap: onSignIn),
            _InfoChip(label: '粉丝', value: loading ? '...' : profile.fans),
            _InfoChip(label: '关注', value: loading ? '...' : profile.follows),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : profile.points,
                label: '积分',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : profile.coins,
                label: '金币',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : profile.vip,
                label: '会员',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoChip({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: BlinStyle.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (onTap == null) return box;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: box,
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String value;
  final String label;
  const _HeroMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white, width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: BlinStyle.ink,
            fontSize: 25,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.play_arrow_rounded,
              size: 15,
              color: BlinStyle.muted,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ApiFeature {
  final String title;
  final IconData icon;
  final String path;
  final bool list;
  const _ApiFeature(this.title, this.icon, this.path, {this.list = true});
}

class _QuickCirclePanel extends StatelessWidget {
  final UserSession session;
  const _QuickCirclePanel({required this.session});

  void _open(BuildContext context, _ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ApiFeatureScreen(session: session, feature: feature),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = const [
      _ApiFeature('帖子', Icons.forum_rounded, '/get_posts_list'),
      _ApiFeature('粉丝', Icons.favorite_rounded, '/get_fan_list'),
      _ApiFeature('关注', Icons.person_add_alt_1_rounded, '/get_follow_list'),
      _ApiFeature('排行', Icons.emoji_events_rounded, '/ranking_list'),
      _ApiFeature('账单', Icons.receipt_long_rounded, '/get_user_billing'),
    ];
    return SoftCard(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  '经常访问',
                  style: TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '接口能力',
                style: TextStyle(
                  color: BlinStyle.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Icon(Icons.play_arrow_rounded, size: 16, color: BlinStyle.muted),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: items
                .map(
                  (e) => Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _open(context, e),
                      child: Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F7FA),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(e.icon, color: BlinStyle.ink, size: 25),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: BlinStyle.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FunctionGridPanel extends StatelessWidget {
  final UserSession session;
  const _FunctionGridPanel({required this.session});

  void _open(BuildContext context, _ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ApiFeatureScreen(session: session, feature: feature),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = const [
      _ApiFeature(
        '编辑资料',
        Icons.edit_note_rounded,
        '/modify_user_information',
        list: false,
      ),
      _ApiFeature(
        '上传头像',
        Icons.add_a_photo_outlined,
        '/upload_avatar',
        list: false,
      ),
      _ApiFeature(
        '上传背景',
        Icons.image_outlined,
        '/upload_background',
        list: false,
      ),
      _ApiFeature('我的帖子', Icons.article_outlined, '/get_posts_list'),
      _ApiFeature('点赞记录', Icons.thumb_up_alt_outlined, '/get_likes_records'),
      _ApiFeature('浏览历史', Icons.history_rounded, '/browse_history'),
      _ApiFeature('商品列表', Icons.storefront_outlined, '/product_list'),
      _ApiFeature('订单记录', Icons.receipt_long_outlined, '/get_order_record'),
      _ApiFeature(
        '会员卡密',
        Icons.card_membership_rounded,
        '/apply_direct_charge_km',
        list: false,
      ),
      _ApiFeature(
        '提现记录',
        Icons.account_balance_wallet_outlined,
        '/get_user_withdraw_cash_list',
      ),
    ];
    return SoftCard(
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 22),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 22,
          crossAxisSpacing: 4,
          childAspectRatio: .78,
        ),
        itemBuilder: (_, i) => InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(context, items[i]),
          child: Column(
            children: [
              Icon(items[i].icon, color: BlinStyle.ink, size: 31),
              const SizedBox(height: 9),
              Text(
                items[i].title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterfaceRecordPanel extends StatelessWidget {
  final UserProfileSummary profile;
  const _InterfaceRecordPanel({required this.profile});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('帖子', profile.posts),
      ('评论', profile.comments),
      ('点赞', profile.likes),
      ('浏览', profile.views),
    ];
    return SoftCard(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  '内容记录',
                  style: TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '已按接口保留',
                style: TextStyle(
                  color: BlinStyle.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        items[i].$2,
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 27,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        items[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BlinStyle.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != items.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  const _SettingsScreen({
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late ThemeMode themeMode;

  @override
  void initState() {
    super.initState();
    themeMode = widget.themeMode;
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  String get _themeLabel => switch (themeMode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '夜间',
    ThemeMode.system => '跟随系统',
  };

  Future<void> _checkUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在检测更新...')));
    try {
      final info = await const ApiService().getAppInfo();
      final updates = info['updates_info'];
      final updateMap = updates is Map ? Map<String, dynamic>.from(updates) : info;
      final latest = '${updateMap['update_version'] ?? ''}'.trim();
      final url = '${updateMap['update_url'] ?? ''}'.trim();
      final content = '${updateMap['update_content'] ?? ''}'.trim();
      if (!context.mounted) return;
      if (latest.isNotEmpty && latest != AppConfig.appVersion) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('发现新版本 $latest'),
            content: Text(content.isEmpty ? '有新版本可用。' : content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(url.isEmpty ? '后台未配置更新地址' : url)),
                  );
                },
                child: const Text('查看'),
              ),
            ],
          ),
        );
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('检测更新失败：$e')));
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    await widget.onLogout();
  }

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
                const Expanded(
                  child: Text(
                    '设置',
                    style: TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SoftCard(
              radius: 30,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.dark_mode_rounded,
                    title: '夜间模式',
                    subtitle: _themeLabel,
                    trailing: Switch(
                      value: themeMode == ThemeMode.dark,
                      onChanged: (v) => setThemeMode(
                        v ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.auto_mode_rounded,
                    title: '跟随系统',
                    subtitle: '自动适配系统深浅色',
                    trailing: Radio<ThemeMode>(
                      value: ThemeMode.system,
                      groupValue: themeMode,
                      onChanged: (v) {
                        if (v != null) setThemeMode(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              radius: 30,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.info_rounded,
                    title: '版本',
                    subtitle: AppConfig.appVersion,
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.system_update_alt_rounded,
                    title: '检测更新',
                    subtitle: '检查是否有新版本可用',
                    onTap: () => _checkUpdate(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              radius: 30,
              padding: const EdgeInsets.all(6),
              child: _SettingTile(
                icon: Icons.logout_rounded,
                title: '退出登录',
                subtitle: '退出当前账号并返回登录页',
                danger: true,
                onTap: () => _confirmLogout(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool danger;
  final VoidCallback? onTap;
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (danger ? Colors.red : BlinStyle.green).withValues(
                  alpha: .12,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: danger ? Colors.red : BlinStyle.ink,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? Colors.red : BlinStyle.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: BlinStyle.muted),
          ],
        ),
      ),
    ),
  );
}

class _ApiFeatureScreen extends StatefulWidget {
  final UserSession session;
  final _ApiFeature feature;
  const _ApiFeatureScreen({required this.session, required this.feature});

  @override
  State<_ApiFeatureScreen> createState() => _ApiFeatureScreenState();
}

class _ApiFeatureScreenState extends State<_ApiFeatureScreen> {
  final api = const ApiService();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? detail;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.feature.list) {
        final r = await api.getApiList(
          widget.session.token,
          widget.feature.path,
        );
        if (mounted) setState(() => rows = r);
      } else {
        if (mounted) {
          setState(
            () => detail = {
              '功能': widget.feature.title,
              '接口': widget.feature.path,
              '状态': '需要表单、文件或卡密参数，已预留入口',
            },
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
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
                  Expanded(
                    child: Text(
                      widget.feature.title,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading)
                const _ApiLoadingSkeleton()
              else if (error != null)
                SoftCard(
                  child: Text(
                    '加载失败：$error',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else if (widget.feature.list)
                _ApiRows(rows: rows)
              else
                _ApiDetail(detail: detail ?? const {}),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ApiLoadingSkeleton extends StatelessWidget {
  const _ApiLoadingSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      4,
      (i) => SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBox(width: i.isEven ? 180 : 130, height: 18, radius: 999),
            const SizedBox(height: 12),
            const _SkeletonBox(width: double.infinity, height: 12, radius: 999),
            const SizedBox(height: 8),
            _SkeletonBox(width: i.isEven ? 240 : 200, height: 12, radius: 999),
          ],
        ),
      ),
    ),
  );
}

class _ApiRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ApiRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SoftCard(
        child: Text(
          '暂无数据',
          style: TextStyle(color: BlinStyle.muted, fontWeight: FontWeight.w800),
        ),
      );
    }
    return Column(
      children: rows
          .map(
            (row) => SoftCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: _JsonPreview(data: row),
            ),
          )
          .toList(),
    );
  }
}

class _ApiDetail extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ApiDetail({required this.detail});

  @override
  Widget build(BuildContext context) =>
      SoftCard(child: _JsonPreview(data: detail));
}

class _JsonPreview extends StatelessWidget {
  final Map<String, dynamic> data;
  const _JsonPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.take(8).toList();
    if (entries.isEmpty) {
      return const Text('暂无字段', style: TextStyle(color: BlinStyle.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${e.value}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
