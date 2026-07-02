import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/otc_cache_store.dart';
import '../widgets/blin_style.dart';

class OtcScreen extends StatefulWidget {
  final UserSession session;

  const OtcScreen({super.key, required this.session});

  @override
  State<OtcScreen> createState() => _OtcScreenState();
}

class _OtcScreenState extends State<OtcScreen> {
  final api = const ApiService();
  OtcFeatureConfig config = const OtcFeatureConfig();
  OtcMerchantStatus merchant = const OtcMerchantStatus();
  String balance = '0.00';
  String side = 'sell';
  bool loading = true;
  List<OtcAdItem> ads = const [];
  List<OtcOrderItem> orders = const [];
  List<OtcPaymentMethod> payments = const [];

  @override
  void initState() {
    super.initState();
    unawaited(loadCache());
    unawaited(load());
  }

  Future<void> loadCache() async {
    final cached = await OtcCacheStore.load(widget.session.id);
    if (!mounted || cached == null) return;
    setState(() {
      config = cached.config;
      merchant = cached.merchant;
      balance = cached.balance;
      ads = cached.adsForSide(side);
      orders = cached.orders;
      payments = cached.payments;
      loading = false;
    });
  }

  Future<void> load() async {
    if (mounted && ads.isEmpty && orders.isEmpty) {
      setState(() => loading = true);
    }
    try {
      final cfg = await api.getOtcConfig(token: widget.session.token);
      final result = await Future.wait<Object>([
        api.getOtcHome(token: widget.session.token, side: 'sell'),
        api.getOtcHome(token: widget.session.token, side: 'buy'),
        api.getOtcOrders(token: widget.session.token),
        api.getOtcPaymentMethods(token: widget.session.token),
      ]);
      final nextSellAds = result[0] as List<OtcAdItem>;
      final nextBuyAds = result[1] as List<OtcAdItem>;
      final nextOrders = result[2] as List<OtcOrderItem>;
      final nextPayments = result[3] as List<OtcPaymentMethod>;
      final nextConfig = cfg['config'] as OtcFeatureConfig;
      final nextMerchant = cfg['merchant'] as OtcMerchantStatus;
      final nextBalance = '${cfg['balance'] ?? '0.00'}';
      if (!mounted) return;
      setState(() {
        config = nextConfig;
        merchant = nextMerchant;
        balance = nextBalance;
        ads = side == 'buy' ? nextBuyAds : nextSellAds;
        orders = nextOrders;
        payments = nextPayments;
      });
      unawaited(
        OtcCacheStore.save(
          widget.session.id,
          OtcCacheSnapshot(
            config: nextConfig,
            merchant: nextMerchant,
            balance: nextBalance,
            buyAds: nextBuyAds,
            sellAds: nextSellAds,
            orders: nextOrders,
            payments: nextPayments,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _input({
    required String title,
    required String label,
    String initial = '',
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> applyMerchant() async {
    final name = await _input(title: '申请商家', label: '商家名称');
    if (name == null || name.isEmpty) return;
    final contact = await _input(title: '联系方式', label: '手机号/微信/邮箱');
    if (contact == null || contact.isEmpty) return;
    try {
      merchant = await api.applyOtcMerchant(
        token: widget.session.token,
        merchantName: name,
        contact: contact,
      );
      if (mounted) {
        setState(() {});
        _toast('申请已提交');
      }
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> addPayment() async {
    final type = config.paymentTypes.first['key'] ?? 'bank';
    final realName = await _input(title: '新增收款方式', label: '实名姓名');
    if (realName == null || realName.isEmpty) return;
    final account = await _input(title: '收款账号', label: '银行卡/支付宝/微信账号');
    if (account == null || account.isEmpty) return;
    try {
      await api.saveOtcPaymentMethod(
        token: widget.session.token,
        type: type,
        realName: realName,
        account: account,
      );
      await load();
      _toast('收款方式已保存');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> createAd() async {
    if (!merchant.approved) {
      _toast('请先通过商家认证');
      return;
    }
    final price = await _input(
      title: '发布广告',
      label: '单价 ${config.fiat}',
      keyboardType: TextInputType.number,
    );
    if (price == null || price.isEmpty) return;
    final amount = await _input(
      title: '发布广告',
      label: '数量 ${config.coin}',
      keyboardType: TextInputType.number,
    );
    if (amount == null || amount.isEmpty) return;
    try {
      await api.createOtcAd(
        token: widget.session.token,
        side: side,
        price: price,
        amount: amount,
        minLimit: config.minOrder,
        maxLimit: config.maxOrder,
        paymentTypes: config.paymentTypes.map((e) => e['key']).join(','),
      );
      await load();
      _toast('广告已发布');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> createOrder(OtcAdItem ad) async {
    final amount = await _input(
      title: side == 'sell' ? '买入 ${ad.coin}' : '卖出 ${ad.coin}',
      label: '数量 ${ad.coin}',
      keyboardType: TextInputType.number,
    );
    if (amount == null || amount.isEmpty) return;
    try {
      final order = await api.createOtcOrder(
        token: widget.session.token,
        adId: ad.id,
        amount: amount,
        paymentMethodId: side == 'buy' && payments.isNotEmpty
            ? payments.first.id
            : 0,
      );
      await load();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtcOrderDetailScreen(
            session: widget.session,
            initial: order,
            onChanged: load,
          ),
        ),
      );
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> openOrder(OtcOrderItem order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtcOrderDetailScreen(
          session: widget.session,
          initial: order,
          onChanged: load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: 'OTC交易',
            subtitle: '${config.coin}/${config.fiat} 余额 $balance',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              IconButton(
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  _OtcHero(
                    config: config,
                    merchant: merchant,
                    onApply: applyMerchant,
                    onPayment: addPayment,
                    onCreateAd: createAd,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'sell', label: Text('我要买')),
                      ButtonSegment(value: 'buy', label: Text('我要卖')),
                    ],
                    selected: {side},
                    onSelectionChanged: (set) {
                      setState(() => side = set.first);
                      unawaited(loadCache());
                      unawaited(load());
                    },
                  ),
                  const SizedBox(height: 12),
                  for (final ad in ads)
                    _OtcAdCard(ad: ad, onTap: () => createOrder(ad)),
                  if (ads.isEmpty) const _OtcEmpty(text: '暂无可交易广告'),
                  const SizedBox(height: 18),
                  Text(
                    '我的订单',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final order in orders.take(8))
                    _OtcOrderRow(order: order, onTap: () => openOrder(order)),
                  if (orders.isEmpty) const _OtcEmpty(text: '暂无订单'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OtcHero extends StatelessWidget {
  final OtcFeatureConfig config;
  final OtcMerchantStatus merchant;
  final VoidCallback onApply;
  final VoidCallback onPayment;
  final VoidCallback onCreateAd;

  const _OtcHero({
    required this.config,
    required this.merchant,
    required this.onApply,
    required this.onPayment,
    required this.onCreateAd,
  });

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const NativeIconBox(
              icon: Icons.currency_exchange_rounded,
              color: BlinStyle.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${config.coin} OTC',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '商家状态：${merchant.statusText}',
                    style: TextStyle(color: BlinStyle.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: merchant.approved ? onCreateAd : onApply,
                child: Text(merchant.approved ? '发布广告' : '申请商家'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onPayment,
                child: const Text('收款方式'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _OtcAdCard extends StatelessWidget {
  final OtcAdItem ad;
  final VoidCallback onTap;

  const _OtcAdCard({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ad.merchant['name'] ?? '商家'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                ad.side == 'sell' ? '出售' : '收购',
                style: TextStyle(
                  color: ad.side == 'sell'
                      ? BlinStyle.success
                      : BlinStyle.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${ad.price} ${ad.fiat}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '数量 ${ad.availableAmount} ${ad.coin} · 限额 ${ad.minLimit}-${ad.maxLimit}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: ad.paymentTypeLabels
                .map(
                  (e) => Chip(
                    label: Text(e),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
  );
}

class _OtcOrderRow extends StatelessWidget {
  final OtcOrderItem order;
  final VoidCallback onTap;

  const _OtcOrderRow({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          const NativeIconBox(icon: Icons.receipt_long_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.coinAmount} ${order.coin} · ${order.fiatAmount} ${order.fiat}',
                ),
              ],
            ),
          ),
          Text(order.statusText),
        ],
      ),
    ),
  );
}

class _OtcEmpty extends StatelessWidget {
  final String text;

  const _OtcEmpty({required this.text});

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: TextStyle(color: BlinStyle.textSecondary(context)),
        ),
      ),
    ),
  );
}

class OtcOrderDetailScreen extends StatefulWidget {
  final UserSession session;
  final OtcOrderItem initial;
  final Future<void> Function() onChanged;

  const OtcOrderDetailScreen({
    super.key,
    required this.session,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<OtcOrderDetailScreen> createState() => _OtcOrderDetailScreenState();
}

class _OtcOrderDetailScreenState extends State<OtcOrderDetailScreen> {
  final api = const ApiService();
  late OtcOrderItem order = widget.initial;
  bool busy = false;

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> refresh() async {
    final next = await api.getOtcOrderDetail(
      token: widget.session.token,
      orderId: order.id,
    );
    if (mounted) setState(() => order = next);
  }

  Future<void> run(Future<OtcOrderItem> Function() action) async {
    setState(() => busy = true);
    try {
      final next = await action();
      if (mounted) setState(() => order = next);
      await widget.onChanged();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _input(String title, String label, {bool obscure = false}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuyer = order.buyerId == widget.session.id;
    final isSeller = order.sellerId == widget.session.id;
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '订单详情',
              subtitle: order.statusText,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNo,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${order.coinAmount} ${order.coin}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '应付 ${order.fiatAmount} ${order.fiat} · 单价 ${order.price}',
                        ),
                        const SizedBox(height: 12),
                        if (order.payment.isNotEmpty) ...[
                          const Divider(),
                          Text('收款方式：${order.payment['type_label'] ?? ''}'),
                          Text('实名：${order.payment['real_name'] ?? ''}'),
                          Text('账号：${order.payment['account'] ?? ''}'),
                        ],
                        if (order.appealReason.isNotEmpty) ...[
                          const Divider(),
                          Text('申诉原因：${order.appealReason}'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (order.status == 'created' && isBuyer)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(
                              () => api.markOtcOrderPaid(
                                token: widget.session.token,
                                orderId: order.id,
                              ),
                            ),
                      child: const Text('我已付款'),
                    ),
                  if (order.status == 'created')
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(
                              () => api.cancelOtcOrder(
                                token: widget.session.token,
                                orderId: order.id,
                              ),
                            ),
                      child: const Text('取消订单'),
                    ),
                  if ((order.status == 'paid' || order.status == 'appeal') &&
                      isSeller)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final pwd = await _input(
                                '确认放币',
                                '支付密码',
                                obscure: true,
                              );
                              if (pwd == null || pwd.isEmpty) return;
                              await run(
                                () => api.releaseOtcOrder(
                                  token: widget.session.token,
                                  orderId: order.id,
                                  paymentPassword: pwd,
                                ),
                              );
                            },
                      child: const Text('确认收款并放币'),
                    ),
                  if ((order.status == 'created' || order.status == 'paid') &&
                      (isBuyer || isSeller))
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final reason = await _input('发起申诉', '申诉原因');
                              if (reason == null || reason.isEmpty) return;
                              await run(
                                () => api.appealOtcOrder(
                                  token: widget.session.token,
                                  orderId: order.id,
                                  reason: reason,
                                ),
                              );
                            },
                      child: const Text('发起申诉'),
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
