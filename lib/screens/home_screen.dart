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

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Feed(
        session: widget.session,
        onLogout: widget.onLogout,
        connected: im.connected,
        connecting: im.connecting,
        connectionError: im.connectionError,
        onReconnect: _connect,
      ),
      ChatListScreen(session: widget.session, im: im),
      _Discover(),
    ];
    return Scaffold(
      body: GradientShell(child: SafeArea(child: pages[index])),
      bottomNavigationBar: NavigationBar(
        height: 70,
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '社区',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: '消息',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  final UserSession session;
  final VoidCallback onLogout;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;
  const _Feed({
    required this.session,
    required this.onLogout,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
  });
  @override
  Widget build(BuildContext context) {
    final posts = [
      CommunityPost(
        id: 1,
        author: '春色园社区',
        avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
        title: '实时 IM 已接入 Flutter',
        content: '现在社区消息、历史消息和实时长连接都统一为 im_payload 结构，安卓、网页和 iOS 代码共用一套渲染。',
        image:
            'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=1200',
        likes: 128,
        comments: 36,
        time: '刚刚',
      ),
      CommunityPost(
        id: 2,
        author: 'Blinlin Lab',
        avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
        title: '社区 UI 进入玻璃拟态时代',
        content: '柔和渐变、漂浮卡片、强对比行动按钮，给移动端和 Web 端同样清晰的现代体验。',
        image:
            'https://images.unsplash.com/photo-1557683316-973673baf926?w=1200',
        likes: 86,
        comments: 19,
        time: '10分钟前',
      ),
      CommunityPost(
        id: 3,
        author: session.username,
        avatar: 'http://139.196.166.181/static/images/initial_photo/user.png',
        title: '欢迎回来，${session.username}',
        content: '点击底部消息，可以加载会话列表、打开历史消息，并通过悟空 IM 实时收到对方消息。',
        likes: 42,
        comments: 8,
        time: '今天',
      ),
    ];
    final statusText = connected
        ? 'IM 已连接，实时在线'
        : (connecting
              ? 'IM 连接中...'
              : (connectionError == null ? 'IM 未连接' : connectionError!));
    final statusColor = connected
        ? Colors.green.shade700
        : (connecting ? Colors.orange.shade700 : Colors.red.shade700);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blinlin 社区',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                        ),
                      ),
                      Text(
                        statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!connected && !connecting)
                        TextButton.icon(
                          onPressed: onReconnect,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重试 IM 连接'),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    await AuthStore().clear();
                    onLogout();
                  },
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: ['推荐', '关注', '同城', '技术', '旅行']
                  .map(
                    (e) => Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: e == '推荐'
                            ? const Color(0xFF101828)
                            : Colors.white.withOpacity(.75),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        e,
                        style: TextStyle(
                          color: e == '推荐' ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (c, i) => PostCard(post: posts[i]),
            childCount: posts.length,
          ),
        ),
      ],
    );
  }
}

class _Discover extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.all(28),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.75),
        borderRadius: BorderRadius.circular(32),
      ),
      child: const Text(
        '发现页预留：话题、圈子、附近的人、系统通知。',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
