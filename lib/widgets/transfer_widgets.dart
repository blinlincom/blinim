import 'package:flutter/material.dart';

import '../models/im_models.dart';
import 'blin_style.dart';

class TransferCard extends StatelessWidget {
  final UnifiedMessage message;
  final bool me;
  final bool group;
  final int currentUserId;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onReturn;

  const TransferCard({
    super.key,
    required this.message,
    required this.me,
    this.group = false,
    this.currentUserId = 0,
    this.onAccept,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final amount = transferAmount(message);
    final note = transferNote(message);
    final status = transferStatus(message);
    final accepted = transferAccepted(status);
    final returned = transferReturned(status);
    final target = transferTargetName(message);
    final title = group ? (target.isEmpty ? '群内转账' : '转给 $target') : '好友转账';
    final completed = accepted || returned;
    final bg = completed ? const Color(0xFFEAF8F2) : const Color(0xFF10B981);
    final fg = completed ? const Color(0xFF166534) : Colors.white;
    final iconBg = completed
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFA7F3D0);
    final iconColor = completed
        ? const Color(0xFF047857)
        : const Color(0xFF065F46);
    final subtitle = accepted
        ? '已收款'
        : returned
        ? '已退回'
        : me
        ? '等待对方确认'
        : '点击处理转账';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTransferDialog(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: group ? 244 : 236,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: .18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.payments_rounded,
                        color: iconColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¥$amount',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: 22,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              title,
                              subtitle,
                            ].where((e) => e.trim().isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg.withValues(alpha: .86),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg.withValues(alpha: .72),
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group ? 'Blin 群转账' : 'Blin 转账',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      accepted
                          ? '资金已入账'
                          : returned
                          ? '已原路退回'
                          : '待领取',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

  Future<void> _showTransferDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (_) => _TransferActionDialog(
        parentContext: context,
        message: message,
        me: me,
        group: group,
        currentUserId: currentUserId,
        onAccept: onAccept,
        onReturn: onReturn,
      ),
    );
  }
}

class _TransferActionDialog extends StatefulWidget {
  final BuildContext parentContext;
  final UnifiedMessage message;
  final bool me;
  final bool group;
  final int currentUserId;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onReturn;

  const _TransferActionDialog({
    required this.parentContext,
    required this.message,
    required this.me,
    required this.group,
    required this.currentUserId,
    this.onAccept,
    this.onReturn,
  });

  @override
  State<_TransferActionDialog> createState() => _TransferActionDialogState();
}

class _TransferActionDialogState extends State<_TransferActionDialog> {
  bool submitting = false;

  bool get _accepted => transferAccepted(transferStatus(widget.message));
  bool get _returned => transferReturned(transferStatus(widget.message));
  bool get _actionable =>
      !widget.me &&
      !_accepted &&
      !_returned &&
      _isTransferReceiver(widget.message, widget.currentUserId) &&
      widget.onAccept != null;

  Future<void> _runAction(bool accept) async {
    final action = accept ? widget.onAccept : widget.onReturn;
    if (action == null || submitting) return;
    setState(() => submitting = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _openDetail() {
    Navigator.of(context).pop();
    Navigator.of(widget.parentContext).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TransferDetailScreen(message: widget.message, group: widget.group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = transferAmount(widget.message);
    final note = transferNote(widget.message);
    final title = widget.group ? '群内转账' : '转账';
    final statusText = transferStatusLabel(widget.message);
    final description = transferStatusDescription(widget.message, widget.me);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: BlinStyle.surface(context),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NativeIconBox(
                  icon: Icons.account_balance_wallet_rounded,
                  color: BlinStyle.warning,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: BlinStyle.textPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: BlinStyle.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: Column(
                children: [
                  Text(
                    '¥$amount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: BlinStyle.textPrimary(context),
                      fontSize: 38,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      note,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: BlinStyle.textSecondary(context),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BlinStyle.softFill,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: BlinStyle.hairline(context, .55).color,
                ),
              ),
              child: Text(
                description,
                style: TextStyle(
                  color: BlinStyle.textSecondary(context),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_actionable) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: submitting || widget.onReturn == null
                          ? null
                          : () => _runAction(false),
                      child: const Text('立即退回'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: submitting ? null : () => _runAction(true),
                      child: submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('确认收款'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: submitting ? null : _openDetail,
                child: const Text('查看详情'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransferDetailScreen extends StatelessWidget {
  final UnifiedMessage message;
  final bool group;

  const TransferDetailScreen({
    super.key,
    required this.message,
    this.group = false,
  });

  @override
  Widget build(BuildContext context) {
    final amount = transferAmount(message);
    final note = transferNote(message);
    final target = transferTargetName(message);
    final tradeNo = transferTradeNo(message);
    final acceptedAt = _transferDate(message, const [
      'accepted_at',
      'received_at',
      'paid_at',
    ]);
    final returnedAt = _transferDate(message, const [
      'refunded_at',
      'returned_at',
      'expired_at',
    ]);
    final expiresAt = _transferDate(message, const ['expires_at', 'expire_at']);
    final rows = <_TransferDetailRow>[
      _TransferDetailRow('转账金额', '¥$amount'),
      _TransferDetailRow('当前状态', transferStatusLabel(message)),
      _TransferDetailRow('转账类型', group ? '群内转账' : '好友转账'),
      if (tradeNo.isNotEmpty) _TransferDetailRow('交易单号', tradeNo),
      if (target.isNotEmpty) _TransferDetailRow('收款人', target),
      _TransferDetailRow('发送时间', formatTransferDate(message.createTime)),
      if (acceptedAt != null) _TransferDetailRow('收款时间', acceptedAt),
      if (returnedAt != null) _TransferDetailRow('退回时间', returnedAt),
      if (expiresAt != null) _TransferDetailRow('到期时间', expiresAt),
      if (note.isNotEmpty) _TransferDetailRow('备注', note),
    ];

    return Scaffold(
      backgroundColor: BlinStyle.page(context),
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '转账详情',
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ModuleContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SoftCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                NativeIconBox(
                                  icon: Icons.account_balance_wallet_rounded,
                                  color: BlinStyle.warning,
                                  size: 56,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '¥$amount',
                                  style: TextStyle(
                                    color: BlinStyle.textPrimary(context),
                                    fontSize: 34,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  transferStatusDescription(
                                    message,
                                    message.isMe,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: BlinStyle.textSecondary(context),
                                    fontSize: 14,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SoftCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                _TransferDetailLine(
                                  row: rows[i],
                                  showDivider: i != rows.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ],
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

class _TransferDetailRow {
  final String label;
  final String value;

  const _TransferDetailRow(this.label, this.value);
}

class _TransferDetailLine extends StatelessWidget {
  final _TransferDetailRow row;
  final bool showDivider;

  const _TransferDetailLine({required this.row, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  row.label,
                  style: TextStyle(
                    color: BlinStyle.textSecondary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  row.value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: BlinStyle.textPrimary(context),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 112),
            child: Divider(
              height: 1,
              thickness: 1,
              color: BlinStyle.hairline(context, .48).color,
            ),
          ),
      ],
    );
  }
}

String transferAmount(UnifiedMessage message) {
  final amount = _transferText(message, const [
    'amount',
    'money',
    'value',
    'total_amount',
  ]);
  return amount.isEmpty ? '0.00' : amount;
}

String transferNote(UnifiedMessage message) {
  return _transferText(message, const [
    'note',
    'remark',
    'text',
    'memo',
  ]).trim();
}

String transferTargetName(UnifiedMessage message) {
  return _transferText(message, const [
    'target_nickname',
    'target_name',
    'receiver_name',
    'receiver_nickname',
    'to_name',
    'nickname',
  ]).trim();
}

String transferTradeNo(UnifiedMessage message) {
  return _transferText(message, const [
    'trade_no',
    'transaction_no',
    'transaction_id',
    'order_no',
    'transfer_no',
    'tradeNo',
  ]).trim();
}

String transferStatus(UnifiedMessage message) {
  return _normalizeTransferStatus(_transferStatusText(message));
}

bool transferAccepted(String status) {
  return _normalizeTransferStatus(status) == 'accepted';
}

bool transferReturned(String status) {
  final value = _normalizeTransferStatus(status);
  return value == 'refunded' || value == 'expired';
}

bool _isTransferReceiver(UnifiedMessage message, int currentUserId) {
  if (currentUserId <= 0) return true;
  final targetId =
      int.tryParse(
        '${message.content['receiver_id'] ?? message.content['target_user_id'] ?? message.content['to_user_id'] ?? 0}',
      ) ??
      0;
  return targetId <= 0 || targetId == currentUserId;
}

String transferStatusLabel(UnifiedMessage message) {
  final status = transferStatus(message);
  if (transferAccepted(status)) return '已收款';
  if (status == 'expired') return '已超时退回';
  if (transferReturned(status)) return '已退回';
  return '待收款';
}

String transferStatusDescription(UnifiedMessage message, bool me) {
  final status = transferStatus(message);
  if (transferAccepted(status)) {
    return me ? '对方已确认收款，资金已入账。' : '你已确认收款，资金已入账。';
  }
  if (status == 'expired') return '转账超过24小时未领取，资金已原路退回。';
  if (transferReturned(status)) return '收款方已退回，资金已原路退回。';
  return me ? '等待对方确认收款，24小时未收将自动退回。' : '这笔转账待处理，可以确认收款或立即退回。';
}

String formatTransferDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _transferText(UnifiedMessage message, List<String> keys) {
  for (final source in _transferSources(message)) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final text = '$value';
      if (text.trim().isNotEmpty && text != 'null') return text;
    }
  }
  return '';
}

String _transferStatusText(UnifiedMessage message) {
  for (final source in _transferSources(message)) {
    final status = _firstTransferText(source, const [
      'status',
      'state',
      'transfer_status',
      'order_status',
      'receive_status',
      'accept_status',
      'pay_status',
      'payment_status',
      'status_text',
    ]);
    if (status.isNotEmpty) return status;
    final acceptedAt = _firstTransferText(source, const [
      'accepted_at',
      'received_at',
      'accept_time',
      'receive_time',
      'paid_at',
      'finish_time',
      'finished_at',
    ]);
    if (acceptedAt.isNotEmpty) return 'accepted';
    final returnedAt = _firstTransferText(source, const [
      'returned_at',
      'refunded_at',
      'return_time',
      'refund_time',
    ]);
    if (returnedAt.isNotEmpty) return 'refunded';
  }
  return '';
}

String _firstTransferText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null' && text != '0') return text;
  }
  return '';
}

String _normalizeTransferStatus(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'null') return 'pending';
  if (const {
    '1',
    'success',
    'accepted',
    'accept',
    'received',
    'receive',
    'paid',
    'complete',
    'completed',
    'done',
    '已收款',
    '已领取',
    '已完成',
    '收款成功',
  }.contains(value)) {
    return 'accepted';
  }
  if (const {
    '2',
    'refunded',
    'refund',
    'returned',
    'return',
    '退回',
    '已退回',
    '已退款',
  }.contains(value)) {
    return 'refunded';
  }
  if (const {
    '3',
    'expired',
    'timeout',
    'overdue',
    '已过期',
    '超时',
  }.contains(value)) {
    return 'expired';
  }
  return 'pending';
}

Iterable<Map<String, dynamic>> _transferSources(UnifiedMessage message) sync* {
  yield message.content;
  final contentTransfer = _asTransferMap(message.content['transfer']);
  if (contentTransfer.isNotEmpty) yield contentTransfer;
  final contentOrder = _asTransferMap(message.content['order']);
  if (contentOrder.isNotEmpty) yield contentOrder;
  yield message.raw;
  final rawTransfer = _asTransferMap(message.raw['transfer']);
  if (rawTransfer.isNotEmpty) yield rawTransfer;
  final rawOrder = _asTransferMap(message.raw['order']);
  if (rawOrder.isNotEmpty) yield rawOrder;
  final rawContent = _asTransferMap(message.raw['content']);
  if (rawContent.isNotEmpty) {
    yield rawContent;
    final nestedTransfer = _asTransferMap(rawContent['transfer']);
    if (nestedTransfer.isNotEmpty) yield nestedTransfer;
    final nestedOrder = _asTransferMap(rawContent['order']);
    if (nestedOrder.isNotEmpty) yield nestedOrder;
  }
  final data = _asTransferMap(message.raw['data']);
  if (data.isNotEmpty) {
    yield data;
    final dataTransfer = _asTransferMap(data['transfer']);
    if (dataTransfer.isNotEmpty) yield dataTransfer;
    final dataOrder = _asTransferMap(data['order']);
    if (dataOrder.isNotEmpty) yield dataOrder;
  }
}

Map<String, dynamic> _asTransferMap(Object? value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String? _transferDate(UnifiedMessage message, List<String> keys) {
  for (final source in _transferSources(message)) {
    for (final key in keys) {
      final parsed = _parseTransferDate(source[key]);
      if (parsed != null) return formatTransferDate(parsed);
    }
  }
  return null;
}

DateTime? _parseTransferDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = '$value'.trim();
  if (text.isEmpty || text == '0' || text == 'null') return null;
  final numeric = int.tryParse(text);
  if (numeric != null) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return DateTime.tryParse(text);
}
