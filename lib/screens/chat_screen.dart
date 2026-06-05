import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import '../widgets/blin_style.dart';

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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
      }
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
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _ChatHeader(
              name: widget.peerName,
              avatar: widget.peerAvatar,
              online: peerOnline,
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(m: messages[i]),
                  ),
          ),
          _Composer(controller: input, onSend: send),
        ],
      ),
    ),
  );
}

class _ChatHeader extends StatelessWidget {
  final String name;
  final String avatar;
  final bool? online;
  const _ChatHeader({
    required this.name,
    required this.avatar,
    required this.online,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 14, 8),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        CircleAvatar(
          radius: 22,
          backgroundImage: avatar.isNotEmpty
              ? CachedNetworkImageProvider(avatar)
              : null,
          child: avatar.isEmpty ? Text(name.characters.first) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                online == null ? '检测在线状态...' : (online! ? '实时在线' : '暂时离线'),
                style: TextStyle(
                  color: online == true ? BlinStyle.green : BlinStyle.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const GradientIcon(
          icon: Icons.more_horiz_rounded,
          size: 40,
          iconSize: 22,
        ),
      ],
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
          maxWidth: MediaQuery.sizeOf(context).width * .74,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: me ? BlinStyle.brandGradient : null,
          color: me ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(me ? 20 : 5),
            bottomRight: Radius.circular(me ? 5 : 20),
          ),
          boxShadow: [BlinStyle.softShadow(.05)],
        ),
        child: _content(me),
      ),
    );
  }

  Widget _content(bool me) {
    final color = me ? Colors.white : BlinStyle.ink;
    if (m.msgType == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${m.content['url'] ?? ''}'.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      );
    }
    return Text(
      '${m.content['text'] ?? m.preview}',
      style: TextStyle(
        color: color,
        height: 1.35,
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
      ),
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
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BlinStyle.softShadow(.08)],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: BlinStyle.ink,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: '回复消息...'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSend,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(13),
            ),
            child: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    ),
  );
}
