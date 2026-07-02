import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import 'api_service.dart';

class OtcCacheSnapshot {
  final OtcFeatureConfig config;
  final OtcMerchantStatus merchant;
  final String balance;
  final List<OtcAdItem> buyAds;
  final List<OtcAdItem> sellAds;
  final List<OtcOrderItem> orders;
  final List<OtcPaymentMethod> payments;

  const OtcCacheSnapshot({
    this.config = const OtcFeatureConfig(),
    this.merchant = const OtcMerchantStatus(),
    this.balance = '0.00',
    this.buyAds = const <OtcAdItem>[],
    this.sellAds = const <OtcAdItem>[],
    this.orders = const <OtcOrderItem>[],
    this.payments = const <OtcPaymentMethod>[],
  });

  List<OtcAdItem> adsForSide(String side) => side == 'buy' ? buyAds : sellAds;

  Map<String, dynamic> toCacheJson() => {
    'config': config.toCacheJson(),
    'merchant': merchant.toCacheJson(),
    'balance': balance,
    'buy_ads': buyAds.map((item) => item.toCacheJson()).toList(),
    'sell_ads': sellAds.map((item) => item.toCacheJson()).toList(),
    'orders': orders.map((item) => item.toCacheJson()).toList(),
    'payments': payments.map((item) => item.toCacheJson()).toList(),
  };

  factory OtcCacheSnapshot.fromJson(Map<String, dynamic> json) =>
      OtcCacheSnapshot(
        config: OtcFeatureConfig.fromJson(_map(json['config'])),
        merchant: OtcMerchantStatus.fromJson(_map(json['merchant'])),
        balance: '${json['balance'] ?? '0.00'}',
        buyAds: _list(json['buy_ads']).map(OtcAdItem.fromJson).toList(),
        sellAds: _list(json['sell_ads']).map(OtcAdItem.fromJson).toList(),
        orders: _list(json['orders']).map(OtcOrderItem.fromJson).toList(),
        payments: _list(
          json['payments'],
        ).map(OtcPaymentMethod.fromJson).toList(),
      );

  static Map<String, dynamic> _map(Object? source) {
    if (source is Map<String, dynamic>) return source;
    if (source is Map) return Map<String, dynamic>.from(source);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(Object? source) {
    final rows = source is List ? source : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}

class OtcCacheStore {
  OtcCacheStore._();

  static const int _maxAds = 80;
  static const int _maxOrders = 80;
  static MMKV get _kv => MMKV.defaultMMKV();

  static String _key(int userId) => 'otc_cache_snapshot_$userId';

  static Future<OtcCacheSnapshot?> load(int userId) async {
    final raw = _kv.decodeString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return OtcCacheSnapshot.fromJson(decoded);
      }
      if (decoded is Map) {
        return OtcCacheSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(int userId, OtcCacheSnapshot snapshot) async {
    _kv.encodeString(
      _key(userId),
      jsonEncode(
        OtcCacheSnapshot(
          config: snapshot.config,
          merchant: snapshot.merchant,
          balance: snapshot.balance,
          buyAds: _trim(snapshot.buyAds, _maxAds),
          sellAds: _trim(snapshot.sellAds, _maxAds),
          orders: _trim(snapshot.orders, _maxOrders),
          payments: snapshot.payments,
        ).toCacheJson(),
      ),
    );
  }

  static List<T> _trim<T>(List<T> items, int max) =>
      items.length > max ? items.sublist(0, max) : items;
}
