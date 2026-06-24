class MemoryLruCache<K, V> {
  final int capacity;
  final _entries = <K, V>{};

  MemoryLruCache({required this.capacity}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be greater than 0');
    }
  }

  int get length => _entries.length;

  Iterable<K> get keys => List<K>.unmodifiable(_entries.keys);

  V? get(K key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }

  void set(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  bool containsKey(K key) => _entries.containsKey(key);
}
