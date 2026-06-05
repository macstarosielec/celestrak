/// In-memory [CacheStore] implementation for testing and short-lived caches.
library;

import 'dart:typed_data';

import 'package:celestrak/src/data/local/cache_store.dart';

/// An in-memory implementation of [CacheStore].
///
/// Stores entries in a plain [Map]; data is lost when the object is garbage
/// collected. Intended for unit tests and as a fallback when file I/O is
/// unavailable.
final class MemoryCacheStore implements CacheStore {
  /// Creates a [MemoryCacheStore].
  MemoryCacheStore();

  final _bytes = <String, Uint8List>{};
  final _timestamps = <String, DateTime>{};

  @override
  Future<Uint8List?> read(String key) async => _bytes[key];

  @override
  Future<void> write(
    String key,
    Uint8List bytes,
    DateTime writtenAt,
  ) async {
    _bytes[key] = Uint8List.fromList(bytes);
    _timestamps[key] = writtenAt;
  }

  @override
  Future<Duration?> age(String key, DateTime now) async {
    final ts = _timestamps[key];
    if (ts == null) return null;
    return now.difference(ts);
  }

  @override
  Future<void> clear({String? keyPrefix}) async {
    if (keyPrefix == null) {
      _bytes.clear();
      _timestamps.clear();
    } else {
      final keysToRemove =
          _bytes.keys.where((k) => k.startsWith(keyPrefix)).toList();
      for (final k in keysToRemove) {
        _bytes.remove(k);
        _timestamps.remove(k);
      }
    }
  }
}
