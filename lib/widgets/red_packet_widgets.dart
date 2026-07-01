import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/im_models.dart';
import 'blin_style.dart';

class RedPacketDraft {
  final String amount;
  final String greeting;
  final int count;
  final String packetType;

  const RedPacketDraft({
    required this.amount,
    required this.greeting,
    this.count = 1,
    this.packetType = 'normal',
  });
}

String? normalizeRedPacketAmount(String raw) {
  var value = raw
      .replaceAll('，', '.')
      .replaceAll(',', '.')
      .replaceAll('。', '.')
      .trim();
  value = value.replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed.toStringAsFixed(2);
}

String redPacketGreeting(Map<String, dynamic> content) {
  final text = '${content['greeting'] ?? content['note'] ?? ''}'.trim();
  return text.isEmpty ? '恭喜发财，大吉大利' : text;
}

int redPacketIdFromMessage(UnifiedMessage message) =>
    int.tryParse(
      '${_firstRedPacketField(message, const ['red_packet_id', 'packet_id', 'redpacket_id']) ?? 0}',
    ) ??
    0;

int redPacketMessageIdFromMessage(UnifiedMessage message) {
  if (message.messageId > 0) return message.messageId;
  return int.tryParse(
        '${_firstRedPacketField(message, const ['message_id', 'msg_id']) ?? 0}',
      ) ??
      0;
}

String redPacketClientMsgNoFromMessage(UnifiedMessage message) =>
    '${_firstRedPacketField(message, const ['client_msg_no', 'clientMsgNo']) ?? ''}'
        .trim();

Object? _firstRedPacketField(UnifiedMessage message, List<String> keys) {
  for (final source in _redPacketSources(message)) {
    for (final key in keys) {
      final value = source[key];
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return value;
    }
  }
  return null;
}

Iterable<Map<String, dynamic>> _redPacketSources(UnifiedMessage message) sync* {
  yield message.content;
  final contentPacket = _asRedPacketMap(message.content['red_packet']);
  if (contentPacket.isNotEmpty) yield contentPacket;
  final contentLegacyPacket = _asRedPacketMap(message.content['packet']);
  if (contentLegacyPacket.isNotEmpty) yield contentLegacyPacket;
  yield message.raw;
  final rawPacket = _asRedPacketMap(message.raw['red_packet']);
  if (rawPacket.isNotEmpty) yield rawPacket;
  final rawLegacyPacket = _asRedPacketMap(message.raw['packet']);
  if (rawLegacyPacket.isNotEmpty) yield rawLegacyPacket;
  final rawContent = _asRedPacketMap(message.raw['content']);
  if (rawContent.isNotEmpty) {
    yield rawContent;
    final rawContentPacket = _asRedPacketMap(rawContent['red_packet']);
    if (rawContentPacket.isNotEmpty) yield rawContentPacket;
    final rawContentLegacyPacket = _asRedPacketMap(rawContent['packet']);
    if (rawContentLegacyPacket.isNotEmpty) yield rawContentLegacyPacket;
  }
  final legacy = _asRedPacketMap(message.raw['legacy']);
  if (legacy.isNotEmpty) yield legacy;
  final messageMap = _asRedPacketMap(message.raw['_message']);
  if (messageMap.isNotEmpty) {
    yield messageMap;
    final messagePacket = _asRedPacketMap(messageMap['red_packet']);
    if (messagePacket.isNotEmpty) yield messagePacket;
    final messageLegacyPacket = _asRedPacketMap(messageMap['packet']);
    if (messageLegacyPacket.isNotEmpty) yield messageLegacyPacket;
  }
  final payloadMap = _asRedPacketMap(message.raw['_payload']);
  if (payloadMap.isNotEmpty) {
    yield payloadMap;
    final payloadContent = _asRedPacketMap(payloadMap['content']);
    if (payloadContent.isNotEmpty) yield payloadContent;
  }
  final data = _asRedPacketMap(message.raw['data']);
  if (data.isNotEmpty) {
    yield data;
    final dataPacket = _asRedPacketMap(data['red_packet']);
    if (dataPacket.isNotEmpty) yield dataPacket;
    final dataLegacyPacket = _asRedPacketMap(data['packet']);
    if (dataLegacyPacket.isNotEmpty) yield dataLegacyPacket;
    final dataClaim = _asRedPacketMap(data['claim']);
    if (dataClaim.isNotEmpty) yield dataClaim;
  }
}

Map<String, dynamic> _asRedPacketMap(Object? value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String redPacketStatus(Map<String, dynamic> content) {
  final raw = _firstRedPacketText(content, const [
    'status',
    'state',
    'packet_status',
    'red_packet_status',
    'claim_status',
    'receive_status',
    'status_text',
  ]).toLowerCase();
  final claim = _asRedPacketMap(content['claim']);
  if (claim.isNotEmpty && redPacketClaimedByMe({...content, ...claim})) {
    return 'finished';
  }
  if (const {
    'finished',
    'finish',
    'done',
    'empty',
    'completed',
    'complete',
    '已领完',
    '已完成',
  }.contains(raw)) {
    return 'finished';
  }
  if (const {
    'refunded',
    'refund',
    'returned',
    'expired',
    'timeout',
    'overdue',
    '已退回',
    '已过期',
  }.contains(raw)) {
    return 'refunded';
  }
  if (raw == '1') return 'finished';
  if (raw == '2' || raw == '3') return 'refunded';
  return 'pending';
}

bool redPacketClaimedByMe(Map<String, dynamic> content) {
  final claim = _asRedPacketMap(content['claim']);
  final raw =
      content['claimed_by_me'] ??
      content['is_claimed'] ??
      content['claimed'] ??
      content['received'] ??
      content['has_claimed'] ??
      claim['claimed_by_me'] ??
      claim['is_claimed'] ??
      claim['claimed'] ??
      claim['received'];
  final text = '$raw'.trim().toLowerCase();
  if (raw == true ||
      text == '1' ||
      text == 'true' ||
      text == 'yes' ||
      text == 'claimed' ||
      text == 'received') {
    return true;
  }
  final amount =
      '${content['my_claim_amount'] ?? content['claim_amount'] ?? content['receive_amount'] ?? claim['amount'] ?? claim['money'] ?? claim['receive_amount'] ?? ''}'
          .trim();
  return amount.isNotEmpty && amount != '0' && amount != '0.00';
}

String _firstRedPacketText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null' && text != '0') return text;
  }
  final packet = _asRedPacketMap(source['red_packet']);
  if (packet.isNotEmpty) return _firstRedPacketText(packet, keys);
  final legacyPacket = _asRedPacketMap(source['packet']);
  if (legacyPacket.isNotEmpty) return _firstRedPacketText(legacyPacket, keys);
  final claim = _asRedPacketMap(source['claim']);
  if (claim.isNotEmpty) return _firstRedPacketText(claim, keys);
  return '';
}

Future<RedPacketDraft?> showRedPacketDraftSheet(
  BuildContext context, {
  required bool group,
}) async {
  final amountController = TextEditingController();
  final greetingController = TextEditingController(text: '恭喜发财，大吉大利');
  final countController = TextEditingController(text: group ? '3' : '1');
  var packetType = 'lucky';
  final result = await showModalBottomSheet<RedPacketDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .26),
    builder: (sheetContext) {
      final bottom = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
          child: SoftCard(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF2DE),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.redeem_rounded,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group ? '发群红包' : '发红包',
                            style: const TextStyle(
                              color: BlinStyle.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            group ? '支持拼手气和普通红包' : '对方领取后才会入账',
                            style: const TextStyle(
                              color: BlinStyle.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (group) ...[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: BlinStyle.softFill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _RedPacketTypeChoice(
                          selected: packetType == 'lucky',
                          label: '拼手气',
                          onTap: () =>
                              setSheetState(() => packetType = 'lucky'),
                        ),
                        _RedPacketTypeChoice(
                          selected: packetType == 'normal',
                          label: '普通',
                          onTap: () =>
                              setSheetState(() => packetType = 'normal'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _RedPacketInput(
                  controller: amountController,
                  label: '金额',
                  prefix: '¥ ',
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                  ],
                ),
                if (group) ...[
                  const SizedBox(height: 12),
                  _RedPacketInput(
                    controller: countController,
                    label: '红包个数',
                    suffix: '个',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
                const SizedBox(height: 12),
                _RedPacketInput(
                  controller: greetingController,
                  label: '祝福语',
                  maxLength: 80,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          final amount = normalizeRedPacketAmount(
                            amountController.text,
                          );
                          if (amount == null) {
                            HapticFeedback.selectionClick();
                            return;
                          }
                          final count = group
                              ? math.max(
                                  1,
                                  int.tryParse(countController.text.trim()) ??
                                      1,
                                )
                              : 1;
                          Navigator.pop(
                            sheetContext,
                            RedPacketDraft(
                              amount: amount,
                              greeting: greetingController.text.trim().isEmpty
                                  ? '恭喜发财，大吉大利'
                                  : greetingController.text.trim(),
                              count: count,
                              packetType: group ? packetType : 'normal',
                            ),
                          );
                        },
                        icon: const Icon(Icons.redeem_rounded),
                        label: const Text('塞钱进红包'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  amountController.dispose();
  greetingController.dispose();
  countController.dispose();
  return result;
}

class _RedPacketTypeChoice extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _RedPacketTypeChoice({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected ? const [BlinStyle.cardShadow] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? BlinStyle.ink : BlinStyle.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _RedPacketInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String prefix;
  final String suffix;
  final bool autofocus;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _RedPacketInput({
    required this.controller,
    required this.label,
    this.prefix = '',
    this.suffix = '',
    this.autofocus = false,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLength: maxLength,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    decoration: InputDecoration(
      labelText: label,
      prefixText: prefix.isEmpty ? null : prefix,
      suffixText: suffix.isEmpty ? null : suffix,
      counterText: '',
      filled: true,
      fillColor: BlinStyle.softFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: BlinStyle.primary.withValues(alpha: .55)),
      ),
    ),
  );
}

class RedPacketCard extends StatelessWidget {
  final UnifiedMessage message;
  final bool me;
  final VoidCallback? onTap;

  const RedPacketCard({
    super.key,
    required this.message,
    required this.me,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final status = redPacketStatus(content);
    final claimed = redPacketClaimedByMe(content);
    final disabled = status == 'finished' || status == 'refunded' || claimed;
    final scope = '${content['scope'] ?? ''}';
    final typeLabel =
        '${content['packet_type_label'] ?? (scope == 'group' ? '群红包' : '红包')}';
    final greeting = redPacketGreeting(content);
    final subtitle = status == 'refunded'
        ? '已过期退回'
        : status == 'finished'
        ? '已领完'
        : claimed
        ? '已领取'
        : typeLabel;
    final handleTap = onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onTap!();
          };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: handleTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 244,
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFFFF1E7) : null,
            gradient: disabled
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF4B45), Color(0xFFFF6A21)],
                  ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE94234).withValues(alpha: .18),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: disabled
                            ? const Color(0xFFFFDDBE)
                            : const Color(0xFFE73532),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.redeem_rounded,
                        color: disabled
                            ? const Color(0xFFC87331)
                            : const Color(0xFFFFD684),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            typeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: disabled
                                  ? const Color(0xFFA75B34)
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            greeting,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: disabled
                                  ? const Color(0xFFB87754)
                                  : Colors.white.withValues(alpha: .88),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFE2A5),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        disabled ? '已' : '开',
                        style: const TextStyle(
                          color: Color(0xFFE73532),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                color: Colors.white.withValues(alpha: .88),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB76437),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      scope == 'group' ? '群红包' : '红包',
                      style: const TextStyle(
                        color: Color(0xFFB76437),
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
      ),
    );
  }
}

Future<void> showRedPacketOpenDialog(
  BuildContext context, {
  required UnifiedMessage message,
  required Future<Map<String, dynamic>> Function() onOpen,
  Future<Map<String, dynamic>> Function()? onLoadDetail,
  required ValueChanged<Map<String, dynamic>> onUpdate,
  ValueChanged<Map<String, dynamic>>? onOpened,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .45),
    builder: (_) => _RedPacketOpenDialog(
      message: message,
      onOpen: onOpen,
      onLoadDetail: onLoadDetail,
      onUpdate: onUpdate,
      onOpened: onOpened,
    ),
  );
}

class _RedPacketOpenDialog extends StatefulWidget {
  final UnifiedMessage message;
  final Future<Map<String, dynamic>> Function() onOpen;
  final Future<Map<String, dynamic>> Function()? onLoadDetail;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final ValueChanged<Map<String, dynamic>>? onOpened;

  const _RedPacketOpenDialog({
    required this.message,
    required this.onOpen,
    this.onLoadDetail,
    required this.onUpdate,
    this.onOpened,
  });

  @override
  State<_RedPacketOpenDialog> createState() => _RedPacketOpenDialogState();
}

class _RedPacketOpenDialogState extends State<_RedPacketOpenDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  bool opening = false;
  Map<String, dynamic>? detail;
  String error = '';

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
  }

  bool _claimedByMe(Map<String, dynamic> packet) {
    final claim = detail?['claim'] is Map
        ? Map<String, dynamic>.from(detail!['claim'] as Map)
        : const <String, dynamic>{};
    final amount = '${claim['amount'] ?? packet['my_claim_amount'] ?? ''}'
        .trim();
    return amount.isNotEmpty || redPacketClaimedByMe(packet);
  }

  bool _canViewDetail(Map<String, dynamic> packet) =>
      widget.message.isMe || _claimedByMe(packet);

  Future<void> showDetail(Map<String, dynamic> packet) async {
    Map<String, dynamic>? loaded = detail;
    if (widget.onLoadDetail != null) {
      try {
        loaded = await widget.onLoadDetail!();
        final updatedPacket = loaded['red_packet'] is Map
            ? Map<String, dynamic>.from(loaded['red_packet'] as Map)
            : <String, dynamic>{};
        if (updatedPacket.isNotEmpty) {
          widget.onUpdate(loaded);
          if (mounted) {
            setState(() => detail = loaded);
          }
          packet = updatedPacket;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
        return;
      }
    }
    if (!mounted) return;
    if (!_canViewDetail(packet)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('领取后才能查看详情')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RedPacketDetailScreen(packet: packet, detail: loaded),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> open() async {
    if (opening) return;
    final packet = _packetFromDetail(widget.message.content, detail);
    if (_claimedByMe(packet) || redPacketStatus(packet) != 'pending') return;
    setState(() {
      opening = true;
      error = '';
    });
    unawaited(controller.repeat());
    try {
      final data = await widget.onOpen();
      if (!mounted) return;
      controller.stop();
      controller.reset();
      widget.onUpdate(data);
      widget.onOpened?.call(data);
      setState(() {
        detail = data;
        opening = false;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      controller.stop();
      controller.reset();
      setState(() {
        error = '$e';
        opening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.message.content;
    final packet = _packetFromDetail(content, detail);
    final claim = detail?['claim'] is Map
        ? Map<String, dynamic>.from(detail!['claim'] as Map)
        : const <String, dynamic>{};
    final amount = '${claim['amount'] ?? packet['my_claim_amount'] ?? ''}'
        .trim();
    final status = redPacketStatus(packet);
    final greeting = redPacketGreeting(packet);
    final claimed = _claimedByMe(packet);
    final canViewDetail = _canViewDetail(packet);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFD8472F),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .22),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: -80,
              right: -80,
              top: -170,
              child: Container(
                height: 280,
                decoration: const BoxDecoration(
                  color: Color(0xFFE95A3F),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFFFFE1AA),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDA8A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.redeem_rounded,
                      color: Color(0xFF9A3E1B),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    greeting,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE7B8),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status == 'refunded'
                        ? '红包已过期退回'
                        : status == 'finished' && !claimed
                        ? '红包已被领完'
                        : claimed
                        ? '已领取'
                        : '领取后自动入账到钱包',
                    style: TextStyle(
                      color: const Color(0xFFFFE7B8).withValues(alpha: .82),
                      fontSize: 13,
                    ),
                  ),
                  if (amount.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      '¥$amount',
                      style: const TextStyle(
                        color: Color(0xFFFFF2D2),
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => showDetail(packet),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFE7B8),
                    ),
                    child: const Text('查看领取详情'),
                  ),
                  if (!canViewDetail)
                    Text(
                      '未领取前不可查看领取记录',
                      style: TextStyle(
                        color: const Color(0xFFFFE7B8).withValues(alpha: .68),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFE1AA),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!claimed && status == 'pending')
                    GestureDetector(
                      onTap: open,
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, child) => Transform.rotate(
                          angle: opening ? controller.value * math.pi * 2 : 0,
                          child: child,
                        ),
                        child: Container(
                          width: 82,
                          height: 82,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD36B),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            opening ? '开' : '开',
                            style: const TextStyle(
                              color: Color(0xFF8C3A19),
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD36B),
                          foregroundColor: const Color(0xFF8C3A19),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('知道了'),
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

Map<String, dynamic> _packetFromDetail(
  Map<String, dynamic> fallback,
  Map<String, dynamic>? detail,
) {
  final packet = detail?['red_packet'] is Map
      ? Map<String, dynamic>.from(detail!['red_packet'] as Map)
      : detail?['packet'] is Map
      ? Map<String, dynamic>.from(detail!['packet'] as Map)
      : <String, dynamic>{};
  final claim = detail?['claim'] is Map
      ? Map<String, dynamic>.from(detail!['claim'] as Map)
      : <String, dynamic>{};
  final merged = <String, dynamic>{...fallback, ...packet};
  if (detail != null) {
    for (final key in const [
      'status',
      'state',
      'packet_status',
      'red_packet_status',
      'claim_status',
      'receive_status',
      'claimed_by_me',
      'is_claimed',
      'my_claim_amount',
      'claim_amount',
      'receive_amount',
      'remaining_count',
      'claimed_count',
      'remaining_amount',
    ]) {
      final value = detail[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        merged[key] = value;
      }
    }
  }
  if (claim.isNotEmpty) {
    merged['claim'] = claim;
    merged['claimed_by_me'] = true;
    merged['is_claimed'] = true;
    merged['claim_amount'] =
        claim['amount'] ?? claim['money'] ?? claim['receive_amount'] ?? '';
    merged['my_claim_amount'] =
        claim['amount'] ?? claim['money'] ?? claim['receive_amount'] ?? '';
  }
  return merged;
}

class RedPacketDetailScreen extends StatelessWidget {
  final Map<String, dynamic> packet;
  final Map<String, dynamic>? detail;

  const RedPacketDetailScreen({super.key, required this.packet, this.detail});

  List<Map<String, dynamic>> get claims {
    final source = packet['claims'] ?? detail?['claims'];
    if (source is List) {
      return source
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  String _text(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = packet[key] ?? detail?[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return fallback;
  }

  int _int(List<String> keys) {
    for (final key in keys) {
      final value = packet[key] ?? detail?[key];
      final parsed = int.tryParse('$value');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String get greeting => redPacketGreeting(packet);

  String get totalAmount => _text(['total_amount', 'amount'], '0.00');

  String get remainingAmount => _text(['remaining_amount'], '0.00');

  String get moneyType => _text(['money_type']) == '1' ? '积分' : '金币';

  String get packetTypeLabel => _text([
    'packet_type_label',
  ], _text(['packet_type']) == 'lucky' ? '拼手气红包' : '普通红包');

  int get totalCount => _int(['total_count', 'count']);

  int get remainingCount => _int(['remaining_count']);

  int get claimedCount {
    final value = _int(['claimed_count']);
    if (value > 0) return value;
    if (totalCount > 0) return math.max(0, totalCount - remainingCount);
    return claims.length;
  }

  String get statusLabel {
    final status = redPacketStatus(packet);
    if (status == 'finished') return '已领完';
    if (status == 'refunded') return '已过期退回';
    return '领取中';
  }

  @override
  Widget build(BuildContext context) {
    final claimList = claims;
    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '红包领取详情',
              subtitle: statusLabel,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  children: [
                    SoftCard(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF2DE),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.redeem_rounded,
                                  color: Color(0xFFD97706),
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      greeting,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: BlinStyle.textPrimary(context),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        height: 1.22,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$packetTypeLabel · $statusLabel',
                                      style: TextStyle(
                                        color: BlinStyle.textSecondary(context),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _RedPacketSummaryTile(
                                  label: '红包金额',
                                  value: totalAmount,
                                  unit: moneyType,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _RedPacketSummaryTile(
                                  label: '领取进度',
                                  value: totalCount > 0
                                      ? '$claimedCount/$totalCount'
                                      : '$claimedCount',
                                  unit: '个',
                                ),
                              ),
                            ],
                          ),
                          if (remainingAmount.isNotEmpty &&
                              redPacketStatus(packet) != 'finished') ...[
                            const SizedBox(height: 10),
                            _RedPacketSummaryTile(
                              label: '剩余金额',
                              value: remainingAmount,
                              unit: moneyType,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SoftCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
                            child: Text(
                              '领取记录',
                              style: TextStyle(
                                color: BlinStyle.textPrimary(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (claimList.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                              child: Text(
                                '暂时还没有人领取',
                                style: TextStyle(
                                  color: BlinStyle.textSecondary(context),
                                  fontSize: 14,
                                ),
                              ),
                            )
                          else
                            for (var i = 0; i < claimList.length; i++)
                              _RedPacketClaimRow(
                                claim: claimList[i],
                                moneyType: moneyType,
                                showDivider: i != claimList.length - 1,
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedPacketSummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool compact;

  const _RedPacketSummaryTile({
    required this.label,
    required this.value,
    required this.unit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 14 : 13,
      vertical: compact ? 12 : 13,
    ),
    decoration: BoxDecoration(
      color: BlinStyle.softFill,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: BlinStyle.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(
              color: BlinStyle.textPrimary(context),
              fontSize: compact ? 18 : 20,
              fontWeight: FontWeight.w900,
            ),
            children: [
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  color: BlinStyle.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RedPacketClaimRow extends StatelessWidget {
  final Map<String, dynamic> claim;
  final String moneyType;
  final bool showDivider;

  const _RedPacketClaimRow({
    required this.claim,
    required this.moneyType,
    required this.showDivider,
  });

  String _pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = claim[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = _pick(['nickname', 'name', 'username'], '用户');
    final avatar = _pick(['avatar', 'usertx', 'headimg']);
    final amount = _pick(['amount'], '0.00');
    final time = _pick(['create_time_text', 'created_at', 'time']);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              AppAvatar(imageUrl: avatar, name: name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: BlinStyle.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BlinStyle.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$amount $moneyType',
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 70),
            child: Divider(
              height: 1,
              thickness: 1,
              color: BlinStyle.hairline(context, .55).color,
            ),
          ),
      ],
    );
  }
}
