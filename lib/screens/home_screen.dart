import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../core/app_config.dart';
import '../models/community.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../services/im_service.dart';
import '../services/client_device_context.dart';
import '../services/message_alert_service.dart';
import '../widgets/blin_style.dart';
import '../widgets/post_card.dart';
import 'chat_list_screen.dart';
import 'call_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int index = 0;
  final visitedTabs = <int>{0};
  late final ImService im;
  final alerts = MessageAlertService();
  StreamSubscription? imSub;
  StreamSubscription? messageSub;
  StreamSubscription? callSub;
  final Map<String, List<Map<String, dynamic>>> pendingCallSignals = {};
  Timer? unreadTimer;
  Timer? reconnectTimer;
  Timer? healthTimer;
  Timer? onlineHeartbeatTimer;
  bool reconnecting = false;
  int unreadCount = 0;
  final Set<String> openingCallIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    im = ImService();
    unawaited(alerts.prepare());
    imSub = im.connectionChanges.listen((_) {
      if (mounted) setState(() {});
      if (!im.connected && !im.connecting) scheduleReconnect();
      unawaited(_refreshUnreadCount());
    });
    messageSub = im.messages.listen((message) {
      unawaited(_refreshUnreadCount());
      unawaited(alerts.notifyMessage(message));
    });
    callSub = im.calls.listen((payload) {
      final content = payload['content'];
      final rawAction = content is Map
          ? '${content['action'] ?? content['type'] ?? ''}'
          : '';
      final action = switch (rawAction) {
        'call_invite' => 'invite',
        'call_offer' => 'offer',
        'call_accept' => 'accept',
        'call_answer' => 'answer',
        'call_ice' => 'ice',
        'call_hangup' => 'hangup',
        'call_reject' => 'reject',
        'call_ack' => 'ack',
        _ => rawAction,
      };
      if (action == 'invite' || action == 'offer') {
        unawaited(
          alerts.notifyCall(
            title: '搭个话来电',
            body:
                '${content is Map ? content['nickname'] ?? '有人' : '有人'}邀请你${content is Map && content['media'] == 'video' ? '视频' : '语音'}通话',
          ),
        );
        unawaited(_openIncomingCall(payload));
      } else if (content is Map) {
        final callId = '${content['call_id'] ?? payload['call_id'] ?? ''}'.trim();
        if (callId.isNotEmpty) {
          pendingCallSignals.putIfAbsent(callId, () => <Map<String, dynamic>>[]).add(
                Map<String, dynamic>.from(payload),
              );
        }
      }
    });
    unreadTimer = Timer.periodic(
      const Duration(seconds: 18),
      (_) => unawaited(_refreshUnreadCount()),
    );
    healthTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_checkImHealth()),
    );
    onlineHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_reportOnlineHeartbeat()),
    );
    _connect();
    unawaited(_refreshUnreadCount());
  }

  Future<void> _openIncomingCall(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final content = payload['content'];
    if (content is! Map) return;
    final fromId =
        int.tryParse(
          '${payload['from_user_id'] ?? content['from_user_id'] ?? 0}',
        ) ??
        0;
    if (fromId <= 0 || fromId == widget.session.id) return;
    final callId = '${content['call_id'] ?? payload['call_id'] ?? ''}'.trim();
    final openKey = callId.isNotEmpty
        ? callId
        : '${fromId}_${content['media'] ?? ''}_${content['create_time'] ?? payload['client_msg_no'] ?? ''}';
    if (openingCallIds.contains(openKey)) return;
    openingCallIds.add(openKey);
    final video = '${content['media']}' == 'video';
    final peerName = '${content['nickname'] ?? content['name'] ?? '用户$fromId'}';
    if (!mounted) return;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            session: widget.session,
            im: im,
            peerId: fromId,
            peerName: peerName,
            video: video,
            incoming: true,
            initialSignal: payload,
              initialSignals: pendingCallSignals.remove(openKey) ?? const <Map<String, dynamic>>[],
          ),
        ),
      );
    } finally {
      openingCallIds.remove(openKey);
    }
  }

  Future<void> _connect() async {
    if (reconnecting || im.connecting) return;
    reconnecting = true;
    reconnectTimer?.cancel();
    try {
      try {
        await im.disconnect();
      } catch (_) {}
      final info = await const ApiService().getImConnectInfo(
        widget.session.token,
      );
      await im.connect(info: info, myId: widget.session.id);
      unawaited(_reportOnlineHeartbeat());
      unawaited(_broadcastOwnPresence());
    } catch (e) {
      im.connectionError = '网络暂不可用，正在重试';
      im.connecting = false;
      im.connected = false;
      if (mounted) setState(() {});
      scheduleReconnect();
    } finally {
      reconnecting = false;
    }
  }

  Future<void> _reportOnlineHeartbeat({bool online = true}) async {
    try {
      await const ApiService().reportImOnlineHeartbeat(
        token: widget.session.token,
        online: online,
      );
      if (online) unawaited(_broadcastOwnPresence());
    } catch (_) {}
  }

  Future<void> _broadcastOwnPresence() async {
    if (!im.connected || !im.isSocketConnected) return;
    try {
      final friends = await const ApiService().getFriends(widget.session.token);
      final device = ClientDeviceContext.current();
      final now = DateTime.now().toIso8601String();
      for (final friend in friends.take(100)) {
        final payload = {
          'msg_type': 'presence',
          'client_msg_no': 'presence_${widget.session.id}_${friend.id}_${DateTime.now().microsecondsSinceEpoch}',
          'from_user_id': widget.session.id,
          'to_user_id': friend.id,
          'from_uid': ImService.uidForUser(widget.session.id),
          'to_uid': ImService.uidForUser(friend.id),
          'uid': ImService.uidForUser(widget.session.id),
          'user_id': widget.session.id,
          'online': true,
          'event': 'online',
          'time': now,
          ...device.toApiFields(),
        };
        try {
          await im.sendDirect(
            channelId: ImService.uidForUser(friend.id),
            payload: payload,
          ).timeout(const Duration(milliseconds: 800));
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _checkImHealth() async {
    if (!mounted || reconnecting || im.connecting) return;
    if (!im.connected || !im.isSocketConnected) {
      await _connect();
    }
  }

  void scheduleReconnect() {
    if (!mounted || reconnectTimer?.isActive == true || im.connecting) return;
    reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !im.connected) unawaited(_connect());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reportOnlineHeartbeat());
      unawaited(_checkImHealth());
      unawaited(_refreshUnreadCount());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_reportOnlineHeartbeat(online: false));
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final list = await const ApiService().getMessageList(
        widget.session.token,
      );
      final total = list.fold<int>(0, (sum, item) => sum + item.unread);
      if (mounted && total != unreadCount) setState(() => unreadCount = total);
    } catch (_) {
      // 商业界面不暴露未读数量同步失败，保留上一次稳定值。
    }
  }

  Future<void> _logout() async {
    await _reportOnlineHeartbeat(online: false);
    await im.disconnect();
    await AuthStore().clear();
    widget.onLogout();
  }

  @override
  void dispose() {
    imSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    reconnectTimer?.cancel();
    healthTimer?.cancel();
    onlineHeartbeatTimer?.cancel();
    unawaited(_reportOnlineHeartbeat(online: false));
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
  Widget build(BuildContext context) =>
      loaded ? child : const SizedBox.expand();
}

class _FeedTab extends StatefulWidget {
  final UserSession session;
  final bool connected;
  final bool connecting;
  const _FeedTab({
    required this.session,
    required this.connected,
    required this.connecting,
  });

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  final api = const ApiService();
  bool loading = true;
  List<CommunityPost> posts = [];
  List<Map<String, dynamic>> sections = [];
  List<String> hotKeywords = [];
  String selectedSectionId = '';

  @override
  void initState() {
    super.initState();
    unawaited(load());
    unawaited(loadHotKeywords());
  }

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  int _int(Map<String, dynamic> row, List<String> keys) {
    final value = _pick(row, keys, '0');
    return int.tryParse(value) ?? 0;
  }

  List<String> _images(Map<String, dynamic> row) {
    final out = <String>[];
    void add(dynamic value) {
      final text = '$value'.trim();
      if (text.startsWith('http') && !out.contains(text)) out.add(text);
    }

    for (final key in const [
      'img_url',
      'picture_arr',
      'network_picture',
      'images',
      'image_arr',
      'img_url_array',
    ]) {
      final value = row[key];
      if (value is List) {
        for (final item in value) add(item);
      } else if (value is String) {
        final text = value.trim();
        if (text.startsWith('[')) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is List) {
              for (final item in decoded) add(item);
            }
          } catch (_) {}
        } else if (text.contains(',')) {
          for (final item in text.split(',')) add(item);
        } else {
          add(text);
        }
      }
    }

    for (final key in const ['cover', 'picture', 'image']) {
      add(row[key]);
    }
    return out;
  }

  // 图片列表从 img_url / picture_arr 等真实后端字段解析。

  CommunityPost _postFromRow(Map<String, dynamic> row) {
    final id = int.tryParse(_pick(row, const ['id', 'postid'], '0')) ?? 0;
    final images = _images(row);
    return CommunityPost(
      id: id,
      author: _pick(row, const [
        'nickname',
        'username',
        'author',
        'name',
      ], '社区用户'),
      avatar: _pick(row, const [
        'usertx',
        'avatar',
        'user_avatar',
        'headimg',
      ], 'http://139.196.166.181/static/images/initial_photo/user.png'),
      title: _pick(row, const ['title', 'post_title', 'name'], '社区动态'),
      content: _pick(row, const [
        'content',
        'post_content',
        'text',
        'summary',
        'description',
      ]),
      image: images.isEmpty ? null : images.first,
      images: images,
      videoUrl: _pick(row, const ['video_url', 'video', 'videoUrl']),
      videoCover: _pick(row, const [
        'video_img',
        'video_cover',
        'video_image',
        'cover',
      ]),
      likes: _int(row, const [
        'thumbs',
        'likes',
        'like_count',
        'likes_count',
        'like_num',
        'give_like_num',
      ]),
      comments: _int(row, const [
        'comment',
        'comments',
        'comment_count',
        'comments_count',
        'comment_num',
      ]),
      views: _int(row, const ['view', 'views', 'view_count', 'browse_count']),
      sectionName: _pick(row, const [
        'section_name',
        'sub_section_name',
        'forum_name',
        'plate_name',
      ]),
      hierarchy: _pick(row, const ['hierarchy', 'level', 'user_level']),
      location: _pick(row, const ['ip_address', 'address', 'location']),
      time: _pick(row, const [
        'create_time_ago',
        'time_ago',
        'create_time',
        'created_at',
        'time',
      ], '刚刚'),
      raw: row,
    );
  }

  List<Map<String, dynamic>> _sectionsFromPosts(
    List<Map<String, dynamic>> rows,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = _pick(row, const [
        'sectionid',
        'section_id',
        'fid',
        'plate_id',
      ]);
      final name = _pick(row, const [
        'section_name',
        'forum_name',
        'plate_name',
      ]);
      if (id.isEmpty || name.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add({'id': id, 'section_name': name});
    }
    return out;
  }

  Future<void> loadHotKeywords() async {
    final words = await api.getSearchKeywords(limit: 6);
    if (!mounted) return;
    setState(() => hotKeywords = words);
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final rows = await api.getForumPosts(
        widget.session.token,
        page: 1,
        limit: 10,
        sectionId: selectedSectionId,
      );
      List<Map<String, dynamic>> sectionRows = sections;
      try {
        sectionRows = await api.getSectionList(widget.session.token);
      } catch (_) {
        // 板块接口异常不影响首页帖子流展示。
      }
      if (sectionRows.isEmpty) sectionRows = _sectionsFromPosts(rows);
      if (!mounted) return;
      setState(() {
        posts = rows.map(_postFromRow).toList();
        sections = sectionRows;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => posts = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showSignInDialog(
    String title,
    String message, {
    bool success = true,
  }) async {
    final quote = DateTime.now().weekday % 2 == 0
        ? '今天也要好好搭话，别把生活过成静音。'
        : '把一句问候发出去，关系就会多一个入口。';
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFBF0), Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD166), Color(0xFFFF8A65)],
                  ),
                ),
                child: Icon(
                  success ? Icons.wb_sunny_rounded : Icons.info_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3D7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '每日一言：$quote',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8A5A00),
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: BlinStyle.ink,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInFromHome() async {
    try {
      final msg = await api.userSignIn(widget.session.token);
      if (!mounted) return;
      await _showSignInDialog('签到完成', msg, success: true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException && e.message.trim().isNotEmpty
          ? e.message.trim()
          : '今日签到状态同步失败，请稍后再试。';
      await _showSignInDialog('签到提醒', message, success: false);
    }
  }

  void _openPublish() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _PublishPostScreen(session: widget.session, sections: sections),
      ),
    ).then((_) => unawaited(load()));
  }

  void _openPost(CommunityPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PostDetailScreen(post: post, session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _FeedHero(
              connected: widget.connected,
              connecting: widget.connecting,
              postCount: posts.length,
              sections: sections,
              selectedSectionId: selectedSectionId,
              hotKeywords: hotKeywords,
              onSectionSelected: (id) {
                setState(() => selectedSectionId = id);
                unawaited(load());
              },
              onSignIn: () => unawaited(_signInFromHome()),
              onPublish: _openPublish,
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: _ApiLoadingSkeleton(),
              ),
            )
          else if (posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: SoftCard(
                  child: Text(
                    '社区暂时还没有新动态，刷新后会同步后台真实帖子',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: PostCard(
                    post: posts[i],
                    featured: i == 0,
                    onTap: () => _openPost(posts[i]),
                  ),
                ),
                childCount: posts.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
        ],
      ),
    );
  }
}

class _PublishPostScreen extends StatefulWidget {
  final UserSession session;
  final List<Map<String, dynamic>> sections;
  const _PublishPostScreen({required this.session, required this.sections});

  @override
  State<_PublishPostScreen> createState() => _PublishPostScreenState();
}

class _PublishPostScreenState extends State<_PublishPostScreen> {
  final api = const ApiService();
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final videoController = TextEditingController();
  final videoCoverController = TextEditingController();
  String sectionId = '';
  String subsectionId = '';
  bool submitting = false;

  List<Map<String, dynamic>> get publishSections {
    final out = <Map<String, dynamic>>[];
    for (final row in widget.sections) {
      final children = row['sub_section'];
      if (children is List && children.isNotEmpty) {
        for (final child in children) {
          if (child is Map) {
            final item = Map<String, dynamic>.from(child);
            item['_parent_id'] = row['id'];
            item['_parent_name'] = _pick(row, const [
              'section_name',
              'name',
            ], '一级板块');
            item['_is_sub_section'] = true;
            out.add(item);
          }
        }
      } else {
        final item = Map<String, dynamic>.from(row);
        item['_is_sub_section'] = false;
        out.add(item);
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    titleController.addListener(() {
      if (mounted) setState(() {});
    });
    videoController.addListener(() {
      if (mounted) setState(() {});
    });
    videoCoverController.addListener(() {
      if (mounted) setState(() {});
    });
    if (publishSections.isNotEmpty) {
      final first = publishSections.first;
      if (first['_is_sub_section'] == true) {
        sectionId = '${first['_parent_id'] ?? ''}';
        subsectionId = '${first['id'] ?? ''}';
      } else {
        sectionId = '${first['id'] ?? ''}';
        subsectionId = '';
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    videoController.dispose();
    videoCoverController.dispose();
    super.dispose();
  }

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  Future<void> submit() async {
    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (submitting || title.isEmpty || content.isEmpty || sectionId.isEmpty) {
      await _showPrettyDialog(
        context,
        title: '还不能发布',
        message: '请选择板块，并填写标题和内容。',
        icon: Icons.info_rounded,
      );
      return;
    }
    setState(() => submitting = true);
    try {
      final msg = await api.publishPost(
        widget.session.token,
        sectionId: sectionId,
        subsectionId: subsectionId,
        title: title,
        content: content,
        video: videoController.text,
        videoCover: videoCoverController.text,
      );
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '发布成功',
        message: msg,
        icon: Icons.check_circle_rounded,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        await _showPrettyDialog(
          context,
          title: '发布失败',
          message: '$e',
          icon: Icons.info_rounded,
        );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openSectionPicker() async {
    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              '选择圈子',
              style: TextStyle(
                color: BlinStyle.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final row in publishSections)
              Builder(
                builder: (_) {
                  final isSub = row['_is_sub_section'] == true;
                  final targetSectionId = isSub
                      ? '${row['_parent_id'] ?? ''}'
                      : '${row['id'] ?? ''}';
                  final targetSubsectionId = isSub ? '${row['id'] ?? ''}' : '';
                  final active =
                      targetSectionId == sectionId &&
                      targetSubsectionId == subsectionId;
                  final name = _pick(row, const ['section_name', 'name'], '圈子');
                  final parentName = '${row['_parent_name'] ?? ''}'.trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isSub
                          ? Icons.subdirectory_arrow_right_rounded
                          : Icons.tag_faces_rounded,
                      color: isSub ? BlinStyle.blue : BlinStyle.green,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: BlinStyle.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      isSub
                          ? '$parentName 下的二级板块 · ID ${row['id'] ?? '--'}'
                          : '一级板块 · 可直接发帖 · ID ${row['id'] ?? '--'}',
                      style: const TextStyle(color: BlinStyle.muted),
                    ),
                    trailing: active
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: BlinStyle.green,
                          )
                        : const Icon(
                            Icons.circle_outlined,
                            color: Color(0xFFE5E8EF),
                          ),
                    onTap: () => Navigator.pop(context, {
                      'sectionId': targetSectionId,
                      'subsectionId': targetSubsectionId,
                    }),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        sectionId = selected['sectionId'] ?? '';
        subsectionId = selected['subsectionId'] ?? '';
      });
    }
  }

  Future<void> _openVideoEditor() async {
    final video = TextEditingController(text: videoController.text);
    final cover = TextEditingController(text: videoCoverController.text);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '添加视频',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: video,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '视频链接',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cover,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '视频封面链接',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  videoController.text = video.text;
                  videoCoverController.text = cover.text;
                  if (mounted) setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      ),
    );
    video.dispose();
    cover.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final row in publishSections) {
      final rowSectionId = row['_is_sub_section'] == true
          ? '${row['_parent_id'] ?? ''}'
          : '${row['id'] ?? ''}';
      final rowSubsectionId = row['_is_sub_section'] == true
          ? '${row['id'] ?? ''}'
          : '';
      if (rowSectionId == sectionId && rowSubsectionId == subsectionId) {
        selected = row;
        break;
      }
    }
    final sectionName = selected == null
        ? '选择圈子'
        : _pick(selected, const ['section_name', 'name'], '选择圈子');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: BlinStyle.ink,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          '发布帖子',
          style: TextStyle(
            color: BlinStyle.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: TextButton(
              onPressed: submitting ? null : submit,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF3F6FC),
                foregroundColor: BlinStyle.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '发布',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _openSectionPicker,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 17, 14, 17),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FB),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sectionName,
                                style: const TextStyle(
                                  color: BlinStyle.ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '先选择一个合适的圈子，再填写标题和内容',
                                style: TextStyle(
                                  color: BlinStyle.muted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF2F7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: BlinStyle.muted,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: titleController,
                  maxLength: 40,
                  style: const TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    hintText: '标题',
                    hintStyle: TextStyle(
                      color: Color(0xFFB6BDC8),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: contentController,
                  minLines: 8,
                  maxLines: 18,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 20,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '分享你的想法',
                    hintStyle: TextStyle(
                      color: Color(0xFFB6BDC8),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (videoController.text.trim().isNotEmpty ||
                    videoCoverController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FB),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '视频信息',
                          style: TextStyle(
                            color: BlinStyle.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (videoController.text.trim().isNotEmpty)
                          Text(
                            videoController.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: BlinStyle.muted),
                          ),
                        if (videoCoverController.text.trim().isNotEmpty)
                          Text(
                            videoCoverController.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: BlinStyle.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 18,
              child: Row(
                children: [
                  _PublishToolButton(
                    icon: Icons.emoji_emotions_outlined,
                    onTap: () {},
                  ),
                  _PublishToolButton(
                    icon: Icons.image_outlined,
                    onTap: () => _showPrettyDialog(
                      context,
                      title: '图片发布',
                      message: '当前后端 /post 支持网络图片或上传字段，下一步可接入文件上传。',
                      icon: Icons.image_outlined,
                    ),
                  ),
                  _PublishToolButton(
                    icon: Icons.videocam_outlined,
                    onTap: _openVideoEditor,
                  ),
                  _PublishToolButton(
                    icon: Icons.insert_drive_file_outlined,
                    onTap: () => _showPrettyDialog(
                      context,
                      title: '附件',
                      message: '后端支持 file 字段，当前先保留入口。',
                      icon: Icons.attach_file_rounded,
                    ),
                  ),
                  _PublishToolButton(
                    icon: Icons.tune_rounded,
                    onTap: _openVideoEditor,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${titleController.text.trim().isEmpty ? 0 : 1}/9',
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PublishToolButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FB),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Color(0xFF566170), size: 25),
      ),
    ),
  );
}

class _PostDetailScreen extends StatefulWidget {
  final CommunityPost post;
  final UserSession session;
  const _PostDetailScreen({required this.post, required this.session});

  @override
  State<_PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<_PostDetailScreen> {
  final api = const ApiService();
  final TextEditingController controller = TextEditingController();
  final FocusNode commentFocusNode = FocusNode();
  bool loadingComments = false;
  bool sending = false;
  bool liking = false;
  bool collecting = false;
  bool following = false;
  late int likesCount;
  bool collected = false;
  bool followed = false;
  Map<String, dynamic> detailRaw = {};
  List<Map<String, dynamic>> comments = [];
  final Map<String, List<Map<String, dynamic>>> commentReplies = {};
  Map<String, dynamic>? replyTo;

  CommunityPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    likesCount = post.likes;
    collected = '${post.raw['is_collection'] ?? 0}' == '1';
    followed = '${post.raw['is_follow'] ?? 3}' != '3';
    unawaited(loadPostDetail());
    unawaited(loadComments());
  }

  @override
  void dispose() {
    controller.dispose();
    commentFocusNode.dispose();
    super.dispose();
  }

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  Future<void> loadPostDetail() async {
    try {
      final row = await api.getPostInformation(
        widget.session.token,
        '${post.id}',
      );
      if (!mounted || row.isEmpty) return;
      setState(() {
        detailRaw = row;
        collected =
            '${row['is_collection'] ?? row['collection'] ?? (collected ? 1 : 0)}' ==
            '1';
        followed =
            '${row['is_follow'] ?? row['follow'] ?? (followed ? 1 : 3)}' != '3';
        final thumbs = int.tryParse(
          '${row['thumbs'] ?? row['likes'] ?? row['like_count'] ?? likesCount}',
        );
        if (thumbs != null) likesCount = thumbs;
      });
    } catch (_) {}
  }

  Future<void> loadComments() async {
    setState(() => loadingComments = true);
    try {
      final list = await api.getPostComments('${post.id}', page: 1, limit: 20);
      final replies = <String, List<Map<String, dynamic>>>{};
      for (final row in list) {
        final commentId = _commentId(row);
        if (commentId.isEmpty) continue;
        final directReplies = _embeddedReplies(row);
        final replyRows = directReplies.isNotEmpty
            ? await _attachNestedReplies(directReplies, 1)
            : await _loadReplyTree(commentId, 2);
        if (replyRows.isNotEmpty) replies[commentId] = replyRows;
      }
      if (mounted) {
        setState(() {
          comments = list;
          commentReplies
            ..clear()
            ..addAll(replies);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          comments = [];
          commentReplies.clear();
        });
      }
    } finally {
      if (mounted) setState(() => loadingComments = false);
    }
  }

  String _commentId(Map<String, dynamic> row) =>
      _pick(row, const ['id', 'comment_id', 'commentid']);

  Future<List<Map<String, dynamic>>> _loadReplyTree(
    String commentId,
    int depth,
  ) async {
    if (depth <= 0 || commentId.isEmpty) return const [];
    try {
      final rows = await api.getPostComments(
        '${post.id}',
        page: 1,
        limit: 20,
        commentId: commentId,
      );
      return _attachNestedReplies(rows, depth - 1);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _attachNestedReplies(
    List<Map<String, dynamic>> rows,
    int depth,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final copy = Map<String, dynamic>.from(row);
      final embedded = _embeddedReplies(copy);
      final nested = embedded.isNotEmpty
          ? await _attachNestedReplies(embedded, depth - 1)
          : await _loadReplyTree(_commentId(copy), depth);
      if (nested.isNotEmpty) copy['_nested_replies'] = nested;
      out.add(copy);
    }
    return out;
  }

  List<Map<String, dynamic>> _embeddedReplies(Map<String, dynamic> row) {
    for (final key in const [
      'children',
      'child',
      'reply',
      'replies',
      'son',
      'sons',
    ]) {
      final value = row[key];
      if (value is List)
        return value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    }
    return const [];
  }

  Future<void> sendComment() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    final parentId = '${replyTo?['id'] ?? replyTo?['comment_id'] ?? 0}';
    setState(() => sending = true);
    try {
      await api.postComment(
        widget.session.token,
        '${post.id}',
        text,
        parentId: parentId,
      );
      controller.clear();
      if (mounted) setState(() => replyTo = null);
      await loadComments();
    } catch (_) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '评论未发送',
        message: '评论暂时没有提交成功，请稍后再试。',
        icon: Icons.info_rounded,
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void startReply(Map<String, dynamic> row) {
    setState(() => replyTo = row);
    controller.text = '';
    commentFocusNode.requestFocus();
  }

  Future<void> toggleLike() async {
    if (liking) return;
    setState(() => liking = true);
    try {
      final r = await api.togglePostLike(widget.session.token, '${post.id}');
      final count = int.tryParse(
        '${r['thumbs_count'] ?? r['thumbs'] ?? likesCount}',
      );
      if (mounted) setState(() => likesCount = count ?? likesCount);
    } catch (_) {
      if (mounted)
        await _showPrettyDialog(
          context,
          title: '点赞未完成',
          message: '点赞状态暂时没有同步成功，请稍后再试。',
          icon: Icons.info_rounded,
        );
    } finally {
      if (mounted) setState(() => liking = false);
    }
  }

  Future<void> toggleCollection() async {
    if (collecting) return;
    setState(() => collecting = true);
    try {
      await api.togglePostCollection(widget.session.token, '${post.id}');
      if (mounted) setState(() => collected = !collected);
    } catch (_) {
      if (mounted)
        await _showPrettyDialog(
          context,
          title: '收藏未完成',
          message: '收藏状态暂时没有同步成功，请稍后再试。',
          icon: Icons.info_rounded,
        );
    } finally {
      if (mounted) setState(() => collecting = false);
    }
  }

  Future<void> toggleFollow() async {
    final followedId = '${post.raw['userid'] ?? ''}'.trim();
    if (following || followedId.isEmpty || followedId == '${widget.session.id}')
      return;
    setState(() => following = true);
    try {
      await api.toggleFollowUser(widget.session.token, followedId);
      if (mounted) setState(() => followed = !followed);
    } catch (_) {
      if (mounted)
        await _showPrettyDialog(
          context,
          title: '关注未完成',
          message: '关注状态暂时没有同步成功，请稍后再试。',
          icon: Icons.info_rounded,
        );
    } finally {
      if (mounted) setState(() => following = false);
    }
  }

  Future<void> sharePost() async {
    final url = '${post.raw['posturl'] ?? post.raw['post_url'] ?? ''}'.trim();
    final text = url.isNotEmpty ? url : '${post.title}\n${post.content}'.trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted)
      await _showPrettyDialog(
        context,
        title: '已复制分享内容',
        message: url.isNotEmpty ? '帖子链接已复制，可以分享给朋友。' : '帖子标题和内容已复制，可以分享给朋友。',
        icon: Icons.ios_share_rounded,
      );
  }

  @override
  Widget build(BuildContext context) {
    final detailTitle = _pick(detailRaw, const [
      'title',
      'post_title',
    ], post.title);
    final detailContent = _pick(detailRaw, const [
      'content',
      'post_content',
      'body',
    ], post.content);
    return Scaffold(
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .86),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BlinStyle.softShadow(.04)],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: BlinStyle.ink,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          post.sectionName.isNotEmpty
                              ? post.sectionName
                              : '帖子详情',
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: sharePost,
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          color: BlinStyle.ink,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundImage: post.avatar.startsWith('http')
                                    ? NetworkImage(post.avatar)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.author,
                                      style: const TextStyle(
                                        color: BlinStyle.ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [post.time, post.location, post.hierarchy]
                                          .where((e) => e.trim().isNotEmpty)
                                          .join(' · '),
                                      style: const TextStyle(
                                        color: BlinStyle.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: following ? null : toggleFollow,
                                style: FilledButton.styleFrom(
                                  backgroundColor: followed
                                      ? const Color(0xFFF4F5F7)
                                      : BlinStyle.ink,
                                  foregroundColor: followed
                                      ? BlinStyle.ink
                                      : Colors.white,
                                ),
                                child: Text(followed ? '已关注' : '关注'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Text(
                            detailTitle,
                            style: const TextStyle(
                              color: BlinStyle.ink,
                              fontSize: 28,
                              height: 1.18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.6,
                            ),
                          ),
                          if (detailContent.trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              detailContent,
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 17,
                                height: 1.75,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (post.images.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _DetailImageColumn(images: post.images),
                          ] else if (post.videoCover.isNotEmpty ||
                              post.videoUrl.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 220,
                              child: _DetailHeroMedia(post: post),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            '${post.time}${post.location.isNotEmpty ? ' · ${post.location}' : ''}${post.sectionName.isNotEmpty ? ' · 来自${post.sectionName}' : ''}${post.views > 0 ? ' · 浏览${post.views}' : ''}',
                            style: const TextStyle(
                              color: BlinStyle.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BlinStyle.softShadow(.08)],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _DetailAction(
                                  icon: Icons.remove_red_eye_rounded,
                                  text: '${post.views}',
                                  label: '浏览',
                                  color: BlinStyle.blue,
                                ),
                                _DetailAction(
                                  icon: Icons.mode_comment_rounded,
                                  text:
                                      '${comments.isEmpty ? post.comments : comments.length}',
                                  label: '评论',
                                  color: BlinStyle.cyan,
                                ),
                                _DetailAction(
                                  icon: Icons.favorite_rounded,
                                  text: '$likesCount',
                                  label: '点赞',
                                  color: BlinStyle.orange,
                                  onTap: toggleLike,
                                ),
                                _DetailAction(
                                  icon: collected
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_add_rounded,
                                  text: collected ? '已收藏' : '收藏',
                                  label: '保存',
                                  color: BlinStyle.purple,
                                  onTap: toggleCollection,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              Text(
                                '全部评论 ${comments.isEmpty ? post.comments : comments.length}',
                                style: const TextStyle(
                                  color: BlinStyle.ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F3F5),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  children: const [
                                    _CommentSortChip(text: '热门', active: true),
                                    _CommentSortChip(text: '最新'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (loadingComments)
                            const _ApiLoadingSkeleton()
                          else if (comments.isEmpty)
                            const Text(
                              '还没有评论，来说说你的想法。',
                              style: TextStyle(
                                color: BlinStyle.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          else
                            ...comments.map(
                              (row) => _CommentTile(
                                row: row,
                                replies:
                                    commentReplies[_commentId(row)] ?? const [],
                                pick: _pick,
                                onReply: startReply,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            decoration: BoxDecoration(
              color: BlinStyle.bg.withValues(alpha: .96),
              boxShadow: [BlinStyle.softShadow(.04)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyTo != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '回复 @${_pick(replyTo!, const ['nickname', 'username', 'name'], '用户')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => replyTo = null),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: BlinStyle.muted,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFE3E7EE),
                            width: .8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller,
                                focusNode: commentFocusNode,
                                minLines: 1,
                                maxLines: 3,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => sendComment(),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: replyTo == null ? '写评论…' : '回复评论…',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: sending ? null : sendComment,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  gradient: sending
                                      ? null
                                      : BlinStyle.brandGradient,
                                  color: sending
                                      ? const Color(0xFFEFF3F6)
                                      : null,
                                  shape: BoxShape.circle,
                                  boxShadow: sending
                                      ? const []
                                      : [BlinStyle.softShadow(.10)],
                                ),
                                child: Center(
                                  child: sending
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: BlinStyle.green,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_upward_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _BottomPostAction(
                      icon: collected
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      text: '收藏',
                      onTap: toggleCollection,
                    ),
                    _BottomPostAction(
                      icon: Icons.thumb_up_alt_outlined,
                      text: likesCount == 0 ? '赞' : '$likesCount',
                      onTap: toggleLike,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomPostAction extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _BottomPostAction({required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BlinStyle.softShadow(.04)],
            ),
            child: Icon(icon, color: BlinStyle.ink, size: 19),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CommentSortChip extends StatelessWidget {
  final String text;
  final bool active;
  const _CommentSortChip({required this.text, this.active = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: active ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: active ? BlinStyle.ink : BlinStyle.muted,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _CommentTile extends StatefulWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> replies;
  final String Function(Map<String, dynamic>, List<String>, [String]) pick;
  final ValueChanged<Map<String, dynamic>> onReply;
  const _CommentTile({
    required this.row,
    required this.replies,
    required this.pick,
    required this.onReply,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool liked = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final pick = widget.pick;
    final avatar = pick(row, const ['usertx', 'avatar', 'headimg']);
    final name = pick(row, const ['nickname', 'username', 'name'], '用户');
    final content = pick(row, const ['content', 'comment_content'], '');
    final time = pick(row, const ['time_ago', 'time', 'create_time'], '刚刚');
    final hierarchy = pick(row, const ['hierarchy', 'level']);
    final images = _images(row);
    final likes = '${row['likes'] ?? row['thumbs'] ?? 0}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: avatar.startsWith('http')
                ? NetworkImage(avatar)
                : null,
            child: avatar.startsWith('http')
                ? null
                : const Icon(Icons.person_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: BlinStyle.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (hierarchy.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BlinStyle.green.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hierarchy,
                          style: const TextStyle(
                            color: BlinStyle.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  content,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      images.first,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: () => setState(() => liked = !liked),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            liked
                                ? Icons.thumb_up_alt_rounded
                                : Icons.thumb_up_alt_outlined,
                            size: 16,
                            color: liked ? BlinStyle.green : BlinStyle.muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            likes,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: liked ? BlinStyle.green : BlinStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: () => widget.onReply(row),
                      child: const Text(
                        '回复',
                        style: TextStyle(
                          color: BlinStyle.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.replies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .90),
                      ),
                      boxShadow: [BlinStyle.softShadow(.035)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 16,
                              decoration: BoxDecoration(
                                color: BlinStyle.green,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${widget.replies.length} 条回复',
                              style: const TextStyle(
                                color: BlinStyle.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...widget.replies
                            .take(3)
                            .map((reply) => _replyLine(reply, 0)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyLine(Map<String, dynamic> reply, int depth) {
    final pick = widget.pick;
    final replyName = pick(reply, const ['nickname', 'username', 'name'], '用户');
    final replyContent = pick(reply, const ['content', 'comment_content'], '');
    final nested = (reply['_nested_replies'] is List)
        ? (reply['_nested_replies'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => widget.onReply(reply),
      child: Padding(
        padding: EdgeInsets.only(left: depth * 12.0, bottom: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: '$replyName：',
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: replyContent),
                ],
              ),
            ),
            if (depth < 1 && nested.isNotEmpty)
              ...nested.take(2).map((child) => _replyLine(child, depth + 1)),
          ],
        ),
      ),
    );
  }

  List<String> _images(Map<String, dynamic> r) {
    final value = r['image_path'] ?? r['img'] ?? r['images'];
    if (value is List) {
      return value
          .map((e) => '$e'.trim())
          .where((e) => e.startsWith('http'))
          .toList();
    }
    final text = '$value'.trim();
    return text.startsWith('http') ? [text] : const [];
  }
}

class _DetailHeroMedia extends StatefulWidget {
  final CommunityPost post;
  const _DetailHeroMedia({required this.post});

  @override
  State<_DetailHeroMedia> createState() => _DetailHeroMediaState();
}

class _DetailHeroMediaState extends State<_DetailHeroMedia> {
  VideoPlayerController? controller;
  bool ready = false;
  bool playing = false;

  CommunityPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    final url = post.videoUrl.trim();
    if (url.startsWith('http')) {
      controller = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize()
            .then((_) {
              controller?.addListener(() {
                if (mounted)
                  setState(
                    () => playing = controller?.value.isPlaying ?? false,
                  );
              });
              if (mounted) setState(() => ready = true);
            })
            .catchError((_) {});
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void togglePlay() {
    final player = controller;
    if (player == null || !ready) return;
    if (player.value.isPlaying) {
      player.pause();
      setState(() => playing = false);
    } else {
      player.play();
      setState(() => playing = true);
    }
  }

  void openFullScreen() {
    final player = controller;
    if (player == null || !ready) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio == 0
                    ? 16 / 9
                    : player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
            Positioned(
              top: 26,
              right: 18,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 24,
              child: VideoProgressIndicator(
                player,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cover = post.videoCover.trim();
    final player = controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: togglePlay,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (ready && player != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: player.value.size.width,
                  height: player.value.size.height,
                  child: VideoPlayer(player),
                ),
              )
            else if (cover.startsWith('http'))
              Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: const Color(0xFFEFF3F6)),
              )
            else
              Container(
                color: const Color(0xFFEDEFF3),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.movie_creation_outlined,
                  color: BlinStyle.muted,
                  size: 42,
                ),
              ),
            if (!playing)
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 46,
              ),
            Positioned(
              top: 10,
              right: 10,
              child: ready && player != null
                  ? InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: openFullScreen,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .28),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Positioned(
              left: 10,
              bottom: 6,
              right: 10,
              child: ready && player != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          player,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          colors: VideoProgressColors(
                            playedColor: BlinStyle.green,
                            bufferedColor: Colors.white.withValues(alpha: .45),
                            backgroundColor: Colors.white.withValues(
                              alpha: .22,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              _time(player.value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _time(player.value.duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '视频加载中',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailImageColumn extends StatelessWidget {
  final List<String> images;
  const _DetailImageColumn({required this.images});

  @override
  Widget build(BuildContext context) => Column(
    children: images
        .map(
          (url) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.network(
                url,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        )
        .toList(),
  );
}

class _DetailAction extends StatelessWidget {
  final IconData icon;
  final String text;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _DetailAction({
    required this.icon,
    required this.text,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 7),
          Text(
            text,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: BlinStyle.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _FeedHero extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final int postCount;
  final List<Map<String, dynamic>> sections;
  final String selectedSectionId;
  final List<String> hotKeywords;
  final ValueChanged<String> onSectionSelected;
  final VoidCallback onSignIn;
  final VoidCallback onPublish;
  const _FeedHero({
    required this.connected,
    required this.connecting,
    required this.postCount,
    required this.sections,
    required this.selectedSectionId,
    required this.hotKeywords,
    required this.onSectionSelected,
    required this.onSignIn,
    required this.onPublish,
  });

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final visibleSections = sections
        .where((row) {
          final children = row['sub_section'];
          return !(children is List && children.isNotEmpty);
        })
        .take(8)
        .toList();
    final topInset = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onSignIn,
                child: Container(
                  width: 46,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD166), Color(0xFFFF8A65)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BlinStyle.softShadow(.08)],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wb_sunny_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(height: 1),
                      Text(
                        '签到',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BlinStyle.softShadow(.05)],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: BlinStyle.muted,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hotKeywords.isEmpty
                              ? '搜索帖子 / 用户 / 板块'
                              : hotKeywords.take(3).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onPublish,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [BlinStyle.green, Color(0xFF22B8CF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BlinStyle.softShadow(.10)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 3),
                      Text(
                        '发布',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FeedChannel(
                  text: '推荐',
                  active: selectedSectionId.isEmpty,
                  onTap: () => onSectionSelected(''),
                ),
                for (final row in visibleSections)
                  _SectionChip(
                    row: row,
                    active: selectedSectionId == _pick(row, const ['id']),
                    onTap: () => onSectionSelected(_pick(row, const ['id'])),
                    onSelectSection: onSectionSelected,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// 首页右侧入口与 Banner 已按用户要求移除。

class _SectionChip extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool active;
  final VoidCallback onTap;
  final void Function(String id) onSelectSection;
  const _SectionChip({
    required this.row,
    required this.active,
    required this.onTap,
    required this.onSelectSection,
  });

  String _pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  void _showSubSections(BuildContext context, List subSections) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '二级板块',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ...subSections.whereType<Map>().map((item) {
                final name =
                    '${item['section_name'] ?? item['name'] ?? '默认版块'}';
                final icon = '${item['section_icon'] ?? ''}';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(context);
                    onSelectSection('${item['id'] ?? ''}');
                  },
                  leading: icon.startsWith('http')
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            icon,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.grid_view_rounded),
                          ),
                        )
                      : const Icon(Icons.grid_view_rounded),
                  title: Text(
                    name,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    'ID ${item['id'] ?? '--'}',
                    style: const TextStyle(color: BlinStyle.muted),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = _pick(const ['section_icon']);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? BlinStyle.green.withValues(alpha: .13)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BlinStyle.softShadow(.04)],
          ),
          child: Row(
            children: [
              if (icon.startsWith('http')) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    icon,
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                _pick(const ['section_name', 'name'], '板块'),
                style: TextStyle(
                  color: active ? BlinStyle.green : BlinStyle.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              // 只展示一级板块；二级板块不在首页频道露出。
            ],
          ),
        ),
      ),
    );
  }
}

// 首页顶部已改为真实板块导航。

class _FeedChannel extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback? onTap;
  const _FeedChannel({required this.text, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: active ? BlinStyle.ink : BlinStyle.muted,
            fontSize: active ? 22 : 20,
            fontWeight: active ? FontWeight.w900 : FontWeight.w700,
            decoration: active ? TextDecoration.underline : TextDecoration.none,
            decorationColor: BlinStyle.green,
            decorationThickness: 4,
          ),
        ),
      ),
    ),
  );
}

// 顶部搜索已融合进 _FeedHero 的视觉操作区。

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

// 首页频道已改为顶部横向导航，旧故事栏移除。

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
      ('账单会员', '账单/会员/金币', Icons.workspace_premium_rounded),
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
        builder: (_) =>
            _SignInRewardDialog(message: msg.isEmpty ? '今日奖励已到账' : msg),
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

  void openFeature(_ApiFeature feature) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ApiFeatureScreen(session: widget.session, feature: feature),
      ),
    );
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
            onOpenHome: () => openFeature(
              const _ApiFeature(
                '我的主页',
                Icons.home_rounded,
                '/get_user_other_information',
                list: false,
              ),
            ),
            onOpenFans: () => openFeature(
              const _ApiFeature(
                '粉丝列表',
                Icons.favorite_rounded,
                '/get_fan_list',
              ),
            ),
            onOpenFollows: () => openFeature(
              const _ApiFeature(
                '关注列表',
                Icons.person_add_alt_1_rounded,
                '/get_follow_list',
              ),
            ),
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

Future<void> _showPrettyDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.auto_awesome_rounded,
  String action = '知道了',
  Map<String, dynamic>? detail,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BlinStyle.softShadow(.20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: BlinStyle.brandGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: BlinStyle.muted,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: _ApiDetailCard(data: detail),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(action),
            ),
          ],
        ),
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
          child: const Icon(Icons.stars_rounded, color: Colors.white, size: 38),
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
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: .25), blurRadius: 14),
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
  final VoidCallback onOpenHome;
  final VoidCallback onOpenFans;
  final VoidCallback onOpenFollows;
  final bool loading;
  const _ProfileHero({
    required this.session,
    required this.profile,
    required this.onOpenHome,
    required this.onOpenFans,
    required this.onOpenFollows,
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
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onOpenHome,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
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
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(
              label: '粉丝',
              value: loading ? '...' : valueOrZero(profile.fans),
              onTap: onOpenFans,
            ),
            _InfoChip(
              label: '关注',
              value: loading ? '...' : valueOrZero(profile.follows),
              onTap: onOpenFollows,
            ),
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
    _ApiFeature('账单', Icons.receipt_long_rounded, '/get_user_billing'),
    _ApiFeature('订单', Icons.shopping_bag_outlined, '/get_order_record'),
    _ApiFeature('商品', Icons.storefront_outlined, '/product_list'),
    _ApiFeature('排行', Icons.emoji_events_rounded, '/ranking_list'),
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
    if (feature.path == '/product_list') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ProductCenterScreen(session: widget.session),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ApiFeatureScreen(session: widget.session, feature: feature),
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
    if (feature.path == '/product_list') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ProductCenterScreen(session: session),
        ),
      );
      return;
    }
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
      _ApiFeature('我的帖子', Icons.article_outlined, '/get_posts_list'),
      _ApiFeature('收藏记录', Icons.bookmark_rounded, '/get_collection_records'),
      _ApiFeature('点赞记录', Icons.thumb_up_alt_outlined, '/get_likes_records'),
      _ApiFeature('浏览历史', Icons.history_rounded, '/browse_history'),
      _ApiFeature('账单明细', Icons.receipt_long_rounded, '/get_user_billing'),
      _ApiFeature(
        '提现记录',
        Icons.payments_rounded,
        '/get_user_withdraw_cash_list',
      ),
      _ApiFeature('订单记录', Icons.shopping_bag_outlined, '/get_order_record'),
      _ApiFeature('商品中心', Icons.storefront_outlined, '/product_list'),
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
          _ApiFormField('name', '收款人姓名', required: true),
          _ApiFormField('account', '收款账号', required: true),
          _ApiFormField('money', '提现金额', required: true),
          _ApiFormField('type', '提现类型', hint: '0 金币，1 积分', required: true),
          _ApiFormField('remarks', '提现备注', hint: '例如：请从 QQ 转账', required: true),
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
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .92),
                  ),
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
        builder: (_) =>
            _ApiFeatureScreen(session: widget.session, feature: feature),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    try {
      final info = await const ApiService().getAppInfo();
      final updates = info['updates_info'];
      final updateMap = updates is Map
          ? Map<String, dynamic>.from(updates)
          : info;
      final latest = '${updateMap['update_version'] ?? ''}'.trim();
      final url = '${updateMap['update_url'] ?? ''}'.trim();
      final content = '${updateMap['update_content'] ?? ''}'.trim();
      if (!context.mounted) return;
      if (latest.isNotEmpty && latest != AppConfig.appVersion) {
        await _showPrettyDialog(
          context,
          title: '发现新版本 $latest',
          message: content.isEmpty
              ? '有新版本可用。${url.isEmpty ? '' : '\n更新地址：$url'}'
              : '$content${url.isEmpty ? '' : '\n\n更新地址：$url'}',
          icon: Icons.system_update_alt_rounded,
        );
      } else {
        await _showPrettyDialog(
          context,
          title: '已是最新版本',
          message: '当前版本 ${AppConfig.appVersion} 已是后台配置的最新版本。',
          icon: Icons.verified_rounded,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      await _showPrettyDialog(
        context,
        title: '检测未完成',
        message: '当前暂时没有同步到版本信息，请稍后再试。',
        icon: Icons.info_rounded,
      );
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
                        fields: [
                          _ApiFormField(
                            'avatar',
                            '头像地址',
                            hint: '图片 URL 或后台返回路径',
                            required: true,
                          ),
                        ],
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
                        fields: [
                          _ApiFormField(
                            'background',
                            '背景地址',
                            hint: '图片 URL 或后台返回路径',
                            required: true,
                          ),
                        ],
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
                          _ApiFormField(
                            'old_password',
                            '原密码',
                            obscure: true,
                            required: true,
                          ),
                          _ApiFormField(
                            'new_password',
                            '新密码',
                            obscure: true,
                            required: true,
                          ),
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
                      const _ApiFeature(
                        '解绑QQ',
                        Icons.link_off_rounded,
                        '/unbind_qq',
                        list: false,
                      ),
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
                        fields: [
                          _ApiFormField(
                            'invitation_code',
                            '邀请码',
                            required: true,
                          ),
                        ],
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
                      onChanged: (v) =>
                          setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
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

class _ProductCenterScreen extends StatefulWidget {
  final UserSession session;
  const _ProductCenterScreen({required this.session});

  @override
  State<_ProductCenterScreen> createState() => _ProductCenterScreenState();
}

class _ProductCenterScreenState extends State<_ProductCenterScreen> {
  final api = const ApiService();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  String _pick(
    Map<String, dynamic> row,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return fallback;
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await api.getProductList(page: 1, limit: 10);
      if (!mounted) return;
      setState(() {
        products = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        products = [];
        error = '商品正在同步，请稍后下拉刷新';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showProductDetail(Map<String, dynamic> product) async {
    final id = _pick(product, const ['id']);
    final canBuy = id.isNotEmpty && id != '0';
    var detail = product;
    if (canBuy) {
      try {
        final r = await api.getProductInformation(id);
        detail = {...product, ...r};
      } catch (_) {}
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ApiDetailCard(data: detail),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: canBuy
                    ? () {
                        Navigator.pop(context);
                        buy(detail);
                      }
                    : null,
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: Text(canBuy ? '立即购买' : '展示商品'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> buy(Map<String, dynamic> product) async {
    final id = _pick(product, const ['id']);
    if (id.isEmpty) {
      await _showPrettyDialog(
        context,
        title: '商品信息不完整',
        message: '当前商品缺少必要信息，刷新商品中心后再试。',
        icon: Icons.info_rounded,
      );
      return;
    }
    final name = _pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '该商品');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BlinStyle.softShadow(.20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.shopping_bag_rounded,
                color: BlinStyle.green,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                '确认购买',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '确认购买「$name」吗？',
                style: const TextStyle(
                  color: BlinStyle.muted,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('购买'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await api.buyGoods(widget.session.token, id);
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '购买结果',
        message: '商品购买请求已完成，结果已同步到当前账号。',
        icon: Icons.check_circle_rounded,
        detail: r,
      );
    } catch (_) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '购买未完成',
        message: '当前商品购买暂时没有完成，请稍后刷新商品中心后再试。',
        icon: Icons.info_rounded,
      );
    }
  }

  Widget _productCard(Map<String, dynamic> product) {
    final name = _pick(product, const [
      'product_name',
      'name',
      'title',
      'goods_name',
    ], '商品');
    final desc = _pick(product, const [
      'commodity_details',
      'desc',
      'description',
      'content',
      'remark',
      'summary',
    ]);
    final price = _pick(product, const [
      'commodity_price',
      'price',
      'money',
      'amount',
      'coin',
      'coins',
      'integral',
    ]);
    final stock = _pick(product, const [
      'commodity_inventory',
      'stock',
      'num',
      'number',
      'inventory',
      'surplus',
    ]);
    final priceText = price.isEmpty
        ? ''
        : (price.startsWith('¥') ? price : '¥$price');
    final picture = _pick(product, const [
      'product_picture',
      'picture',
      'image',
      'img',
      'cover',
    ]);
    final canBuy = _pick(product, const ['id']) != '0';
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => showProductDetail(product),
      child: SoftCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: picture.isEmpty
                    ? LinearGradient(
                        colors: [
                          BlinStyle.green.withValues(alpha: .18),
                          BlinStyle.blue.withValues(alpha: .13),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .9)),
              ),
              clipBehavior: Clip.antiAlias,
              child: picture.isNotEmpty
                  ? Image.network(
                      picture,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.local_mall_rounded,
                        color: BlinStyle.ink,
                        size: 26,
                      ),
                    )
                  : const Icon(
                      Icons.local_mall_rounded,
                      color: BlinStyle.ink,
                      size: 26,
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      if (priceText.isNotEmpty)
                        Text(
                          priceText,
                          style: const TextStyle(
                            color: BlinStyle.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (stock.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          '库存 $stock',
                          style: const TextStyle(
                            color: BlinStyle.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: canBuy ? () => buy(product) : null,
              child: Text(canBuy ? '购买' : '展示'),
            ),
          ],
        ),
      ),
    );
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
                  const Expanded(
                    child: Text(
                      '商品中心',
                      style: TextStyle(
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
              SoftCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: BlinStyle.green.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: BlinStyle.ink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '精选服务',
                            style: TextStyle(
                              color: BlinStyle.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '购买后将同步到当前账号',
                            style: TextStyle(
                              color: BlinStyle.muted,
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
              const SizedBox(height: 12),
              if (loading)
                const _ApiLoadingSkeleton()
              else if (error != null)
                SoftCard(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else if (products.isEmpty)
                const SoftCard(
                  child: Text(
                    '后台暂无商品，请添加商品后刷新',
                    style: TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                ...products.map(_productCard),
            ],
          ),
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

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final field in widget.feature.fields)
        field.key: TextEditingController(),
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

  Map<String, dynamic> get _listExtra {
    final path = widget.feature.path;
    if (path == '/get_posts_list') {
      return {'userid': widget.session.id, 'limit': 10, 'page': 1};
    }
    if (path == '/ranking_list') {
      return const {
        'sort': 'money',
        'sortOrder': 'desc',
        'limit': 10,
        'page': 1,
      };
    }
    if (path == '/invitation_ranking') {
      return const {'sortOrder': 'desc', 'limit': 10};
    }
    if (path == '/get_user_billing' ||
        path == '/get_user_withdraw_cash_list' ||
        path == '/get_order_record' ||
        path == '/get_collection_records' ||
        path == '/get_likes_records' ||
        path == '/browse_history' ||
        path == '/get_fan_list') {
      return const {'limit': 10, 'page': 1};
    }
    return const {};
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
          extra: _listExtra,
        );
        if (mounted) {
          setState(() {
            rows = r;
          });
        }
      } else if (widget.feature.fields.isEmpty &&
          widget.feature.path.startsWith('/get_')) {
        final r = await api.getApiData(
          widget.session.token,
          widget.feature.path,
        );
        if (mounted) setState(() => detail = r);
      } else {
        if (mounted) setState(() => detail = null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (widget.feature.list) {
          rows = [];
          error = null;
        } else {
          detail = null;
          error = null;
        }
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // 列表按接口原始返回展示，不额外追加未确认的请求参数。

  Future<void> submitForm() async {
    final extra = <String, dynamic>{};
    for (final field in widget.feature.fields) {
      final value = controllers[field.key]?.text.trim() ?? '';
      if (field.required && value.isEmpty) {
        await _showPrettyDialog(
          context,
          title: '信息还没填完整',
          message: '请先填写「${field.label}」，再继续提交。',
          icon: Icons.edit_note_rounded,
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
      await _showPrettyDialog(
        context,
        title: '${widget.feature.title}已完成',
        message: '操作结果已同步到当前账号。',
        icon: Icons.check_circle_rounded,
        detail: r,
      );
    } catch (_) {
      if (!mounted) return;
      await _showPrettyDialog(
        context,
        title: '${widget.feature.title}未完成',
        message: '当前操作没有完成，请确认信息后稍后再试。',
        icon: Icons.info_rounded,
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
                  child: _ApiDetailCard(
                    data: {
                      'title': widget.feature.title,
                      'summary': '内容正在准备中，后台记录生成后会自动同步。',
                    },
                  ),
                )
              else if (widget.feature.list)
                _ApiRows(rows: rows, feature: widget.feature)
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
  final _ApiFeature feature;
  const _ApiRows({required this.rows, required this.feature});

  String _pick(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return '';
  }

  String _mapValue(String value, Map<String, String> labels) =>
      labels[value] ?? value;

  String _transactionType(String value) => _mapValue(value, const {
    '0': '邀请奖励',
    '1': '注册奖励',
    '2': '签到奖励',
    '3': '购买商品',
    '4': '帖子付费',
    '5': '附件下载',
    '6': '打赏文章',
    '7': '提现',
    '8': '卡密兑换',
    '9': '发帖',
    '10': '评论',
    '11': '点赞',
    '12': '充值',
    '13': '系统调整',
  });

  String _deductionType(String value) =>
      _mapValue(value, const {'0': '金币', '1': '积分'});

  String _withdrawType(String value) =>
      _mapValue(value, const {'0': '金币提现', '1': '积分提现'});

  String _productType(String value) => _mapValue(value, const {
    '0': '兑换会员',
    '1': '购买积分',
    '2': '购买金币',
    '3': '购买会员',
  });

  String _paymentMethod(String value) => _mapValue(value, const {
    '0': '金币支付',
    '1': '积分支付',
    '2': '支付宝当面付',
    '3': '易支付',
    '4': '源支付',
  });

  String _displayTitle(Map<String, dynamic> row) {
    final path = feature.path;
    if (path == '/get_user_billing') {
      final t = _transactionType(
        _pick(row, const ['transaction_type', 'type']),
      );
      final d = _deductionType(_pick(row, const ['deduction_type']));
      return [t, d].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_withdraw_cash_list') {
      final t = _withdrawType(_pick(row, const ['type']));
      return t.isEmpty ? '提现记录' : t;
    }
    if (path == '/get_order_record') {
      return _pick(row, const [
        'product_name',
        'goods_name',
        'order_no',
        'order_number',
        'trade_no',
        'id',
      ]);
    }
    if (path == '/ranking_list' || path == '/invitation_ranking') {
      return _pick(row, const [
        'nickname',
        'username',
        'name',
        'userid',
        'user_id',
        'id',
      ]);
    }
    if (path == '/get_user_apps_list') {
      return _pick(row, const ['app_name', 'name', 'title', 'id']);
    }
    if (path == '/get_user_badge') {
      return _pick(row, const [
        'badge_name',
        'medal_name',
        'name',
        'title',
        'id',
      ]);
    }
    return _pick(row, const [
      'title',
      'post_title',
      'product_name',
      'app_name',
      'badge_name',
      'medal_name',
      'name',
      'nickname',
      'username',
      'content',
      'remark',
      'message',
      'goods_name',
      'order_no',
      'order_number',
      'trade_no',
      'id',
    ]);
  }

  String _displaySubtitle(Map<String, dynamic> row) {
    final path = feature.path;
    if (path == '/product_list') {
      final type = _productType(_pick(row, const ['type']));
      final pay = _paymentMethod(_pick(row, const ['payment_method']));
      final desc = _pick(row, const [
        'commodity_details',
        'description',
        'desc',
      ]);
      return [desc, type, pay].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_order_record') {
      final pay = _paymentMethod(_pick(row, const ['payment_method']));
      final status = _pick(row, const ['status_text', 'status']);
      return [pay, status].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_billing') {
      final io = _mapValue(_pick(row, const ['type']), const {
        '0': '支出',
        '1': '收入',
      });
      final remark = _pick(row, const [
        'remarks',
        'remark',
        'description',
        'content',
      ]);
      return [io, remark].where((e) => e.isNotEmpty).join(' · ');
    }
    if (path == '/get_user_withdraw_cash_list') {
      return _pick(row, const [
        'account',
        'remarks',
        'remark',
        'status_text',
        'status',
      ]);
    }
    if (path == '/ranking_list') {
      final money = _pick(row, const ['money', 'coin', 'coins']);
      final integral = _pick(row, const ['integral', 'score']);
      final exp = _pick(row, const ['exp', 'experience']);
      return [
        if (money.isNotEmpty) '金币 $money',
        if (integral.isNotEmpty) '积分 $integral',
        if (exp.isNotEmpty) '经验 $exp',
      ].join(' · ');
    }
    if (path == '/invitation_ranking') {
      final invite = _pick(row, const [
        'invitation_num',
        'invite_count',
        'count',
        'num',
      ]);
      return invite.isEmpty ? '' : '邀请 $invite 人';
    }
    return _pick(row, const [
      'commodity_details',
      'desc',
      'description',
      'summary',
      'app_introduce',
      'post_content',
      'text',
      'type',
      'category',
      'status_text',
      'status',
      'created_at',
      'create_time',
      'time',
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return SoftCard(
        child: _ApiDetailCard(
          data: {'title': feature.title, 'summary': '后台暂无真实记录，请添加或产生数据后刷新。'},
        ),
      );
    }
    return Column(
      children: rows.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final row = entry.value;
        final title = _displayTitle(row);
        final subtitle = _displaySubtitle(row);
        final amount = _pick(row, const [
          'commodity_price',
          'money',
          'amount',
          'price',
          'coin',
          'coins',
          'integral',
          'score',
          'balance',
        ]);
        final image = _pick(row, const [
          'product_picture',
          'app_icon',
          'icon',
          'avatar',
          'usertx',
          'cover',
          'picture',
          'image',
        ]);
        final time = _pick(row, const [
          'created_at',
          'create_time',
          'addtime',
          'pay_time',
          'time',
          'updated_at',
        ]);
        final status = _pick(row, const ['status_text', 'status']);
        final isMoney =
            feature.path.contains('billing') ||
            feature.path.contains('withdraw') ||
            feature.path.contains('order') ||
            feature.path.contains('product') ||
            feature.title.contains('账单') ||
            feature.title.contains('提现') ||
            feature.title.contains('订单') ||
            feature.title.contains('商品');
        final amountText = amount.isEmpty
            ? ''
            : (isMoney && !amount.startsWith('¥') ? '¥$amount' : amount);
        final leadingText =
            (feature.path == '/ranking_list' ||
                feature.path == '/invitation_ranking')
            ? '$index'
            : '';
        return SoftCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              builder: (_) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * .72,
                    child: SingleChildScrollView(
                      child: _ApiDetailCard(data: row),
                    ),
                  ),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: image.isEmpty
                        ? BlinStyle.green.withValues(alpha: .12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => leadingText.isNotEmpty
                              ? Center(
                                  child: Text(
                                    leadingText,
                                    style: const TextStyle(
                                      color: BlinStyle.ink,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                )
                              : Icon(
                                  feature.icon,
                                  color: BlinStyle.ink,
                                  size: 22,
                                ),
                        )
                      : leadingText.isNotEmpty
                      ? Center(
                          child: Text(
                            leadingText,
                            style: const TextStyle(
                              color: BlinStyle.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : Icon(feature.icon, color: BlinStyle.ink, size: 22),
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
                      if (status.isNotEmpty && status != subtitle) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: BlinStyle.green.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '状态 $status',
                            style: const TextStyle(
                              color: BlinStyle.softInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
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
                if (amountText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    amountText,
                    style: const TextStyle(
                      color: BlinStyle.green,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
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
    final hasForm =
        feature.fields.isNotEmpty || !feature.path.startsWith('/get_');
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
                  feature.fields.isEmpty
                      ? '确认执行${feature.title}'
                      : '填写${feature.title}信息',
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
                        labelText: field.required
                            ? '${field.label} *'
                            : field.label,
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
          SoftCard(
            child: _ApiDetailCard(
              data: {
                'title': feature.title,
                'summary': '后台暂无真实信息，请添加或产生数据后刷新。',
              },
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
    'userid': '用户ID',
    'nickname': '昵称',
    'username': '账号',
    'name': '名称',
    'title': '标题',
    'post_title': '帖子标题',
    'post_content': '帖子内容',
    'content': '内容',
    'product_name': '商品名称',
    'product_picture': '商品图片',
    'commodity_details': '商品详情',
    'commodity_price': '商品价格',
    'commodity_inventory': '商品库存',
    'type': '类型',
    'payment_method': '支付方式',
    'payment_type': '支付类型',
    'shopid': '商品ID',
    'order_no': '订单号',
    'order_number': '订单号',
    'trade_no': '交易号',
    'transaction_type': '交易类型',
    'deduction_type': '扣减类型',
    'remarks': '备注',
    'account': '收款账号',
    'app_name': '应用名称',
    'app_icon': '应用图标',
    'app_introduce': '应用介绍',
    'badge_name': '徽章名称',
    'medal_name': '徽章名称',
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

  String _mappedScalar(String key, String text) {
    if (key == 'transaction_type') {
      return const {
            '0': '邀请奖励',
            '1': '注册奖励',
            '2': '签到奖励',
            '3': '购买商品',
            '4': '帖子付费',
            '5': '附件下载',
            '6': '打赏文章',
            '7': '提现',
            '8': '卡密兑换',
            '9': '发帖',
            '10': '评论',
            '11': '点赞',
            '12': '充值',
            '13': '系统调整',
          }[text] ??
          text;
    }
    if (key == 'deduction_type')
      return const {'0': '金币', '1': '积分'}[text] ?? text;
    if (key == 'payment_method') {
      return const {
            '0': '金币支付',
            '1': '积分支付',
            '2': '支付宝当面付',
            '3': '易支付',
            '4': '源支付',
          }[text] ??
          text;
    }
    if (key == 'type')
      return const {
            '0': '金币/兑换',
            '1': '积分/购买积分',
            '2': '购买金币',
            '3': '购买会员',
          }[text] ??
          text;
    return text;
  }

  String _value(dynamic value, [String key = '']) {
    if (value == null) return '';
    if (value is Map) {
      return value.entries
          .map((e) => '${_label('${e.key}')}: ${_value(e.value, '${e.key}')}')
          .where((e) => e.trim().isNotEmpty)
          .join('  ');
    }
    if (value is List)
      return value.isEmpty ? '暂无' : value.map((e) => _value(e, key)).join('、');
    final text = '$value'.trim();
    if (text == 'null' || text.isEmpty) return '';
    return _mappedScalar(key, text);
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries
        .map((e) => MapEntry(e.key, _value(e.value, e.key)))
        .where((e) => e.value.isNotEmpty)
        .take(24)
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
