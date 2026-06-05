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
    padding: const EdgeInsets.fromLTRB(18, 48, 18, 22),
    children: [
      _ProfileHero(
        session: session,
        connected: connected,
        connecting: connecting,
      ),
      const SizedBox(height: 16),
      const _QuickCirclePanel(),
      const SizedBox(height: 14),
      const _FunctionGridPanel(),
      const SizedBox(height: 14),
      const _InterfaceRecordPanel(),
      const SizedBox(height: 14),
      if (!connected && !connecting)
        OutlinedButton.icon(
          onPressed: onReconnect,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(connectionError == null ? '重试连接' : '实时连接异常'),
        ),
      FilledButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('退出登录'),
      ),
    ],
  );
}

class _ProfileHero extends StatelessWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  const _ProfileHero({
    required this.session,
    required this.connected,
    required this.connecting,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = session.nickname ?? '';
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
                child: Text(
                  displayName.isEmpty ? 'B' : displayName[0].toUpperCase(),
                  style: const TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: '每日签到', value: '领积分'),
            _InfoChip(label: '粉丝', value: '--'),
            _InfoChip(label: '关注', value: '--'),
          ],
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(
              child: _HeroMetric(value: '--', label: '积分'),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(value: '--', label: '金币'),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(value: '--', label: '会员'),
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
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
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

class _QuickCirclePanel extends StatelessWidget {
  const _QuickCirclePanel();

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('帖子', Icons.forum_rounded),
      ('粉丝', Icons.favorite_rounded),
      ('关注', Icons.person_add_alt_1_rounded),
      ('排行', Icons.emoji_events_rounded),
      ('账单', Icons.receipt_long_rounded),
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
                    child: Column(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(e.$2, color: BlinStyle.ink, size: 25),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          e.$1,
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
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FunctionGridPanel extends StatelessWidget {
  const _FunctionGridPanel();

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('编辑资料', Icons.edit_note_rounded),
      ('上传头像', Icons.add_a_photo_outlined),
      ('上传背景', Icons.image_outlined),
      ('我的帖子', Icons.article_outlined),
      ('点赞记录', Icons.thumb_up_alt_outlined),
      ('浏览历史', Icons.history_rounded),
      ('商品列表', Icons.storefront_outlined),
      ('订单记录', Icons.receipt_long_outlined),
      ('会员卡密', Icons.card_membership_rounded),
      ('提现记录', Icons.account_balance_wallet_outlined),
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
        itemBuilder: (_, i) => Column(
          children: [
            Icon(items[i].$2, color: BlinStyle.ink, size: 31),
            const SizedBox(height: 9),
            Text(
              items[i].$1,
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
    );
  }
}

class _InterfaceRecordPanel extends StatelessWidget {
  const _InterfaceRecordPanel();

  @override
  Widget build(BuildContext context) {
    final items = const ['帖子', '评论', '点赞', '浏览'];
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
                        '--',
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontSize: 27,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        items[i],
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
