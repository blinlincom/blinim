import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final int peerId;
  final String peerName;
  final String peerAvatar;
  const ChatScreen({
    super.key,
    required this.session,
    required this.im,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final api = const ApiService();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  List<UnifiedMessage> messages = [];
  int historyPage = 1;
  bool hasMoreHistory = true;
  bool loadingHistory = false;
  bool isFriend = true;
  bool friendRequestPending = false;
  int nonFriendTextSent = 0;
  bool loading = true;
  ImOnlineStatus? peerOnline;
  DateTime? realtimePresenceAt;
  bool sendingAttachment = false;
  bool readyToShowMessages = false;
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  StreamSubscription? connectionSub;
  Timer? onlineTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    checkFriend();
    scroll.addListener(onScroll);
    inputFocus.addListener(() {
      if (inputFocus.hasFocus) {
        _bottom(delay: const Duration(milliseconds: 280));
      }
    });
    sub = widget.im.messages.listen((m) {
      if (m.fromUserId == widget.peerId || m.toUserId == widget.peerId) {
        if (_isHiddenCallSignal(m)) return;
        setState(() {
          if (!_hasMessage(m)) messages.add(m);
          if (m.fromUserId == widget.peerId) {
            peerOnline = const ImOnlineStatus(online: true, device: '');
          }
        });
        _bottom();
      }
    });
    presenceSub = widget.im.presences.listen((p) {
      if (p.userId == widget.peerId) {
        setState(() {
          realtimePresenceAt = DateTime.now();
          peerOnline = ImOnlineStatus(online: p.online, device: p.device);
        });
      }
    });
    connectionSub = widget.im.connectionChanges.listen((_) {
      if (widget.im.connected) unawaited(refreshPeerOnline());
    });
    onlineTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && widget.im.connected) unawaited(refreshPeerOnline());
    });
    refreshPeerOnline();
  }

  Future<void> refreshPeerOnline() async {
    try {
      final status = await api.getImOnlineStatus(
        token: widget.session.token,
        userId: widget.peerId,
      );
      if (mounted) {
        final hasFreshRealtime = realtimePresenceAt != null &&
            DateTime.now().difference(realtimePresenceAt!) <
                const Duration(seconds: 45);
        if (!hasFreshRealtime) setState(() => peerOnline = status);
      }
    } catch (_) {
      if (mounted)
        setState(() => peerOnline = const ImOnlineStatus(online: false));
    }
  }

  Future<void> checkFriend() async {
    try {
      final value = await api.isFriend(widget.session.token, widget.peerId);
      if (mounted) {
        setState(() {
          isFriend = value;
          if (value) friendRequestPending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isFriend = false);
    }
  }

  bool _isHiddenCallSignal(UnifiedMessage message) {
    return message.msgType == 'call';
  }

  String _messageKey(UnifiedMessage message) {
    final raw = message.raw;
    final direct = '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'.trim();
    if (direct.isNotEmpty && direct != '0') return direct;
    return _semanticMessageKey(message);
  }

  String _semanticMessageKey(UnifiedMessage message) {
    final seconds = message.createTime.millisecondsSinceEpoch ~/ 1000;
    final contentText = jsonEncode(message.content);
    return '${message.fromUserId}_${message.toUserId}_${message.msgType}_${seconds}_$contentText';
  }

  List<UnifiedMessage> _dedupeMessages(List<UnifiedMessage> source) {
    final seen = <String>{};
    final result = <UnifiedMessage>[];
    for (final message in source) {
      final keys = _messageKeys(message);
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      result.add(message);
    }
    return result;
  }

  bool _hasMessage(UnifiedMessage message) {
    final keys = _messageKeys(message);
    return messages.any((m) => _messageKeys(m).any(keys.contains));
  }

  Set<String> _messageKeys(UnifiedMessage message) {
    final raw = message.raw;
    final keys = <String>{};
    final direct = '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'.trim();
    if (direct.isNotEmpty && direct != '0') keys.add(direct);
    keys.add(_semanticMessageKey(message));
    return keys;
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        readyToShowMessages = false;
      });
    }
    try {
      final r = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
        page: 1,
      );
      final visible = r.where((m) => !_isHiddenCallSignal(m)).toList();
      if (mounted) {
        setState(() {
          messages = _dedupeMessages(visible);
          historyPage = 1;
          hasMoreHistory = r.length >= 30;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('聊天内容暂时无法同步')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpBottom();
        if (mounted) setState(() => readyToShowMessages = true);
      });
    }
  }

  void onScroll() {
    if (!scroll.hasClients || loadingHistory || !hasMoreHistory || loading)
      return;
    if (scroll.position.pixels <= 48) unawaited(loadOlderHistory());
  }

  Future<void> loadOlderHistory() async {
    if (loadingHistory || !hasMoreHistory) return;
    setState(() => loadingHistory = true);
    final oldMax = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    try {
      final nextPage = historyPage + 1;
      final older = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
        page: nextPage,
      );
      if (mounted) {
        setState(() {
          final visibleOlder = older.where((m) => !_isHiddenCallSignal(m)).toList();
          messages = _dedupeMessages([...visibleOlder, ...messages]);
          historyPage = nextPage;
          hasMoreHistory = older.length >= 30;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scroll.hasClients) return;
          final delta = scroll.position.maxScrollExtent - oldMax;
          scroll.jumpTo(
            (scroll.position.pixels + delta).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        });
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('历史消息暂时加载失败')));
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Future<void> sendPayload(
    Map<String, dynamic> payload, {
    required String fallbackContent,
    required int messageType,
  }) async {
    final local = UnifiedMessage.fromPayload(payload, widget.session.id);
    setState(() {
      if (!_hasMessage(local)) messages.add(local);
    });
    _bottom();
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: fallbackContent,
        messageType: messageType,
        payload: payload,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('消息暂时没有发送成功：$e')));
    }
  }

  Map<String, dynamic> buildPayload(
    String type,
    Map<String, dynamic> content,
  ) => {
    'message_id': 0,
    'client_msg_no':
        '${widget.session.id}_${widget.peerId}_${DateTime.now().microsecondsSinceEpoch}_$type',
    'from_user_id': widget.session.id,
    'to_user_id': widget.peerId,
    'from_uid': ImService.uidForUser(widget.session.id),
    'to_uid': ImService.uidForUser(widget.peerId),
    'msg_type': type,
    'content': content,
    'create_time': DateTime.now().toIso8601String(),
  };

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (!isFriend && nonFriendTextSent >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还不是好友，只能先发送 3 条文字消息，请先添加好友')),
      );
      return;
    }
    input.clear();
    await sendPayload(
      buildPayload('text', {'text': text}),
      fallbackContent: text,
      messageType: 0,
    );
    if (!isFriend && mounted) setState(() => nonFriendTextSent += 1);
  }

  String _pickUrl(Map<String, dynamic> data) {
    for (final key in const [
      'url',
      'path',
      'file_url',
      'src',
      'image',
      'image_path',
    ]) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return '$value'.trim();
    }
    return '';
  }

  Future<void> sendAttachment({required String mediaType}) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发送图片、视频和文件')));
      return;
    }
    if (sendingAttachment) return;
    final result = await FilePicker.platform.pickFiles(
      type: mediaType == 'image'
          ? FileType.image
          : mediaType == 'video'
          ? FileType.video
          : FileType.any,
      allowMultiple: false,
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    final bytes = file?.bytes;
    if (file == null) return;
    if (bytes == null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前平台暂时无法读取这个文件')));
      return;
    }
    setState(() => sendingAttachment = true);
    try {
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: file.name,
      );
      final url = _pickUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回文件地址');
      final type = mediaType;
      final caption = input.text.trim();
      final payload = buildPayload(type, {
        'url': url,
        'name': file.name,
        'size': file.size,
        if (caption.isNotEmpty && (type == 'image' || type == 'video'))
          'text': caption,
      });
      input.clear();
      await sendPayload(
        payload,
        fallbackContent: type == 'image'
            ? '[图片]'
            : type == 'video'
            ? '[视频] ${file.name}'
            : '[文件] ${file.name}',
        messageType: type == 'image'
            ? 1
            : type == 'video'
            ? 4
            : 3,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image'
                  ? '图片发送失败：$e'
                  : mediaType == 'video'
                  ? '视频发送失败：$e'
                  : '文件发送失败：$e',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => sendingAttachment = false);
    }
  }

  Future<void> sendTransfer() async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能使用转账')));
      return;
    }
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .30),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BlinStyle.softShadow(.20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: BlinStyle.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      '发起转账',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '转账金额',
                  prefixText: '¥ ',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: '备注，可选'),
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
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'amount': amountController.text.trim(),
                        'note': noteController.text.trim(),
                      }),
                      child: const Text('发送'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
    final amount = result?['amount'] ?? '';
    final amountValue = int.tryParse(amount);
    if (amount.isEmpty) return;
    if (amountValue == null || amountValue <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('转账金额必须是正整数')));
      }
      return;
    }
    await sendPayload(
      buildPayload('transfer', {
        'amount': amount,
        'note': result?['note'] ?? '',
        'status': 'pending',
        'payment': 0,
      }),
      fallbackContent: '[转账] ¥$amount',
      messageType: 2,
    );
  }

  Future<void> startCall(bool video) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发起通话')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          session: widget.session,
          im: widget.im,
          peerId: widget.peerId,
          peerName: widget.peerName,
          video: video,
        ),
      ),
    );
  }

  Future<void> addCurrentFriend() async {
    try {
      final msg = await api.addFriend(
        widget.session.token,
        widget.peerId,
        message: '你好，我想添加你为好友',
      );
      if (mounted) {
        setState(() => friendRequestPending = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> deleteCurrentFriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除 ${widget.peerName} 吗？删除后需要重新添加好友才能发送附件和发起通话。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await api.deleteFriend(widget.session.token, widget.peerId);
      if (mounted) {
        setState(() {
          isFriend = false;
          friendRequestPending = false;
          messages = [];
          historyPage = 1;
          hasMoreHistory = false;
          readyToShowMessages = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, {'deletedUserId': widget.peerId});
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> sendEmoji(String emoji) async {
    await sendPayload(
      buildPayload('emoji', {'emoji': emoji, 'text': emoji}),
      fallbackContent: emoji,
      messageType: 0,
    );
  }

  void addEmoji(String emoji) {
    final start = input.selection.start < 0
        ? input.text.length
        : input.selection.start;
    final end = input.selection.end < 0
        ? input.text.length
        : input.selection.end;
    input.text = input.text.replaceRange(start, end, emoji);
    final offset = start + emoji.length;
    input.selection = TextSelection.collapsed(offset: offset);
  }

  Future<void> openMorePanel() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatMorePanel(
        onImage: () {
          Navigator.pop(context);
          unawaited(sendAttachment(mediaType: 'image'));
        },
        onVideo: () {
          Navigator.pop(context);
          unawaited(sendAttachment(mediaType: 'video'));
        },
        onFile: () {
          Navigator.pop(context);
          unawaited(sendAttachment(mediaType: 'file'));
        },
        onTransfer: () {
          Navigator.pop(context);
          unawaited(sendTransfer());
        },
        onEmoji: (emoji) {
          Navigator.pop(context);
          unawaited(sendEmoji(emoji));
        },
      ),
    );
  }

  void _jumpBottom() {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  }

  void _bottom({Duration delay = const Duration(milliseconds: 80)}) => Future.delayed(delay, () {
    if (!mounted || !scroll.hasClients) return;
    scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  });

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (inputFocus.hasFocus) {
      _bottom(delay: const Duration(milliseconds: 320));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(load(silent: true));
      unawaited(refreshPeerOnline());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    onlineTimer?.cancel();
    connectionSub?.cancel();
    presenceSub?.cancel();
    sub?.cancel();
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    backgroundColor: const Color(0xFFF1F1F1),
    body: Column(
      children: [
        _ChatHeader(
          name: widget.peerName,
          avatar: widget.peerAvatar,
          online: peerOnline,
          isFriend: isFriend,
          friendRequestPending: friendRequestPending,
          onAddFriend: addCurrentFriend,
          onOpenInfo: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _PeerChatInfoScreen(
                name: widget.peerName,
                avatar: widget.peerAvatar,
                online: peerOnline,
                onDeleteFriend: deleteCurrentFriend,
                onClearHistory: () {
                  setState(() {
                    messages = [];
                    readyToShowMessages = true;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('本地聊天记录已清空')),
                  );
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const _ChatHistorySkeleton()
              : Opacity(
                  opacity: readyToShowMessages ? 1 : 0,
                  child: ListView.builder(
                    controller: scroll,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                    itemCount: messages.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        if (loadingHistory) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: Text(
                              hasMoreHistory ? '上拉查看历史消息' : '没有更多历史消息了',
                              style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }
                      return _Bubble(m: messages[i - 1]);
                    },
                  ),
                ),
        ),
        _Composer(
          controller: input,
          focusNode: inputFocus,
          sendingAttachment: sendingAttachment,
          onMore: openMorePanel,
          onSend: send,
          onEmoji: () => addEmoji('😊'),
          onImage: () => unawaited(sendAttachment(mediaType: 'image')),
          onVoice: () => startCall(false),
          onVideoCall: () => startCall(true),
        ),
      ],
    ),
  );
}

class _PeerChatInfoScreen extends StatefulWidget {
  final String name;
  final String avatar;
  final ImOnlineStatus? online;
  final VoidCallback onDeleteFriend;
  final VoidCallback onClearHistory;

  const _PeerChatInfoScreen({
    required this.name,
    required this.avatar,
    required this.online,
    required this.onDeleteFriend,
    required this.onClearHistory,
  });

  @override
  State<_PeerChatInfoScreen> createState() => _PeerChatInfoScreenState();
}

class _PeerChatInfoScreenState extends State<_PeerChatInfoScreen> {
  bool muteNotifications = false;
  bool pinnedChat = false;

  String get subtitle {
    final online = widget.online;
    if (online == null) return '';
    if (online.online) return online.device.isNotEmpty ? '在线 · ${online.device}' : '在线';
    return online.label;
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    body: SafeArea(
      child: ListView(
        children: [
          _InfoHeader(title: '聊天信息'),
          Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.fromLTRB(34, 26, 34, 28),
            child: Row(
              children: [
                _InfoAvatar(avatar: widget.avatar, name: widget.name),
                const SizedBox(width: 34),
                _AddContactTile(onTap: () => _toast('添加入口已预留')),
              ],
            ),
          ),
          _InfoSection(
            children: [
              _InfoRow(
                title: '查找聊天记录',
                onTap: () => _toast('聊天记录搜索入口已预留'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoSection(
            children: [
              _InfoSwitchRow(
                title: '消息免打扰',
                value: muteNotifications,
                onChanged: (v) => setState(() => muteNotifications = v),
              ),
              _InfoSwitchRow(
                title: '置顶聊天',
                value: pinnedChat,
                onChanged: (v) => setState(() => pinnedChat = v),
              ),
              _InfoRow(
                title: '聊天背景',
                trailing: '默认背景',
                onTap: () => _toast('聊天背景设置入口已预留'),
              ),
              _InfoRow(
                title: '投诉',
                onTap: () => _toast('投诉入口已预留'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoSection(
            children: [
              _InfoRow(
                title: '清空聊天记录',
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('清空聊天记录'),
                      content: const Text('确定要清空当前本地聊天记录吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
                      ],
                    ),
                  );
                  if (ok == true) widget.onClearHistory();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoSection(
            children: [
              _InfoRow(
                title: '删除好友',
                danger: true,
                onTap: widget.onDeleteFriend,
              ),
            ],
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Center(
                child: Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InfoHeader extends StatelessWidget {
  final String title;
  const _InfoHeader({required this.title});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 74,
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 34, color: Color(0xFF222222)),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(color: Color(0xFF222222), fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _InfoAvatar extends StatelessWidget {
  final String avatar;
  final String name;
  const _InfoAvatar({required this.avatar, required this.name});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 86,
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Container(
            width: 78,
            height: 78,
            color: const Color(0xFF0E6D91),
            child: avatar.isNotEmpty
                ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      name.characters.isEmpty ? '?' : name.characters.first,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF222222), fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _AddContactTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddContactTile({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD8D8D8)),
      ),
      child: const Icon(Icons.add_rounded, size: 46, color: Color(0xFFC6C6C6)),
    ),
  );
}

class _InfoSection extends StatelessWidget {
  final List<Widget> children;
  const _InfoSection({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String? trailing;
  final bool danger;
  final VoidCallback? onTap;
  const _InfoRow({required this.title, this.trailing, this.danger = false, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger ? Colors.red : const Color(0xFF222222),
                fontSize: 24,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 19),
            ),
          if (!danger) const SizedBox(width: 14),
          if (!danger) const Icon(Icons.chevron_right_rounded, color: Color(0xFFD0D0D0), size: 34),
        ],
      ),
    ),
  );
}

class _InfoSwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _InfoSwitchRow({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    height: 82,
    padding: const EdgeInsets.symmetric(horizontal: 34),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Color(0xFF222222), fontSize: 24, fontWeight: FontWeight.w400),
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white),
      ],
    ),
  );
}

class _ChatHistorySkeleton extends StatelessWidget {
  const _ChatHistorySkeleton();

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    itemCount: 8,
    itemBuilder: (_, i) {
      final mine = i.isOdd;
      final width = switch (i % 3) {
        0 => 210.0,
        1 => 160.0,
        _ => 240.0,
      };
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: width,
          height: i % 3 == 0 ? 46 : 38,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .88)),
          ),
        ),
      );
    },
  );
}

class _ChatHeader extends StatelessWidget {
  final String name;
  final String avatar;
  final ImOnlineStatus? online;
  final bool isFriend;
  final bool friendRequestPending;
  final VoidCallback onAddFriend;
  final VoidCallback onOpenInfo;
  const _ChatHeader({
    required this.name,
    required this.avatar,
    required this.online,
    required this.isFriend,
    required this.friendRequestPending,
    required this.onAddFriend,
    required this.onOpenInfo,
  });

  String get subtitle {
    if (online == null) return '正在检测在线状态...';
    if (online!.online) return '在线${online!.device.isNotEmpty ? ' · ${online!.device}' : ''}';
    return '上次在线时间 ${online!.label}';
  }

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF1F1F1),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 78,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 32, color: Color(0xFF222222)),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 56,
                height: 56,
                color: const Color(0xFF0E6D91),
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          name.characters.isEmpty ? '?' : name.characters.first,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF222222), fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (!isFriend)
              TextButton(
                onPressed: friendRequestPending ? null : onAddFriend,
                child: Text(friendRequestPending ? '待同意' : '加好友'),
              )
            else
              IconButton(
                onPressed: onOpenInfo,
                icon: const Icon(Icons.more_horiz_rounded, size: 32, color: Color(0xFF222222)),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  final UnifiedMessage m;
  const _Bubble({required this.m});
  @override
  Widget build(BuildContext context) {
    final me = m.isMe;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        margin: EdgeInsets.fromLTRB(me ? 54 : 10, 5, me ? 10 : 54, 5),
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 10),
        decoration: BoxDecoration(
          color: me ? const Color(0xFFEAF1FF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(me ? 22 : 4),
            bottomRight: Radius.circular(me ? 4 : 22),
          ),
        ),
        child: _content(context, me),
      ),
    );
  }

  Widget _content(BuildContext context, bool me) {
    final color = me ? Colors.white : BlinStyle.ink;
    if (m.msgType == 'image') {
      final text = '${m.content['text'] ?? ''}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${m.content['url'] ?? ''}'.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network('${m.content['url']}'),
            ),
          if (text.isNotEmpty && text != '[图片]')
            Text(text, style: TextStyle(color: color)),
        ],
      );
    }
    if (m.msgType == 'video') {
      final rawName = '${m.content['name'] ?? '视频'}';
      final name = rawName.startsWith('[视频]')
          ? rawName.replaceFirst('[视频]', '').trim()
          : rawName;
      final url = '${m.content['url'] ?? m.content['file_url'] ?? ''}';
      final videoText = '${m.content['text'] ?? ''}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: url.isEmpty ? null : () => _showVideoPlayer(context, url),
            borderRadius: BorderRadius.circular(16),
            child: _VideoCover(url: url),
          ),
          const SizedBox.shrink(),
          if (videoText.isNotEmpty &&
              videoText != '[视频]' &&
              videoText != '[视频] $name')
            Text(
              videoText,
              style: TextStyle(
                color: color.withValues(alpha: .86),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      );
    }
    if (m.msgType == 'emoji') {
      return Text(
        '${m.content['emoji'] ?? m.content['text'] ?? m.preview}',
        style: const TextStyle(fontSize: 34, height: 1.1),
      );
    }
    if (m.msgType == 'file') {
      final name = '${m.content['name'] ?? m.content['file_name'] ?? '文件'}';
      final size = int.tryParse('${m.content['size'] ?? 0}') ?? 0;
      final sizeText = size > 0
          ? ' · ${(size / 1024).toStringAsFixed(size > 1024 * 1024 ? 1 : 0)}${size > 1024 * 1024 ? 'MB' : 'KB'}'
          : '';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (me ? Colors.white : BlinStyle.green).withValues(
                alpha: me ? .18 : .12,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.insert_drive_file_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                if (sizeText.isNotEmpty)
                  Text(
                    sizeText.substring(3),
                    style: TextStyle(
                      color: color.withValues(alpha: .72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    if (m.msgType == 'transfer') {
      return _TransferCard(message: m, me: me, color: color);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            '${m.content['text'] ?? m.preview}',
            style: const TextStyle(
              color: Color(0xFF222222),
              height: 1.35,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _timeText(m.createTime),
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500),
        ),
        if (me) ...[
          const SizedBox(width: 4),
          const Icon(Icons.check_rounded, color: Color(0xFF8E8E93), size: 18),
        ],
      ],
    );
  }

  String _timeText(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  void _showVideoPlayer(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (_) => _VideoPlayerDialog(url: url),
    );
  }
}

class _VideoCover extends StatefulWidget {
  final String url;
  const _VideoCover({required this.url});

  @override
  State<_VideoCover> createState() => _VideoCoverState();
}

class _VideoCoverState extends State<_VideoCover> {
  VideoPlayerController? controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.url.isEmpty) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller = c;
    c
        .initialize()
        .then((_) {
          if (!mounted) return;
          c.pause();
          c.seekTo(Duration.zero);
          setState(() => ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: 220,
      height: 124,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ready && controller != null
                ? VideoPlayer(controller!)
                : Container(color: Colors.black.withValues(alpha: .16)),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .42),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TransferCard extends StatefulWidget {
  final UnifiedMessage message;
  final bool me;
  final Color color;
  const _TransferCard({
    required this.message,
    required this.me,
    required this.color,
  });

  @override
  State<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<_TransferCard> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final me = widget.me;
    final color = widget.color;
    final amount = '${m.content['amount'] ?? ''}';
    final note = '${m.content['note'] ?? ''}';
    final rawStatus = '${m.content['status'] ?? 'pending'}';
    final done = accepted || rawStatus == 'success' || rawStatus == 'accepted';
    return InkWell(
      onTap: me || done
          ? null
          : () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('确认收款'),
                  content: Text('确认接收 ¥$amount 的转账吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认收款'),
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) setState(() => accepted = true);
            },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (me ? Colors.white : const Color(0xFFFFF3D8)).withValues(
            alpha: me ? .14 : 1,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (me ? Colors.white : const Color(0xFFFFC766)).withValues(
              alpha: me ? .22 : .45,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  color: me ? Colors.white : const Color(0xFFE68A00),
                ),
                const SizedBox(width: 8),
                Text(
                  '转账',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '¥$amount',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (note.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: .78),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              done
                  ? '已收款'
                  : me
                  ? '等待对方确认'
                  : '点击确认收款',
              style: TextStyle(
                color: color.withValues(alpha: .68),
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

class _VideoPlayerDialog extends StatefulWidget {
  final String url;
  const _VideoPlayerDialog({required this.url});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final VideoPlayerController controller;
  bool ready = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => ready = true);
          controller.play();
        })
        .catchError((e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.black,
    insetPadding: const EdgeInsets.all(18),
    child: AspectRatio(
      aspectRatio: ready && controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (ready)
            VideoPlayer(controller)
          else if (error != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '视频加载失败：$error',
                style: const TextStyle(color: Colors.white),
              ),
            )
          else
            const CircularProgressIndicator(),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sendingAttachment;
  final VoidCallback onMore;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final VoidCallback onImage;
  final VoidCallback onVoice;
  final VoidCallback onVideoCall;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sendingAttachment,
    required this.onMore,
    required this.onSend,
    required this.onEmoji,
    required this.onImage,
    required this.onVoice,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 54),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7FB),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '',
                      isCollapsed: true,
                    ),
                    style: const TextStyle(fontSize: 18, color: Color(0xFF222222)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5A74E8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                  ),
                  child: const Text('发送', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ComposerTool(icon: Icons.emoji_emotions_outlined, onTap: onEmoji),
              _ComposerTool(icon: Icons.image_outlined, onTap: sendingAttachment ? null : onImage),
              _ComposerTool(icon: Icons.call_rounded, onTap: onVoice),
              _ComposerTool(icon: Icons.videocam_rounded, onTap: onVideoCall),
              _ComposerTool(icon: Icons.more_horiz_rounded, onTap: onMore),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ComposerTool extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ComposerTool({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: const Color(0xFF5A74E8), size: 29),
    ),
  );
}

class _ChatMorePanel extends StatelessWidget {
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onTransfer;
  final ValueChanged<String> onEmoji;
  const _ChatMorePanel({
    required this.onImage,
    required this.onVideo,
    required this.onFile,
    required this.onTransfer,
    required this.onEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final emojis = [
      '😀',
      '😂',
      '😍',
      '👍',
      '🎉',
      '🥰',
      '😭',
      '😎',
      '❤️',
      '🔥',
      '👏',
      '🙏',
    ];
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BlinStyle.softShadow(.18)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MoreAction(
                  icon: Icons.image_rounded,
                  label: '图片',
                  onTap: onImage,
                ),
                const SizedBox(width: 12),
                _MoreAction(
                  icon: Icons.videocam_rounded,
                  label: '视频',
                  onTap: onVideo,
                ),
                const SizedBox(width: 12),
                _MoreAction(
                  icon: Icons.attach_file_rounded,
                  label: '文件',
                  onTap: onFile,
                ),
                const SizedBox(width: 12),
                _MoreAction(
                  icon: Icons.account_balance_wallet_rounded,
                  label: '转账',
                  onTap: onTransfer,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '常用表情',
              style: TextStyle(
                color: BlinStyle.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: emojis
                  .map(
                    (emoji) => InkWell(
                      onTap: () => onEmoji(emoji),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F8F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8F7),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            GradientIcon(icon: icon, size: 46, iconSize: 23),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: BlinStyle.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
