import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_config.dart';
import '../models/community.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
import '../services/message_alert_service.dart';
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
  final alerts = MessageAlertService();
  StreamSubscription? imSub;
  StreamSubscription? messageSub;
  Timer? unreadTimer;
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    im = ImService();
    unawaited(alerts.prepare());
    imSub = im.connectionChanges.listen((_) {
      if (mounted) setState(() {});
      unawaited(_refreshUnreadCount());
    });
    messageSub = im.messages.listen((message) {
      unawaited(_refreshUnreadCount());
      unawaited(alerts.notifyMessage(message));
    });
    unreadTimer = Timer.periodic(
      const Duration(seconds: 18),
      (_) => unawaited(_refreshUnreadCount()),
    );
    _connect();
    unawaited(_refreshUnreadCount());
  }

  Future<void> _connect() async {
    try {
      final info = await const ApiService().getImConnectInfo(
        widget.session.token,
      );
      await im.connect(info: info, myId: widget.session.id);
    } catch (e) {
      im.connectionError = '网络暂不可用';
      im.connecting = false;
      im.connected = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final list = await const ApiService().getMessageList(widget.session.token);
      final total = list.fold<int>(0, (sum, item) => sum + item.unread);
      if (mounted && total != unreadCount) setState(() => unreadCount = total);
    } catch (_) {
      // 商业界面不暴露未读数量同步失败，保留上一次稳定值。
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
    messageSub?.cancel();
    unreadTimer?.cancel();
    im.dispose();
    super.dispose();
  }

  String _formatBadge(int count) => count > 99 ? '99+' : '$count';

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
        child: ChatListScreen(
          session: widget.session,
          im: im,
          onUnreadChanged: (count) {
            if (mounted && unreadCount != count) {
              setState(() => unreadCount = count);
            }
          },
        ),
      ),
      _LazyTab(
        loaded: visitedTabs.contains(3),
        child: _MineTab(
          session: widget.session,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLogout: _logout,
          active: index == 3,
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
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(_formatBadge(unreadCount)),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(_formatBadge(unreadCount)),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: '消息',
          ),
          const NavigationDestination(
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
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  final bool active;
  const _MineTab({
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    required this.active,
  });

  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> with WidgetsBindingObserver {
  final api = const ApiService();
  UserProfileSummary profile = const UserProfileSummary();
  bool loadingProfile = true;
  bool hasLoadedProfile = false;
  String? profileError;
  Timer? profileSyncTimer;
  bool syncingProfile = false;
  DateTime? lastProfileSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadProfile();
    profileSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.active) unawaited(loadProfile(silent: true));
    });
  }

  @override
  void didUpdateWidget(covariant _MineTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      unawaited(loadProfile(silent: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(loadProfile(silent: true));
    }
  }

  @override
  void dispose() {
    profileSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _sameProfile(UserProfileSummary a, UserProfileSummary b) =>
      a.nickname == b.nickname &&
      a.avatar == b.avatar &&
      a.background == b.background &&
      a.fans == b.fans &&
      a.follows == b.follows &&
      a.points == b.points &&
      a.coins == b.coins &&
      a.vip == b.vip &&
      a.level == b.level &&
      a.posts == b.posts &&
      a.comments == b.comments &&
      a.likes == b.likes &&
      a.views == b.views;

  Future<void> loadProfile({bool silent = false}) async {
    if (silent && lastProfileSync != null) {
      final elapsed = DateTime.now().difference(lastProfileSync!);
      if (elapsed < const Duration(seconds: 8)) return;
    }
    if (syncingProfile) return;
    syncingProfile = true;
    if (!silent) {
      setState(() {
        loadingProfile = !hasLoadedProfile;
        profileError = null;
      });
    }
    try {
      final r = await api.getUserOtherInformation(widget.session.token);
      if (mounted) {
        final changed = !_sameProfile(profile, r);
        if (changed || !hasLoadedProfile || profileError != null) {
          setState(() {
            profile = r;
            hasLoadedProfile = true;
            profileError = null;
            lastProfileSync = DateTime.now();
          });
        } else {
          lastProfileSync = DateTime.now();
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => profileError = '$e');
    } finally {
      syncingProfile = false;
      if (mounted && !silent) setState(() => loadingProfile = false);
    }
  }

  Future<void> signIn() async {
    try {
      final msg = await api.userSignIn(widget.session.token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: (_) => _SignInRewardDialog(
          message: msg.isEmpty ? '今日奖励已到账' : msg,
        ),
      );
      await loadProfile();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException && e.message.trim().isNotEmpty
          ? e.message.trim()
          : '今日签到状态已同步';
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: (_) => _SignInRewardDialog(message: message),
      );
      await loadProfile();
    }
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsScreen(
          session: widget.session,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLogout: widget.onLogout,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(loadProfile(silent: true));
    });
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => loadProfile(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 48, 18, 22),
      children: [
        if (loadingProfile && !hasLoadedProfile)
          const _ProfileSkeleton()
        else
          _ProfileHero(
            session: widget.session,
            profile: profile,
            onSignIn: signIn,
            loading: false,
          ),
        if (profileError != null) ...[
          const SizedBox(height: 10),
          Text(
            '个人资料暂时无法更新，请稍后再试',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _QuickCirclePanel(session: widget.session),
        const SizedBox(height: 14),
        _FunctionGridPanel(session: widget.session, onSettings: openSettings),
        const SizedBox(height: 14),
        _InterfaceRecordPanel(profile: profile),
        const SizedBox(height: 2),
      ],
    ),
  );
}

class _SignInRewardDialog extends StatelessWidget {
  final String message;
  const _SignInRewardDialog({required this.message});

  bool get alreadySigned => message.contains('已') && message.contains('签');
  bool get syncIssue =>
      message.contains('暂时') ||
      message.contains('网络') ||
      message.contains('稍后') ||
      message.contains('未完成');
  String get title => syncIssue ? '签到提醒' : (alreadySigned ? '今日已签到' : '签到成功');
  String get buttonText => alreadySigned || syncIssue ? '知道了' : '开心收下';

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [BlinStyle.softShadow(.22)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RewardIllustration(),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: BlinStyle.softInk,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: BlinStyle.line),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFB547)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '每日一言：把今天过好，就是最稳定的成长。',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RewardIllustration extends StatelessWidget {
  const _RewardIllustration();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    height: 112,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                BlinStyle.green.withValues(alpha: .20),
                BlinStyle.cyan.withValues(alpha: .14),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 14,
          child: _SparkleDot(size: 10, color: BlinStyle.cyan),
        ),
        Positioned(
          top: 20,
          right: 18,
          child: _SparkleDot(size: 8, color: BlinStyle.purple),
        ),
        Positioned(
          bottom: 16,
          left: 24,
          child: _SparkleDot(size: 7, color: BlinStyle.green),
        ),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE59A), Color(0xFFFFB547), Color(0xFFFF8F3D)],
            ),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [BlinStyle.softShadow(.18)],
          ),
          child: const Icon(
            Icons.stars_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        Positioned(
          bottom: 10,
          right: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BlinStyle.softShadow(.10)],
            ),
            child: const Text(
              '+奖励',
              style: TextStyle(
                color: BlinStyle.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SparkleDot extends StatelessWidget {
  final double size;
  final Color color;
  const _SparkleDot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .85),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 14)],
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
  final VoidCallback onSignIn;
  final bool loading;
  const _ProfileHero({
    required this.session,
    required this.profile,
    required this.onSignIn,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isNotEmpty
        ? profile.nickname
        : (session.nickname ?? '');
    final displayName = nickname.isNotEmpty ? nickname : session.username;
    final isVip = profile.isVip;
    String valueOrZero(String value) {
      final v = value.trim();
      return v.isEmpty || v == '--' ? '0' : v;
    }
    final memberLabel = isVip ? 'VIP' : '未开通';
    String levelLabel() {
      final v = profile.level.trim();
      if (v.isEmpty || v == '--') return 'Lv.0';
      if (RegExp(r'^\d+$').hasMatch(v)) return 'Lv.$v';
      return v;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  padding: EdgeInsets.all(isVip ? 4 : 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isVip
                        ? const SweepGradient(
                            colors: [
                              Color(0xFFFFE8A3),
                              Color(0xFFFFB547),
                              Color(0xFF7C6CFF),
                              Color(0xFFFFE8A3),
                            ],
                          )
                        : null,
                    color: isVip ? null : Colors.white,
                    border: isVip
                        ? null
                        : Border.all(color: BlinStyle.line, width: 2),
                    boxShadow: [BlinStyle.softShadow(isVip ? .20 : .08)],
                  ),
                  child: Container(
                    padding: EdgeInsets.all(isVip ? 2 : 0),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
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
                ),
                if (isVip)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD66B), Color(0xFFFF9F1C)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BlinStyle.softShadow(.14)],
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
              ],
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
                            color: BlinStyle.softInk,
                            fontSize: 23,
                            height: 1.08,
                            letterSpacing: -.3,
                            fontWeight: FontWeight.w800,
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
                          color: BlinStyle.blue.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          levelLabel(),
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
                    'ID ${session.id}',
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [BlinStyle.softShadow(.06)],
              ),
              child: const Row(
                children: [
                  Text(
                    '主页',
                    style: TextStyle(
                      color: BlinStyle.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 16,
                    color: BlinStyle.muted,
                  ),
                ],
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
            _InfoChip(label: '粉丝', value: loading ? '...' : valueOrZero(profile.fans)),
            _InfoChip(label: '关注', value: loading ? '...' : valueOrZero(profile.follows)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : valueOrZero(profile.points),
                label: '积分',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : valueOrZero(profile.coins),
                label: '金币',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                value: loading ? '...' : memberLabel,
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
            fontSize: 20,
            height: 1.05,
            fontWeight: FontWeight.w800,
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
  final List<_ApiFormField> fields;
  const _ApiFeature(
    this.title,
    this.icon,
    this.path, {
    this.list = true,
    this.fields = const [],
  });
}

class _ApiFormField {
  final String key;
  final String label;
  final String hint;
  final bool required;
  final bool obscure;
  const _ApiFormField(
    this.key,
    this.label, {
    this.hint = '',
    this.required = false,
    this.obscure = false,
  });
}

class _QuickCirclePanel extends StatefulWidget {
  final UserSession session;
  const _QuickCirclePanel({required this.session});

  @override
  State<_QuickCirclePanel> createState() => _QuickCirclePanelState();
}

class _QuickCirclePanelState extends State<_QuickCirclePanel> {
  static const baseItems = [
    _ApiFeature('帖子', Icons.forum_rounded, '/get_posts_list'),
    _ApiFeature('粉丝', Icons.favorite_rounded, '/get_fan_list'),
    _ApiFeature('关注', Icons.person_add_alt_1_rounded, '/get_follow_list'),
    _ApiFeature('排行', Icons.emoji_events_rounded, '/ranking_list'),
    _ApiFeature('账单', Icons.receipt_long_rounded, '/get_user_billing'),
  ];
  Map<String, int> counts = const {};

  String get _prefsKey => 'mine_quick_access_${widget.session.id}';

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && mounted) {
        setState(
          () => counts = decoded.map(
            (key, value) => MapEntry('$key', int.tryParse('$value') ?? 0),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _recordAndOpen(BuildContext context, _ApiFeature feature) async {
    final next = Map<String, int>.from(counts);
    next[feature.path] = (next[feature.path] ?? 0) + 1;
    setState(() => counts = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next));
    if (!context.mounted) return;
    _open(context, feature);
  }

  void _open(BuildContext context, _ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ApiFeatureScreen(
          session: widget.session,
          feature: feature,
        ),
      ),
    );
  }

  List<_ApiFeature> get sortedItems {
    final items = [...baseItems];
    items.sort((a, b) {
      final diff = (counts[b.path] ?? 0).compareTo(counts[a.path] ?? 0);
      if (diff != 0) return diff;
      return baseItems.indexOf(a).compareTo(baseItems.indexOf(b));
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = sortedItems;
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
                '按习惯排序',
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
                      onTap: () => _recordAndOpen(context, e),
                      child: Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  BlinStyle.cyan.withValues(alpha: .18),
                                  BlinStyle.purple.withValues(alpha: .10),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .9),
                              ),
                            ),
                            child: Icon(
                              e.icon,
                              color: BlinStyle.softInk,
                              size: 24,
                            ),
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
  final VoidCallback onSettings;
  const _FunctionGridPanel({required this.session, required this.onSettings});

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
      _ApiFeature('我的资料', Icons.account_circle_outlined, '/get_user_other_information', list: false),
      _ApiFeature('我的帖子', Icons.article_outlined, '/get_posts_list'),
      _ApiFeature('收藏记录', Icons.bookmark_rounded, '/get_collection_records'),
      _ApiFeature('点赞记录', Icons.thumb_up_alt_outlined, '/get_likes_records'),
      _ApiFeature('浏览历史', Icons.history_rounded, '/browse_history'),
      _ApiFeature('粉丝列表', Icons.favorite_rounded, '/get_fan_list'),
      _ApiFeature('关注列表', Icons.person_add_alt_1_rounded, '/get_follow_list'),
      _ApiFeature('消息通知', Icons.notifications_rounded, '/get_message_notifications'),
      _ApiFeature('账单明细', Icons.receipt_long_rounded, '/get_user_billing'),
      _ApiFeature('提现记录', Icons.payments_rounded, '/get_user_withdraw_cash_list'),
      _ApiFeature('订单记录', Icons.shopping_bag_outlined, '/get_order_record'),
      _ApiFeature('商品列表', Icons.storefront_outlined, '/product_list'),
      _ApiFeature('我的应用', Icons.apps_rounded, '/get_user_apps_list'),
      _ApiFeature('我的徽章', Icons.verified_rounded, '/get_user_badge'),
      _ApiFeature('排行榜', Icons.emoji_events_rounded, '/ranking_list'),
      _ApiFeature('邀请排行', Icons.leaderboard_rounded, '/invitation_ranking'),
      _ApiFeature(
        '会员卡密',
        Icons.card_membership_rounded,
        '/apply_direct_charge_km',
        list: false,
        fields: [_ApiFormField('km', '会员卡密', hint: '输入卡密', required: true)],
      ),
      _ApiFeature(
        '申请提现',
        Icons.account_balance_wallet_rounded,
        '/user_withdraw_cash',
        list: false,
        fields: [
          _ApiFormField('money', '提现金额', required: true),
          _ApiFormField('account', '收款账号', required: true),
        ],
      ),
      _ApiFeature('设置', Icons.settings_rounded, '_settings', list: false),
    ];
    return SoftCard(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 6,
          mainAxisExtent: 78,
        ),
        itemBuilder: (_, i) => InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => items[i].path == '_settings'
              ? onSettings()
              : _open(context, items[i]),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      BlinStyle.green.withValues(alpha: .18),
                      BlinStyle.blue.withValues(alpha: .12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: .92)),
                  boxShadow: [BlinStyle.softShadow(.045)],
                ),
                child: Icon(items[i].icon, color: BlinStyle.softInk, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                items[i].title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.softInk,
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
  final UserSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  const _SettingsScreen({
    required this.session,
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

  void _openFeature(_ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ApiFeatureScreen(session: widget.session, feature: feature),
      ),
    );
  }

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
                    icon: Icons.edit_note_rounded,
                    title: '编辑个人资料',
                    subtitle: '昵称、头像、背景资料',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '编辑资料',
                        Icons.edit_note_rounded,
                        '/modify_user_information',
                        list: false,
                        fields: [
                          _ApiFormField('nickname', '昵称', hint: '输入新的昵称'),
                          _ApiFormField('qq', 'QQ', hint: '可选'),
                          _ApiFormField('email', '邮箱', hint: '可选'),
                          _ApiFormField('phone', '手机号', hint: '可选'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.add_a_photo_outlined,
                    title: '更换头像',
                    subtitle: '上传头像地址或图片路径',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '上传头像',
                        Icons.add_a_photo_outlined,
                        '/upload_avatar',
                        list: false,
                        fields: [_ApiFormField('avatar', '头像地址', hint: '图片 URL 或后台返回路径', required: true)],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.image_outlined,
                    title: '更换主页背景',
                    subtitle: '设置个人主页背景图',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '上传背景',
                        Icons.image_outlined,
                        '/upload_background',
                        list: false,
                        fields: [_ApiFormField('background', '背景地址', hint: '图片 URL 或后台返回路径', required: true)],
                      ),
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
                    icon: Icons.lock_reset_rounded,
                    title: '修改密码',
                    subtitle: '更新当前账号登录密码',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '修改密码',
                        Icons.lock_reset_rounded,
                        '/change_password',
                        list: false,
                        fields: [
                          _ApiFormField('old_password', '原密码', obscure: true, required: true),
                          _ApiFormField('new_password', '新密码', obscure: true, required: true),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.link_rounded,
                    title: 'QQ 绑定',
                    subtitle: '绑定 QQ 账号',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '绑定QQ',
                        Icons.link_rounded,
                        '/bind_qq',
                        list: false,
                        fields: [_ApiFormField('qq', 'QQ 号', required: true)],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.link_off_rounded,
                    title: '解绑 QQ',
                    subtitle: '解除当前 QQ 绑定',
                    onTap: () => _openFeature(
                      const _ApiFeature('解绑QQ', Icons.link_off_rounded, '/unbind_qq', list: false),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.email_outlined,
                    title: '修改邮箱',
                    subtitle: '更新账号邮箱',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '修改邮箱',
                        Icons.email_outlined,
                        '/modify_user_email',
                        list: false,
                        fields: [
                          _ApiFormField('email', '新邮箱', required: true),
                          _ApiFormField('code', '验证码', hint: '邮箱验证码'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.phone_android_rounded,
                    title: '修改手机',
                    subtitle: '更新账号手机号',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '修改手机',
                        Icons.phone_android_rounded,
                        '/modify_user_phone',
                        list: false,
                        fields: [
                          _ApiFormField('phone', '新手机号', required: true),
                          _ApiFormField('code', '验证码', hint: '短信验证码'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  _SettingTile(
                    icon: Icons.card_giftcard_rounded,
                    title: '填写邀请码',
                    subtitle: '绑定邀请关系',
                    onTap: () => _openFeature(
                      const _ApiFeature(
                        '填写邀请码',
                        Icons.card_giftcard_rounded,
                        '/fill_invitation_code',
                        list: false,
                        fields: [_ApiFormField('invitation_code', '邀请码', required: true)],
                      ),
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
  late final Map<String, TextEditingController> controllers;
  bool submitting = false;
  int page = 1;
  bool loadingMore = false;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final field in widget.feature.fields) field.key: TextEditingController(),
    };
    load();
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      page = 1;
      hasMore = true;
    });
    try {
      if (widget.feature.list) {
        final r = await api.getApiList(
          widget.session.token,
          widget.feature.path,
          extra: const {'page': 1, 'limit': 20},
        );
        if (mounted) {
          setState(() {
            rows = r;
            hasMore = r.length >= 20;
          });
        }
      } else if (widget.feature.fields.isEmpty && widget.feature.path.startsWith('/get_')) {
        final r = await api.getApiData(
          widget.session.token,
          widget.feature.path,
        );
        if (mounted) setState(() => detail = r);
      } else {
        if (mounted) setState(() => detail = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (!widget.feature.list || loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final nextPage = page + 1;
      final r = await api.getApiList(
        widget.session.token,
        widget.feature.path,
        extra: {'page': nextPage, 'limit': 20},
      );
      if (!mounted) return;
      setState(() {
        page = nextPage;
        rows = [...rows, ...r];
        hasMore = r.length >= 20;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更多内容暂时无法加载，请稍后再试')),
      );
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> submitForm() async {
    final extra = <String, dynamic>{};
    for (final field in widget.feature.fields) {
      final value = controllers[field.key]?.text.trim() ?? '';
      if (field.required && value.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请填写${field.label}')),
        );
        return;
      }
      if (value.isNotEmpty) extra[field.key] = value;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final r = await api.getApiData(
        widget.session.token,
        widget.feature.path,
        extra: extra,
      );
      if (!mounted) return;
      setState(() => detail = r);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.feature.title}已提交')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.feature.title}暂时无法完成，请稍后再试')),
      );
    } finally {
      if (mounted) setState(() => submitting = false);
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
                    '内容暂时无法加载，请稍后再试',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else if (widget.feature.list) ...[
                _ApiRows(rows: rows),
                if (hasMore) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: loadingMore ? null : loadMore,
                      icon: loadingMore
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(loadingMore ? '加载中...' : '加载更多'),
                    ),
                  ),
                ],
              ]
              else
                _ApiFormPanel(
                  feature: widget.feature,
                  controllers: controllers,
                  detail: detail,
                  submitting: submitting,
                  onSubmit: submitForm,
                ),
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

  String _pick(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return '';
  }

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
          .map((row) {
            final title = _pick(row, const [
              'title',
              'name',
              'nickname',
              'username',
              'content',
              'remark',
              'message',
              'goods_name',
              'product_name',
              'app_name',
              'badge_name',
              'order_no',
              'trade_no',
              'id',
            ]);
            final subtitle = _pick(row, const [
              'desc',
              'description',
              'summary',
              'text',
              'type',
              'category',
              'status_text',
              'status',
              'created_at',
              'create_time',
              'time',
            ]);
            final amount = _pick(row, const [
              'money',
              'amount',
              'price',
              'coin',
              'coins',
              'integral',
              'score',
              'balance',
            ]);
            final time = _pick(row, const [
              'created_at',
              'create_time',
              'addtime',
              'pay_time',
              'time',
              'updated_at',
            ]);
            return SoftCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: BlinStyle.green.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.widgets_rounded, color: BlinStyle.ink, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? '记录详情' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: BlinStyle.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (time.isNotEmpty && time != subtitle) ...[
                          const SizedBox(height: 8),
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
                  if (amount.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      amount,
                      style: const TextStyle(
                        color: BlinStyle.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            );
          })
          .toList(),
    );
  }
}

class _ApiFormPanel extends StatelessWidget {
  final _ApiFeature feature;
  final Map<String, TextEditingController> controllers;
  final Map<String, dynamic>? detail;
  final bool submitting;
  final Future<void> Function() onSubmit;
  const _ApiFormPanel({
    required this.feature,
    required this.controllers,
    required this.detail,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasForm = feature.fields.isNotEmpty || !feature.path.startsWith('/get_');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasForm)
          SoftCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  feature.fields.isEmpty ? '确认执行${feature.title}' : '填写${feature.title}信息',
                  style: const TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...feature.fields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[field.key],
                      obscureText: field.obscure,
                      decoration: InputDecoration(
                        labelText: field.required ? '${field.label} *' : field.label,
                        hintText: field.hint.isEmpty ? null : field.hint,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .72),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: BlinStyle.line),
                        ),
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done_rounded),
                  label: Text(submitting ? '提交中...' : '提交'),
                ),
              ],
            ),
          ),
        if (detail != null) SoftCard(child: _ApiDetailCard(data: detail!)),
        if (!hasForm && detail == null)
          const SoftCard(
            child: Text(
              '暂无数据',
              style: TextStyle(color: BlinStyle.muted, fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

class _ApiDetailCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ApiDetailCard({required this.data});

  static const _labels = {
    'id': 'ID',
    'uid': '用户ID',
    'user_id': '用户ID',
    'nickname': '昵称',
    'username': '账号',
    'name': '名称',
    'title': '标题',
    'content': '内容',
    'email': '邮箱',
    'phone': '手机',
    'qq': 'QQ',
    'money': '金额',
    'amount': '金额',
    'balance': '余额',
    'coin': '金币',
    'coins': '金币',
    'integral': '积分',
    'score': '积分',
    'status': '状态',
    'msg': '提示',
    'message': '消息',
    'created_at': '创建时间',
    'create_time': '创建时间',
    'updated_at': '更新时间',
    'time': '时间',
  };

  String _label(String key) => _labels[key] ?? key.replaceAll('_', ' ');

  String _value(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return value.entries
          .map((e) => '${_label('${e.key}')}: ${_value(e.value)}')
          .where((e) => e.trim().isNotEmpty)
          .join('  ');
    }
    if (value is List) return value.isEmpty ? '暂无' : value.map(_value).join('、');
    final text = '$value'.trim();
    if (text == 'null' || text.isEmpty) return '';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries
        .map((e) => MapEntry(e.key, _value(e.value)))
        .where((e) => e.value.isNotEmpty)
        .take(12)
        .toList();
    if (entries.isEmpty) {
      return const Text(
        '操作已完成',
        style: TextStyle(color: BlinStyle.ink, fontWeight: FontWeight.w900),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '详情',
          style: TextStyle(
            color: BlinStyle.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ...entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _label(e.key),
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
                    e.value,
                    maxLines: 3,
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
        ),
      ],
    );
  }
}
