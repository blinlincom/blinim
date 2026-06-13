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
  bool showEmojiPanel = false;
  bool stickToBottomDuringKeyboard = false;
  bool peerTyping = false;
  bool suppressHistoryDuringProgrammaticScroll = false;
  int keyboardSettleGeneration = 0;
  int bottomSettleGeneration = 0;
  DateTime historyLoadBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastReadReceiptSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, String> messageSendStates = {};
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  StreamSubscription? typingSub;
  StreamSubscription? readReceiptSub;
  StreamSubscription? connectionSub;
  Timer? typingHideTimer;
  Timer? onlineTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    checkFriend();
    scroll.addListener(onScroll);
    input.addListener(_handleInputChanged);
    inputFocus.addListener(() {
      if (inputFocus.hasFocus) {
        _handleInputFocus();
      } else {
        unawaited(_sendTypingStopped());
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
        if (m.fromUserId == widget.peerId) unawaited(_sendReadReceipt());
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
    typingSub = widget.im.typingEvents.listen((event) {
      if (event.fromUserId != widget.peerId ||
          event.toUserId != widget.session.id) {
        return;
      }
      _showPeerTyping(event.active);
    });
    readReceiptSub = widget.im.readReceipts.listen((receipt) {
      if (receipt.fromUserId != widget.peerId ||
          receipt.toUserId != widget.session.id) {
        return;
      }
      _applyReadReceipt(receipt);
    });
    onlineTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && widget.im.connected) unawaited(refreshPeerOnline());
    });
    refreshPeerOnline();
  }

  bool _isMobileDevice(String device) {
    final d = device.trim().toLowerCase();
    return d.contains('android') ||
        d.contains('ios') ||
        d.contains('iphone') ||
        d.contains('ipad') ||
        d.contains('mobile') ||
        d.contains('phone') ||
        d == '2' ||
        d == '4';
  }

  Future<void> refreshPeerOnline() async {
    try {
      final status = await api.getImOnlineStatus(
        token: widget.session.token,
        userId: widget.peerId,
      );
      if (mounted) {
        final hasFreshRealtime =
            realtimePresenceAt != null &&
            DateTime.now().difference(realtimePresenceAt!) <
                const Duration(seconds: 45);
        final apiIsMobile = status.online && _isMobileDevice(status.device);
        final currentIsMobile =
            peerOnline != null &&
            peerOnline!.online &&
            _isMobileDevice(peerOnline!.device);
        if (!hasFreshRealtime || apiIsMobile || !currentIsMobile) {
          setState(() => peerOnline = status);
        }
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
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
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
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
    if (direct.isNotEmpty && direct != '0') keys.add(direct);
    keys.add(_semanticMessageKey(message));
    return keys;
  }

  Future<void> _sendControlPayload(String type, Map<String, dynamic> content) {
    return widget.im.sendDirect(
      channelId: ImService.uidForUser(widget.peerId),
      payload: buildPayload(type, content),
    );
  }

  void _handleInputChanged() {
    if (!mounted || input.text.trim().isEmpty || !inputFocus.hasFocus) return;
    final now = DateTime.now();
    if (now.difference(lastTypingSentAt) < const Duration(seconds: 2)) return;
    lastTypingSentAt = now;
    unawaited(
      _sendControlPayload('typing', {
        'event': 'typing',
        'active': true,
        'time': now.toIso8601String(),
      }).catchError((_) {}),
    );
  }

  Future<void> _sendTypingStopped() async {
    final now = DateTime.now();
    await _sendControlPayload('typing', {
      'event': 'stop',
      'active': false,
      'time': now.toIso8601String(),
    }).catchError((_) {});
  }

  void _showPeerTyping(bool active) {
    typingHideTimer?.cancel();
    if (!mounted) return;
    setState(() => peerTyping = active);
    if (!active) return;
    typingHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => peerTyping = false);
    });
    _bottom(delay: const Duration(milliseconds: 40));
  }

  Future<void> _sendReadReceipt() async {
    final now = DateTime.now();
    if (now.difference(lastReadReceiptSentAt) <
        const Duration(milliseconds: 800)) {
      return;
    }
    final received = messages.where((message) => !message.isMe).toList();
    if (received.isEmpty) return;
    lastReadReceiptSentAt = now;
    final keys = <String>{
      for (final message in received) ..._messageKeys(message),
    };
    await _sendControlPayload('read_receipt', {
      'reader_user_id': widget.session.id,
      'peer_id': widget.peerId,
      'message_keys': keys.toList(),
      'last_read_at': now.toIso8601String(),
    }).catchError((_) {});
  }

  void _applyReadReceipt(ReadReceipt receipt) {
    final keys = receipt.messageKeys;
    final readAt = receipt.readAt;
    setState(() {
      for (final message in messages.where((message) => message.isMe)) {
        final matchedKey =
            keys.isEmpty || _messageKeys(message).any(keys.contains);
        final matchedTime =
            readAt != null && !message.createTime.isAfter(readAt);
        if (matchedKey || matchedTime) {
          messageSendStates[_messageKey(message)] = 'read';
        }
      }
    });
  }

  Future<void> load({bool silent = false}) async {
    final shouldStickAfterSilentLoad = silent && _isNearBottom();
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
        unawaited(_sendReadReceipt());
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('聊天内容暂时无法同步')));
      }
    } finally {
      if (mounted) {
        if (!silent) {
          setState(() => loading = false);
          await _revealMessagesAtBottom();
        } else if (shouldStickAfterSilentLoad) {
          _jumpToBottomAfterLayout();
        }
      }
    }
  }

  void onScroll() {
    if (!scroll.hasClients ||
        loadingHistory ||
        !hasMoreHistory ||
        loading ||
        !readyToShowMessages ||
        _historyLoadBlocked ||
        suppressHistoryDuringProgrammaticScroll)
      return;
    if (!scroll.position.isScrollingNotifier.value) return;
    if (scroll.position.pixels <= 48) unawaited(loadOlderHistory());
  }

  Future<void> loadOlderHistory() async {
    if (loadingHistory || !hasMoreHistory) return;
    final oldMax = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    setState(() => loadingHistory = true);
    var historyChanged = false;
    try {
      final nextPage = historyPage + 1;
      final older = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
        page: nextPage,
      );
      if (mounted) {
        final visibleOlder = older
            .where((m) => !_isHiddenCallSignal(m))
            .toList();
        final merged = _dedupeMessages([...visibleOlder, ...messages]);
        final added = merged.length > messages.length;
        setState(() {
          messages = merged;
          if (added) historyPage = nextPage;
          hasMoreHistory = added && older.length >= 30;
        });
        historyChanged = added;
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('历史消息暂时加载失败')));
    } finally {
      if (mounted) setState(() => loadingHistory = false);
      if (mounted && historyChanged) _restoreScrollAfterHistoryLoad(oldMax);
    }
  }

  void _restoreScrollAfterHistoryLoad(double oldMax) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final delta = scroll.position.maxScrollExtent - oldMax;
      if (delta.abs() < .5) return;
      scroll.jumpTo(
        (scroll.position.pixels + delta).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> clearPeerChatHistory() async {
    try {
      final msg = await api.clearPeerChatHistory(
        token: widget.session.token,
        peerId: widget.peerId,
      );
      if (!mounted) return;
      setState(() {
        messages = [];
        historyPage = 1;
        hasMoreHistory = false;
        readyToShowMessages = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('聊天记录清空失败：$e')));
    }
  }

  Future<void> sendPayload(
    Map<String, dynamic> payload, {
    required String fallbackContent,
    required int messageType,
    bool optimistic = true,
  }) async {
    final local = UnifiedMessage.fromPayload(payload, widget.session.id);
    final key = _messageKey(local);
    if (optimistic) {
      setState(() {
        messageSendStates[key] = 'pending';
        if (!_hasMessage(local)) messages.add(local);
      });
      _bottom();
    }
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: fallbackContent,
        messageType: messageType,
        payload: payload,
      );
      if (mounted) {
        setState(() {
          if (messageSendStates[key] != 'read') {
            messageSendStates[key] = 'success';
          }
          if (!optimistic && !_hasMessage(local)) messages.add(local);
        });
        if (!optimistic) _bottom();
      }
    } catch (e) {
      if (mounted) {
        if (optimistic) setState(() => messageSendStates[key] = 'failed');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('消息暂时没有发送成功：$e')));
      }
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
    unawaited(_sendTypingStopped());
    if (_isEmojiOnly(text)) {
      await sendEmoji(text);
      return;
    } else {
      await sendPayload(
        buildPayload('text', {'text': text}),
        fallbackContent: text,
        messageType: 0,
      );
    }
    if (!isFriend && mounted) setState(() => nonFriendTextSent += 1);
  }

  bool _isEmojiOnly(String text) {
    final value = text.trim();
    if (value.isEmpty || value.length > 16) return false;
    return RegExp(
      r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]+$',
      unicode: true,
    ).hasMatch(value);
  }

  Future<void> sendEmoji(String emoji) async {
    if (!isFriend && nonFriendTextSent >= 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('还不是好友，只能先发送 3 条消息，请先添加好友')));
      return;
    }
    await sendPayload(
      buildPayload('emoji', {'emoji': emoji, 'text': emoji}),
      fallbackContent: emoji,
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
      unawaited(_sendTypingStopped());
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
                  color: BlinStyle.primary,
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
    try {
      final profile = await api.getUserOtherInformation(widget.session.token);
      final coinText = profile.coins.replaceAll(',', '').trim();
      final coins = double.tryParse(coinText) ?? 0;
      if (coins < amountValue) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('金币余额不足')));
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('余额校验失败，请稍后再试')));
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
      optimistic: false,
    );
  }

  Future<void> startCall(bool video) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发起通话')));
      return;
    }
    try {
      await widget.im.ensureConnected().timeout(const Duration(seconds: 10));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在连接消息服务，请稍后再拨打')));
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
    if (mounted) unawaited(load(silent: true));
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
    inputFocus.requestFocus();
  }

  void toggleEmojiPanel() {
    FocusScope.of(context).unfocus();
    setState(() => showEmojiPanel = !showEmojiPanel);
    _settleToBottomAfterLayout();
  }

  void _bottom({Duration delay = const Duration(milliseconds: 80)}) =>
      Future.delayed(delay, () {
        if (!mounted) return;
        _stickToBottom();
        _settleToBottomAfterLayout();
      });

  bool get _historyLoadBlocked =>
      DateTime.now().isBefore(historyLoadBlockedUntil);

  void _blockHistoryLoad([
    Duration duration = const Duration(milliseconds: 900),
  ]) {
    historyLoadBlockedUntil = DateTime.now().add(duration);
  }

  void _handleInputFocus() {
    _blockHistoryLoad();
    stickToBottomDuringKeyboard = _isNearBottom(distance: 220);
    if (stickToBottomDuringKeyboard) {
      _settleKeyboardBottom();
    }
  }

  bool _isNearBottom({double distance = 120}) {
    if (!scroll.hasClients) return true;
    return scroll.position.maxScrollExtent - scroll.position.pixels <= distance;
  }

  Future<void> _waitForLayoutFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<void> _revealMessagesAtBottom() async {
    await _settleToBottomAfterLayout(animated: false);
    setState(() => readyToShowMessages = true);
  }

  void _jumpToBottomAfterLayout() {
    unawaited(_settleToBottomAfterLayout(animated: false));
  }

  Future<void> _settleToBottomAfterLayout({bool animated = false}) async {
    final generation = ++bottomSettleGeneration;
    suppressHistoryDuringProgrammaticScroll = true;
    _blockHistoryLoad(const Duration(milliseconds: 700));
    for (var i = 0; i < 4; i++) {
      await _waitForLayoutFrame();
      if (!mounted || generation != bottomSettleGeneration) return;
      _stickToBottom(animated: animated && i == 3);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted && generation == bottomSettleGeneration) {
        suppressHistoryDuringProgrammaticScroll = false;
      }
    });
  }

  void _settleKeyboardBottom() {
    final generation = ++keyboardSettleGeneration;
    void schedule(Duration delay) {
      Future.delayed(delay, () {
        if (!mounted || generation != keyboardSettleGeneration) return;
        _jumpToBottomAfterLayout();
      });
    }

    schedule(Duration.zero);
    schedule(const Duration(milliseconds: 80));
    schedule(const Duration(milliseconds: 180));
    schedule(const Duration(milliseconds: 320));
  }

  void _stickToBottom({bool animated = true}) {
    if (!scroll.hasClients) return;
    final target = scroll.position.maxScrollExtent;
    if (animated) {
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      scroll.jumpTo(target);
    }
  }

  List<_PeerTimelineItem> _timelineItems() {
    final items = <_PeerTimelineItem>[];
    String? lastDate;
    for (final message in messages) {
      final date = _dateLabel(message.createTime);
      if (date != lastDate) {
        items.add(_PeerTimelineDate(date));
        lastDate = date;
      }
      items.add(_PeerTimelineMessage(message));
    }
    return items;
  }

  String _dateLabel(DateTime time) {
    final now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return '今天';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == time.year &&
        yesterday.month == time.month &&
        yesterday.day == time.day) {
      return '昨天';
    }
    if (now.year == time.year) {
      return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    }
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _blockHistoryLoad();
    if (inputFocus.hasFocus) {
      if (stickToBottomDuringKeyboard || _isNearBottom(distance: 220)) {
        stickToBottomDuringKeyboard = true;
        _settleKeyboardBottom();
      }
    } else {
      stickToBottomDuringKeyboard = false;
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
    unawaited(_sendTypingStopped());
    onlineTimer?.cancel();
    connectionSub?.cancel();
    presenceSub?.cancel();
    typingSub?.cancel();
    readReceiptSub?.cancel();
    sub?.cancel();
    typingHideTimer?.cancel();
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timelineItems();
    final showHistorySlot =
        messages.isNotEmpty && (hasMoreHistory || loadingHistory);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
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
                    onClearHistory: clearPeerChatHistory,
                  ),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const _ChatInitialPane()
                  : Opacity(
                      opacity: readyToShowMessages ? 1 : 0,
                      child: ListView.builder(
                        controller: scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                          BlinStyle.pagePadding,
                          14,
                          BlinStyle.pagePadding,
                          34,
                        ),
                        itemCount:
                            timeline.length +
                            (showHistorySlot ? 1 : 0) +
                            (peerTyping ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (showHistorySlot) {
                            if (peerTyping && i == timeline.length + 1) {
                              return const _TypingBubble();
                            }
                            if (i != 0) {
                              final item = timeline[i - 1];
                              if (item is _PeerTimelineDate) {
                                return _PeerDatePill(text: item.text);
                              }
                              final message =
                                  (item as _PeerTimelineMessage).message;
                              return _Bubble(
                                m: message,
                                sendState:
                                    messageSendStates[_messageKey(message)],
                              );
                            }
                            return _PeerHistoryLoadHint(
                              loading: loadingHistory,
                            );
                          }
                          if (peerTyping && i == timeline.length) {
                            return const _TypingBubble();
                          }
                          final item = timeline[i];
                          if (item is _PeerTimelineDate) {
                            return _PeerDatePill(text: item.text);
                          }
                          final message =
                              (item as _PeerTimelineMessage).message;
                          return _Bubble(
                            m: message,
                            sendState: messageSendStates[_messageKey(message)],
                          );
                        },
                      ),
                    ),
            ),
            _Composer(
              controller: input,
              focusNode: inputFocus,
              sendingAttachment: sendingAttachment,
              showEmojiPanel: showEmojiPanel,
              onSend: send,
              onEmoji: toggleEmojiPanel,
              onEmojiSelected: (emoji) => unawaited(sendEmoji(emoji)),
              onImage: () => unawaited(sendAttachment(mediaType: 'image')),
              onFile: () => unawaited(sendAttachment(mediaType: 'file')),
              onTransfer: () => unawaited(sendTransfer()),
              onVoice: () => startCall(false),
              onVideoCall: () => startCall(true),
            ),
          ],
        ),
      ),
    );
  }
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
    if (online.online)
      return online.device.isNotEmpty ? '在线 · ${online.device}' : '在线';
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                _InfoAvatar(avatar: widget.avatar, name: widget.name),
                const SizedBox(width: 18),
                _AddContactTile(onTap: () => _toast('添加入口已预留')),
              ],
            ),
          ),
          _InfoSection(
            children: [
              _InfoRow(title: '查找聊天记录', onTap: () => _toast('聊天记录搜索入口已预留')),
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
              _InfoRow(title: '投诉', onTap: () => _toast('投诉入口已预留')),
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
                      content: const Text('确定要清空你和对方的聊天记录吗？双方都将不再显示这些消息。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('清空'),
                        ),
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
                  style: const TextStyle(
                    color: Color(0xFF9A9A9A),
                    fontSize: 13,
                  ),
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
    height: 54,
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            size: 26,
            color: Color(0xFF222222),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF222222),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
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
    width: 64,
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 56,
            height: 56,
            color: const Color(0xFF0E6D91),
            child: avatar.isNotEmpty
                ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      name.characters.isEmpty ? '?' : name.characters.first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF222222),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
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
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD8D8D8)),
      ),
      child: const Icon(Icons.add_rounded, size: 34, color: Color(0xFFC6C6C6)),
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
  const _InfoRow({
    required this.title,
    this.trailing,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger ? Colors.red : const Color(0xFF222222),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
            ),
          if (!danger) const SizedBox(width: 8),
          if (!danger)
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFD0D0D0),
              size: 22,
            ),
        ],
      ),
    ),
  );
}

class _InfoSwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _InfoSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF222222),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
        ),
      ],
    ),
  );
}

sealed class _PeerTimelineItem {
  const _PeerTimelineItem();
}

class _PeerTimelineDate extends _PeerTimelineItem {
  final String text;
  const _PeerTimelineDate(this.text);
}

class _PeerTimelineMessage extends _PeerTimelineItem {
  final UnifiedMessage message;
  const _PeerTimelineMessage(this.message);
}

class _PeerDatePill extends StatelessWidget {
  final String text;
  const _PeerDatePill({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: BlinStyle.softFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BlinStyle.line),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BlinStyle.subtle,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
  );
}

class _PeerHistoryLoadHint extends StatelessWidget {
  final bool loading;
  const _PeerHistoryLoadHint({required this.loading});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: loading ? 32 : 0,
    child: Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: loading
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(key: ValueKey('idle')),
      ),
    ),
  );
}

class _ChatInitialPane extends StatelessWidget {
  const _ChatInitialPane();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(
    child: DecoratedBox(decoration: BoxDecoration(color: BlinStyle.bg)),
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
    if (online!.online)
      return '在线${online!.device.isNotEmpty ? ' · ${online!.device}' : ''}';
    return '上次在线时间 ${online!.label}';
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(
      BlinStyle.pagePadding,
      8,
      BlinStyle.pagePadding,
      0,
    ),
    decoration: BoxDecoration(
      color: BlinStyle.bgElevated,
      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
      border: Border.all(color: BlinStyle.line),
      boxShadow: const [BlinStyle.cardShadow],
    ),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_outlined,
                size: BlinStyle.iconSize,
                color: BlinStyle.ink,
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 40,
                height: 40,
                color: BlinStyle.primary,
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          name.characters.isEmpty ? '?' : name.characters.first,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BlinStyle.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
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
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: BlinStyle.iconSize,
                  color: BlinStyle.ink,
                ),
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
  final String? sendState;
  const _Bubble({required this.m, this.sendState});
  @override
  Widget build(BuildContext context) {
    final me = m.isMe;
    final isImage = m.msgType == 'image';
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * (isImage ? .56 : .74),
      ),
      margin: EdgeInsets.fromLTRB(me ? 48 : 8, 5, me ? 4 : 48, 5),
      padding: isImage
          ? const EdgeInsets.all(4)
          : const EdgeInsets.fromLTRB(13, 10, 12, 9),
      decoration: BoxDecoration(
        color: me ? BlinStyle.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(me ? 18 : 6),
          bottomRight: Radius.circular(me ? 6 : 18),
        ),
        border: me ? null : Border.all(color: BlinStyle.line),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      child: _content(context, me),
    );
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: me
            ? [
                bubble,
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: _SendStateIcon(state: sendState ?? 'success'),
                ),
              ]
            : [bubble],
      ),
    );
  }

  Widget _content(BuildContext context, bool me) {
    final color = me ? Colors.white : BlinStyle.ink;
    if (m.msgType == 'image') {
      final text = '${m.content['text'] ?? ''}';
      final url = '${m.content['url'] ?? ''}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty) _ChatImagePreview(url: url),
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
                fontWeight: FontWeight.w400,
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
              color: (me ? Colors.white : BlinStyle.primary).withValues(
                alpha: me ? .18 : .12,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.insert_drive_file_outlined,
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
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
                if (sizeText.isNotEmpty)
                  Text(
                    sizeText.substring(3),
                    style: TextStyle(
                      color: color.withValues(alpha: .72),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
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
    if (m.msgType == 'call_record') {
      return _CallRecordLine(message: m, me: me);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            '${m.content['text'] ?? m.preview}',
            style: TextStyle(
              color: color,
              height: 1.35,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _timeText(m.createTime),
          style: const TextStyle(
            color: BlinStyle.subtle,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
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

class _ChatImagePreview extends StatelessWidget {
  final String url;
  const _ChatImagePreview({required this.url});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .86),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .8,
                maxScale: 4,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    borderRadius: BorderRadius.circular(14),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 160,
        height: 150,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return Container(
              color: BlinStyle.softFill,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Container(
            color: BlinStyle.softFill,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    ),
  );
}

class _CallRecordLine extends StatelessWidget {
  final UnifiedMessage message;
  final bool me;
  const _CallRecordLine({required this.message, required this.me});

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final media = '${content['media']}'.contains('video') ? '视频' : '语音';
    final status = '${content['status']}';
    final callerId = int.tryParse('${content['caller_user_id'] ?? 0}') ?? 0;
    final myUserId = message.isMe ? message.fromUserId : message.toUserId;
    final iAmCaller = callerId > 0 ? callerId == myUserId : me;
    final outgoing = iAmCaller;
    final title = outgoing ? '你拨打的$media通话' : '对方拨打的$media通话';
    final desc = _callRecordDescription(status, content['duration']);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          media == '视频' ? Icons.videocam_outlined : Icons.call_outlined,
          size: 18,
          color: BlinStyle.subtle,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$title · $desc',
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  String _callRecordDescription(String status, Object? duration) {
    if (status == 'finished') return _durationText(duration);
    if (status == 'busy') return '对方忙线';
    if (status == 'missed') return '未接听';
    if (status == 'rejected') return '已拒绝';
    if (status == 'failed') return '连接失败';
    return '已取消';
  }

  String _durationText(Object? value) {
    final total = int.tryParse('$value') ?? 0;
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
}

class _SendStateIcon extends StatelessWidget {
  final String state;
  const _SendStateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == 'pending') {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: BlinStyle.subtle,
        ),
      );
    }
    if (state == 'failed') {
      return const Icon(
        Icons.error_outline_rounded,
        color: BlinStyle.danger,
        size: 15,
      );
    }
    if (state == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        color: BlinStyle.primary,
        size: 15,
      );
    }
    return const Icon(Icons.check_rounded, color: BlinStyle.subtle, size: 14);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.fromLTRB(8, 5, 48, 5),
      padding: const EdgeInsets.fromLTRB(13, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: BlinStyle.line),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _TypingDots(),
          const SizedBox(width: 8),
          Text(
            '正在输入中',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: BlinStyle.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < 3; i++) _dot(i)],
    ),
  );

  Widget _dot(int index) {
    final phase = (controller.value + index * .22) % 1.0;
    final lift = phase < .5 ? phase * 2 : (1 - phase) * 2;
    return Transform.translate(
      offset: Offset(0, -3 * lift),
      child: Container(
        width: 5,
        height: 5,
        margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
        decoration: BoxDecoration(
          color: BlinStyle.subtle.withValues(alpha: .55 + .35 * lift),
          shape: BoxShape.circle,
        ),
      ),
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
  final bool showEmojiPanel;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onImage;
  final VoidCallback onFile;
  final VoidCallback onTransfer;
  final VoidCallback onVoice;
  final VoidCallback onVideoCall;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sendingAttachment,
    required this.showEmojiPanel,
    required this.onSend,
    required this.onEmoji,
    required this.onEmojiSelected,
    required this.onImage,
    required this.onFile,
    required this.onTransfer,
    required this.onVoice,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color: BlinStyle.bgElevated,
        border: const Border(top: BorderSide(color: BlinStyle.line)),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      padding: const EdgeInsets.fromLTRB(
        BlinStyle.pagePadding,
        8,
        BlinStyle.pagePadding,
        8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BlinStyle.softFill,
                    borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
                    border: Border.all(color: BlinStyle.line),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '输入消息',
                      hintStyle: TextStyle(color: BlinStyle.subtle),
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14, color: BlinStyle.ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: BlinStyle.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        BlinStyle.buttonRadius,
                      ),
                    ),
                  ),
                  child: const Text(
                    '发送',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ComposerTool(
                  icon: Icons.emoji_emotions_outlined,
                  label: '表情',
                  onTap: onEmoji,
                ),
                _ComposerTool(
                  icon: Icons.image_outlined,
                  label: '图片',
                  onTap: sendingAttachment ? null : onImage,
                ),
                _ComposerTool(
                  icon: Icons.attach_file_outlined,
                  label: '文件',
                  onTap: sendingAttachment ? null : onFile,
                ),
                _ComposerTool(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '转账',
                  onTap: onTransfer,
                ),
                _ComposerTool(
                  icon: Icons.call_outlined,
                  label: '语音',
                  onTap: onVoice,
                ),
                _ComposerTool(
                  icon: Icons.videocam_outlined,
                  label: '视频',
                  onTap: onVideoCall,
                ),
              ],
            ),
          ),
          if (showEmojiPanel) _InlineEmojiPanel(onEmoji: onEmojiSelected),
        ],
      ),
    ),
  );
}

class _InlineEmojiPanel extends StatelessWidget {
  final ValueChanged<String> onEmoji;
  const _InlineEmojiPanel({required this.onEmoji});

  static const emojis = [
    '😀',
    '😂',
    '😊',
    '😍',
    '🥰',
    '😭',
    '😎',
    '👍',
    '👏',
    '🙏',
    '🎉',
    '🔥',
    '❤️',
    '💪',
    '🤔',
    '😅',
    '😡',
    '😴',
    '😋',
    '👌',
    '🌹',
    '🍻',
    '✨',
    '💯',
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: 146,
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    decoration: BoxDecoration(
      color: BlinStyle.softFill,
      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
    ),
    child: GridView.builder(
      itemCount: emojis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, i) => InkWell(
        onTap: () => onEmoji(emojis[i]),
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
        ),
      ),
    ),
  );
}

class _ComposerTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ComposerTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      child: Container(
        width: 58,
        height: 54,
        decoration: BoxDecoration(
          color: BlinStyle.softFill,
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          border: Border.all(color: BlinStyle.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: BlinStyle.primary, size: BlinStyle.iconSize),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: BlinStyle.muted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// More actions are now shown in the horizontal composer toolbar.
