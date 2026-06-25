class LruMemoryCache<K, V> {
  final int capacity;
  final Duration? ttl;
  final _items = <K, _LruEntry<V>>{};

  LruMemoryCache({required this.capacity, this.ttl}) : assert(capacity > 0);

  int get length {
    _removeExpired();
    return _items.length;
  }

  V? get(K key) {
    final entry = _items.remove(key);
    if (entry == null) return null;
    if (entry.expired) return null;
    _items[key] = entry.touch();
    return entry.value;
  }

  void put(K key, V value, {Duration? ttl}) {
    _items.remove(key);
    _items[key] = _LruEntry(value, _deadline(ttl ?? this.ttl));
    while (_items.length > capacity) {
      _items.remove(_items.keys.first);
    }
  }

  void remove(K key) => _items.remove(key);

  void removeWhere(bool Function(K key) test) {
    final keys = _items.keys.where(test).toList(growable: false);
    for (final key in keys) {
      _items.remove(key);
    }
  }

  void clear() => _items.clear();

  DateTime? _deadline(Duration? value) {
    if (value == null || value <= Duration.zero) return null;
    return DateTime.now().add(value);
  }

  void _removeExpired() {
    final keys = _items.entries
        .where((entry) => entry.value.expired)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      _items.remove(key);
    }
  }
}

class _LruEntry<V> {
  final V value;
  final DateTime? expiresAt;

  const _LruEntry(this.value, this.expiresAt);

  bool get expired {
    final deadline = expiresAt;
    return deadline != null && DateTime.now().isAfter(deadline);
  }

  _LruEntry<V> touch() => _LruEntry(value, expiresAt);
}
