/// Abstract interface for key-value byte caching with staleness tracking.
library;

import 'dart:typed_data';

import 'package:celestrak/src/data/local/file_cache_store.dart'
    show FileCacheStore;

/// Defines the contract for all local cache implementations.
///
/// Keys are opaque strings conforming to the ADR-8 naming scheme.
/// Implementations handle persistence, eviction, and concurrency safety.
/// All operations resolve asynchronously.
///
/// ## Key format
/// Keys MUST consist only of alphanumeric characters (`A-Z`, `a-z`, `0-9`)
/// and the separator characters `:`, `_`, and `-`. Path traversal characters
/// (e.g. `/`, `\`, `..`) are explicitly forbidden. [FileCacheStore] uses keys
/// directly as filename stems, so an untrusted key could escape the cache
/// directory. Pass a [validateKey] call before delegating to any implementation
/// when key content originates from user or network input.
abstract class CacheStore {
  /// Asserts that [key] conforms to the allowed key format.
  ///
  /// Throws [ArgumentError] if [key] contains any character outside
  /// `[A-Za-z0-9:_-]`.
  static void validateKey(String key) {
    if (!RegExp(r'^[A-Za-z0-9:_\-]+$').hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Cache keys must only contain alphanumeric characters and :, _, -. '
            'Path traversal characters are not permitted.',
      );
    }
  }

  /// Reads the cached payload for [key].
  ///
  /// Returns `null` if the key does not exist or has been evicted.
  Future<Uint8List?> read(String key);

  /// Persists [bytes] under [key] with the provided [writtenAt] timestamp.
  ///
  /// The stored timestamp is used for staleness calculations via [age].
  Future<void> write(String key, Uint8List bytes, DateTime writtenAt);

  /// Calculates the age of the cached entry for [key].
  ///
  /// Returns `null` if the key is absent; otherwise, returns `now - writtenAt`.
  Future<Duration?> age(String key, DateTime now);

  /// Removes cached entries based on [keyPrefix].
  ///
  /// If [keyPrefix] is provided, only matching entries are deleted.
  /// If `null`, all cached data is cleared.
  Future<void> clear({String? keyPrefix});
}
