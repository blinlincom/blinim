import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
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
  ImOnlineStatus? peerOnline;
  bool sendingAttachment = false;
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  StreamSubscription? connectionSub;
  Timer? onlineTimer;

  @override
  void initState() {
    super.initState();
    load();
    sub = widget.im.messages.listen((m) {
      if (m.fromUserId == widget.peerId || m.toUserId == widget.peerId) {
        setState(() {
          messages.add(m);
          if (m.fromUserId == widget.peerId) {
            peerOnline = const ImOnlineStatus(online: true, device: '');
          }
        });
        _bottom();
      }
    });
    presenceSub = widget.im.presences.listen((p) {
      if (p.userId == widget.peerId) {
        setState(
          () => peerOnline = ImOnlineStatus(online: p.online, device: p.device),
        );
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
      if (mounted) setState(() => peerOnline = status);
    } catch (_) {
      if (mounted)
        setState(() => peerOnline = const ImOnlineStatus(online: false));
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
        ).showSnackBar(const SnackBar(content: Text('聊天内容暂时无法同步')));
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
    final payload = {
      'message_id': 0,
      'from_user_id': widget.session.id,
      'to_user_id': widget.peerId,
      'from_uid': '',
      'to_uid': '',
      'msg_type': 'text',
      'content': {'text': text},
      'create_time': DateTime.now().toIso8601String(),
    };
    setState(
      () =>
          messages.add(UnifiedMessage.fromPayload(payload, widget.session.id)),
    );
    _bottom();
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: text,
        payload: payload,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('消息暂时没有发送成功')));
      }
    }
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

  Future<void> sendAttachment({required bool image}) async {
    if (sendingAttachment) return;
    final result = await FilePicker.platform.pickFiles(
      type: image ? FileType.image : FileType.any,
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
      final type = image ? 'image' : 'file';
      final payload = {
        'message_id': 0,
        'from_user_id': widget.session.id,
        'to_user_id': widget.peerId,
        'from_uid': '',
        'to_uid': '',
        'msg_type': type,
        'content': {
          'url': url,
          'name': file.name,
          'size': file.size,
          if (image) 'text': input.text.trim(),
        },
        'create_time': DateTime.now().toIso8601String(),
      };
      input.clear();
      setState(
        () => messages.add(
          UnifiedMessage.fromPayload(payload, widget.session.id),
        ),
      );
      _bottom();
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: image ? '[图片]' : '[文件] ${file.name}',
        messageType: image ? 1 : 3,
        payload: payload,
      );
      await widget.im.sendDirect(
        channelId: 'user_${widget.peerId}',
        payload: payload,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(image ? '图片发送失败：$e' : '文件发送失败：$e')),
        );
    } finally {
      if (mounted) setState(() => sendingAttachment = false);
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
  }

  Future<void> openMorePanel() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatMorePanel(
        onImage: () {
          Navigator.pop(context);
          unawaited(sendAttachment(image: true));
        },
        onFile: () {
          Navigator.pop(context);
          unawaited(sendAttachment(image: false));
        },
        onEmoji: (emoji) {
          Navigator.pop(context);
          addEmoji(emoji);
        },
      ),
    );
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
    onlineTimer?.cancel();
    connectionSub?.cancel();
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
                ? const _ChatHistorySkeleton()
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(m: messages[i]),
                  ),
          ),
          _Composer(
            controller: input,
            sendingAttachment: sendingAttachment,
            onMore: openMorePanel,
            onSend: send,
          ),
        ],
      ),
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
                online == null ? '检测在线状态...' : online!.label,
                style: TextStyle(
                  color: online?.online == true
                      ? BlinStyle.green
                      : BlinStyle.muted,
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
  final bool sendingAttachment;
  final VoidCallback onMore;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sendingAttachment,
    required this.onMore,
    required this.onSend,
  });
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
            onPressed: sendingAttachment ? null : onMore,
            icon: sendingAttachment
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(
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

class _ChatMorePanel extends StatelessWidget {
  final VoidCallback onImage;
  final VoidCallback onFile;
  final ValueChanged<String> onEmoji;
  const _ChatMorePanel({
    required this.onImage,
    required this.onFile,
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
                const SizedBox(width: 14),
                _MoreAction(
                  icon: Icons.attach_file_rounded,
                  label: '文件',
                  onTap: onFile,
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
