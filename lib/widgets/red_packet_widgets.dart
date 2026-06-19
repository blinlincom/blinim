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
      '${message.content['red_packet_id'] ?? message.content['id'] ?? 0}',
    ) ??
    0;

String redPacketStatus(Map<String, dynamic> content) =>
    '${content['status'] ?? 'pending'}'.trim().toLowerCase();

bool redPacketClaimedByMe(Map<String, dynamic> content) {
  final raw = content['claimed_by_me'];
  return raw == true || '$raw' == '1' || '$raw'.toLowerCase() == 'true';
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFFFF3DE) : const Color(0xFFFF9F2D),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD97706).withValues(alpha: .14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE7B0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.redeem_rounded,
                      color: disabled
                          ? const Color(0xFFD49A47)
                          : const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: disabled
                                ? const Color(0xFF9A6A24)
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: disabled
                                ? const Color(0xFFB58A4A)
                                : Colors.white.withValues(alpha: .88),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
              color: Colors.white.withValues(alpha: .82),
              child: Text(
                scope == 'group' ? 'Blin 群红包' : 'Blin 红包',
                style: const TextStyle(
                  color: Color(0xFF9A6A24),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showRedPacketOpenDialog(
  BuildContext context, {
  required UnifiedMessage message,
  required Future<Map<String, dynamic>> Function() onOpen,
  required ValueChanged<Map<String, dynamic>> onUpdate,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .45),
    builder: (_) => _RedPacketOpenDialog(
      message: message,
      onOpen: onOpen,
      onUpdate: onUpdate,
    ),
  );
}

class _RedPacketOpenDialog extends StatefulWidget {
  final UnifiedMessage message;
  final Future<Map<String, dynamic>> Function() onOpen;
  final ValueChanged<Map<String, dynamic>> onUpdate;

  const _RedPacketOpenDialog({
    required this.message,
    required this.onOpen,
    required this.onUpdate,
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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> open() async {
    if (opening) return;
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
    final packet = detail?['red_packet'] is Map
        ? Map<String, dynamic>.from(detail!['red_packet'] as Map)
        : content;
    final claim = detail?['claim'] is Map
        ? Map<String, dynamic>.from(detail!['claim'] as Map)
        : const <String, dynamic>{};
    final amount = '${claim['amount'] ?? packet['my_claim_amount'] ?? ''}'
        .trim();
    final status = redPacketStatus(packet);
    final greeting = redPacketGreeting(packet);
    final claimed = amount.isNotEmpty || redPacketClaimedByMe(packet);
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
