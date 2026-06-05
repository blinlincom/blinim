import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final api = const ApiService();
  final input = TextEditingController();
  final scroll = ScrollController();
  List<UnifiedMessage> messages = [];
  bool loading = true;
  bool? peerOnline;
  StreamSubscription? sub;
  StreamSubscription? presenceSub;

  @override
  void initState() {
    super.initState();
    load();
    sub = widget.im.messages.listen((m) {
      if (m.fromUserId == widget.peerId || m.toUserId == widget.peerId) {
        setState(() {
          messages.add(m);
          if (m.fromUserId == widget.peerId) peerOnline = true;
        });
        _bottom();
      }
    });
    presenceSub = widget.im.presences.listen((p) {
      if (p.userId == widget.peerId) setState(() => peerOnline = p.online);
    });
    refreshPeerOnline();
  }

  Future<void> refreshPeerOnline() async {
    try {
      final online = await api.getImOnlineStatus(
        token: widget.session.token,
        userId: widget.peerId,
      );
      if (mounted) setState(() => peerOnline = online);
    } catch (_) {
      if (mounted) setState(() => peerOnline = false);
    }
  }

  Future<void> load() async {
    try {
      final r = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
      );
      if (mounted) setState(() => messages = r);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => loading = false);
      _bottom();
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    final optimistic = UnifiedMessage.fromPayload({
      'message_id': 0,
      'from_user_id': widget.session.id,
      'to_user_id': widget.peerId,
      'from_uid': '',
      'to_uid': '',
      'msg_type': 'text',
      'content': {'text': text},
      'create_time': DateTime.now().toIso8601String(),
    }, widget.session.id);
    setState(() => messages.add(optimistic));
    _bottom();
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: text,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    }
  }

  void _bottom() => Future.delayed(const Duration(milliseconds: 80), () {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  });

  @override
  void dispose() {
    presenceSub?.cancel();
    sub?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.peerAvatar.isNotEmpty
                  ? CachedNetworkImageProvider(widget.peerAvatar)
                  : null,
              child: widget.peerAvatar.isEmpty
                  ? Text(widget.peerName.characters.first)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    peerOnline == null
                        ? '检测在线状态...'
                        : (peerOnline! ? '对方在线' : '对方离线'),
                    style: TextStyle(
                      fontSize: 12,
                      color: peerOnline == true ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(m: messages[i]),
                  ),
          ),
          _Composer(controller: input, onSend: send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final UnifiedMessage m;
  const _Bubble({required this.m});

  @override
  Widget build(BuildContext context) {
    final me = m.isMe;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .74,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: me ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(me ? 20 : 6),
            bottomRight: Radius.circular(me ? 6 : 20),
          ),
        ),
        child: _content(context, me),
      ),
    );
  }

  Widget _content(BuildContext context, bool me) {
    final scheme = Theme.of(context).colorScheme;
    final color = me ? scheme.onPrimary : scheme.onSurface;
    if (m.msgType == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${m.content['url'] ?? ''}'.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network('${m.content['url']}'),
            ),
          if ('${m.content['text'] ?? ''}'.isNotEmpty)
            Text('${m.content['text']}', style: TextStyle(color: color)),
        ],
      );
    }
    if (m.msgType == 'transfer') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_rounded, color: color),
          const SizedBox(width: 8),
          Text(
            '转账 ${m.content['amount'] ?? ''}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      );
    }
    return Text(
      '${m.content['text'] ?? m.preview}',
      style: TextStyle(color: color, height: 1.35, fontSize: 15.5),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: '发送消息...'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    ),
  );
}
