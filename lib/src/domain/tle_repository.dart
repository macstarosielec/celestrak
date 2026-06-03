/// Abstract repository interface for fetching satellite TLE records.
///
/// Implementations orchestrate cache look-up, TTL expiry, remote fetch,
/// parsing, and provenance stamping (FR-12, FR-17).
library;

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

  /// Fetches all [SatelliteTle] records for a [SatelliteCategory].
  ///
  /// Uses `GROUP=<category.group>` as the CelesTrak query key (FR-2).
  /// Each category maps to its own cache key so different categories do
  /// not share cached payloads (FR-12).
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and
  /// its age is within [ttl]. Otherwise fetches from the remote source,
  /// caches the raw payload, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// When [allowStale] is `true` and the network request fails, returns
  /// a stale cached entry if one exists (FR-17 partial).
  ///
  /// Throws [NetworkException] on transport failure when no usable cached
  /// entry is available or [allowStale] is `false`.
  Future<List<SatelliteTle>> fetchCategory(
    SatelliteCategory category, {
    CelestrakFormat format,
    Duration ttl,
    bool allowStale,
  });

  /// Returns the current cache age for the [category] entry.
  ///
  /// Returns `null` when no cache entry exists for this category.
  Future<Duration?> categoryAge(
    SatelliteCategory category, {
    CelestrakFormat format,
  });

  /// Fetches all [SatelliteTle] records for an arbitrary CelesTrak group
  /// string.
  ///
  /// Uses `GROUP=<group>` as the CelesTrak query key (FR-21). The [group]
  /// string is passed through verbatim to the API — no validation against
  /// [SatelliteCategory] is performed.
  ///
  /// Each group value maps to its own cache key so different groups do not
  /// share cached payloads (FR-12).
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and
  /// its age is within [ttl]. Otherwise fetches from the remote source,
  /// caches the raw payload, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// When [allowStale] is `true` and the network request fails, returns
  /// a stale cached entry if one exists (FR-17 partial).
  ///
  /// Throws [SatelliteNotFoundException] when the group name is not known to
  /// CelesTrak. This exception is never masked by the `allowStale` fallback.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached
  /// entry is available or [allowStale] is `false`.
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<List<SatelliteTle>> fetchCategoryByGroup(
    String group, {
    CelestrakFormat format,
    Duration ttl,
    bool allowStale,
  });

  /// Returns the current cache age for the entry keyed to [group].
  ///
  /// Returns `null` when no cache entry exists for this group string.
  ///
  /// [format] defaults to [CelestrakFormat.omm].
  Future<Duration?> groupAge(
    String group, {
    CelestrakFormat format,
  });

  /// Removes all cache entries, or only those matching [keyPrefix].
  Future<void> clearCache({String? keyPrefix});
}
