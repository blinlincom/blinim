import 'dart:math';

class SafeRandom {
  static final Random _fallback = Random();

  const SafeRandom._();

  static List<int> bytes(int length) {
    if (length <= 0) return const <int>[];
    final random = _secureOrFallback();
    return List<int>.generate(length, (_) => _nextByte(random));
  }

  static String hex(int byteLength) {
    final values = bytes(byteLength);
    if (values.isEmpty) return '';
    return values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Random _secureOrFallback() {
    try {
      return Random.secure();
    } catch (_) {
      return _fallback;
    }
  }

  static int _nextByte(Random random) {
    try {
      return random.nextInt(256);
    } catch (_) {
      return _fallback.nextInt(256);
    }
  }
}
