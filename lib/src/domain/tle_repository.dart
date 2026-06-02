/// Abstract repository interface for fetching satellite TLE records.
///
/// Implementations orchestrate cache look-up, TTL expiry, remote fetch,
/// parsing, and provenance stamping (FR-12, FR-17).
library;

import 'package:celestrak/celestrak.dart'
    show NetworkException, SatelliteNotFoundException;
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart'
    show NetworkException, SatelliteNotFoundException;
import 'package:celestrak/src/domain/satellite_tle.dart';

/// Contract for fetching [SatelliteTle] records with transparent caching.
///
/// The repository hides the cache→TTL→fetch→parse→stamp pipeline from callers.
/// A cache hit within the configured TTL incurs zero network calls (FR-12).
/// When a fresh cache entry is absent the repository fetches from the remote
/// source, parses the response, writes the raw payload to cache, and returns
/// the fully stamped [SatelliteTle].
///
/// See also:
/// - FR-12: cache-first lookup with TTL.
/// - FR-17: `allowStale` fallback on network failure.
abstract interface class TleRepository {
  /// Fetches a [SatelliteTle] for [noradId].
  ///
  /// Returns a cached record (with [TleSource.local]) when one exists and
  /// its cache age is within [ttl]. Otherwise fetches from the remote
  /// source, parses the response, caches the raw payload, and returns the
  /// record stamped with [TleSource.celestrak].
  ///
  /// [format] selects the wire format used for both remote fetching and
  /// cache key derivation.
  ///
  /// [ttl] controls cache freshness. Defaults to 2 hours (FR-12).
  ///
  /// When [allowStale] is `true` and the network request fails, the
  /// repository returns a stale cached entry (if present) rather than
  /// re-throwing the exception (FR-17 partial).
  ///
  /// Throws [SatelliteNotFoundException] when the object is not in the
  /// CelesTrak catalog and no usable cache entry exists.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached
  /// entry is available or [allowStale] is `false`.
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatelliteTle> fetchByNoradId(
    int noradId, {
    CelestrakFormat format,
    Duration ttl,
    bool allowStale,
  });

  /// Returns the current cache age for the entry keyed to [noradId].
  ///
  /// Returns `null` when no cache entry exists.
  Future<Duration?> cacheAge(
    int noradId, {
    CelestrakFormat format,
  });

  /// Removes all cache entries, or only those matching [keyPrefix].
  Future<void> clearCache({String? keyPrefix});
}
