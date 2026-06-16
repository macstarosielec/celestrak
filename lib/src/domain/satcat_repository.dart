/// Abstract repository interface for fetching CelesTrak SATCAT metadata.
///
/// Implementations orchestrate cache look-up, TTL expiry, remote fetch, and
/// parsing into [SatcatEntry] values. SATCAT is a concern distinct from the
/// orbital GP/OMM data (ADR-14), so this interface is separate from
/// `TleRepository`: a SATCAT-specific type with its own methods and its own
/// cache namespace.
library;

import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/failures.dart'
    show
        CacheMissException,
        NetworkException,
        SatcatParseException,
        SatelliteNotFoundException;
import 'package:celestrak/src/domain/satcat_entry.dart';

/// Contract for fetching [SatcatEntry] records with transparent caching.
///
/// The repository hides the cache -> TTL -> fetch -> parse pipeline from
/// callers. A cache hit within the configured TTL incurs zero network calls. A
/// single-record lookup ([fetchByNoradId]) raises [SatelliteNotFoundException]
/// when the object is not catalogued; the bulk methods ([fetchByGroup],
/// [fetchByIntlDesignator], [fetchAll]) return an empty list when nothing
/// matches (a zero result, including a cached empty list, is never thrown).
///
/// ## `forceCache` and `allowStale` interaction
///
/// When both `forceCache: true` and `allowStale: true` are supplied to any
/// fetch method, `forceCache` takes unconditional priority: the network is
/// never contacted and `allowStale` is silently ignored. If no cached entry
/// exists a [CacheMissException] is thrown immediately regardless of
/// `allowStale`. Callers who want "try cache, fall back to network on miss"
/// should omit `forceCache` and use `allowStale` alone.
///
/// ## `forceCache` and TTL
///
/// When `forceCache: true` and a cache entry exists but is TTL-expired, the
/// stale entry is served with zero network calls. SATCAT staleness is
/// informational (see [kSatcatStaleThreshold]); use the `*Age` methods to
/// decide whether a refresh is worthwhile.
abstract interface class SatcatRepository {
  /// Fetches the SATCAT metadata record for a single satellite by NORAD
  /// catalog number.
  ///
  /// Returns a cached record when one exists and its cache age is within [ttl].
  /// Otherwise fetches from the remote source, parses the response, caches it,
  /// and returns the parsed record.
  ///
  /// [ttl] controls cache freshness. Defaults to [kSatcatDefaultTtl] (7 days).
  ///
  /// When [allowStale] is `true` and the network request fails, returns a
  /// stale cached entry (if present) rather than re-throwing.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [SatelliteNotFoundException] when the object is not in the SATCAT
  /// catalogue and no usable cache entry exists. This exception is never masked
  /// by the [allowStale] fallback.
  ///
  /// Throws [SatcatParseException] when the response body is present but
  /// malformed. This exception is never masked by the [allowStale] fallback.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached entry
  /// is available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatcatEntry> fetchByNoradId(
    int noradId, {
    Duration ttl,
    bool allowStale,
    bool forceCache,
  });

  /// Returns the current cache age for the [noradId] entry.
  ///
  /// Returns `null` when no cache entry exists for this NORAD id.
  Future<Duration?> noradIdAge(int noradId);

  /// Fetches the SATCAT metadata records for a satellite group.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl];
  /// otherwise fetches from the remote source, caches it, and returns the
  /// parsed records. Returns an empty list when the group matches no records; a
  /// zero result (including a cached empty list) is never thrown.
  ///
  /// When [allowStale] is `true` and the network request fails, returns a
  /// stale cached entry (if present).
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached entry
  /// is available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<List<SatcatEntry>> fetchByGroup(
    String group, {
    Duration ttl,
    bool allowStale,
    bool forceCache,
  });

  /// Returns the current cache age for the [group] entry.
  ///
  /// Returns `null` when no cache entry exists for this group.
  Future<Duration?> groupAge(String group);

  /// Fetches the SATCAT metadata records matching an international designator.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl];
  /// otherwise fetches from the remote source, caches it, and returns the
  /// parsed records. Returns an empty list when the designator matches no
  /// records; a zero result (including a cached empty list) is never thrown.
  ///
  /// When [allowStale] is `true` and the network request fails, returns a
  /// stale cached entry (if present).
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached entry
  /// is available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [intlDesignator] is empty.
  Future<List<SatcatEntry>> fetchByIntlDesignator(
    String intlDesignator, {
    Duration ttl,
    bool allowStale,
    bool forceCache,
  });

  /// Returns the current cache age for the [intlDesignator] entry.
  ///
  /// Returns `null` when no cache entry exists for this designator.
  Future<Duration?> intlDesignatorAge(String intlDesignator);

  /// Fetches the full active SATCAT catalogue.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl];
  /// otherwise fetches from the remote source, caches it, and returns the
  /// parsed records. Returns an empty list when the catalogue is empty; a zero
  /// result is never thrown. The result is large (tens of thousands of
  /// records).
  ///
  /// When [allowStale] is `true` and the network request fails, returns a
  /// stale cached entry (if present).
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no usable cached entry
  /// is available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  Future<List<SatcatEntry>> fetchAll({
    Duration ttl,
    bool allowStale,
    bool forceCache,
  });

  /// Returns the current cache age for the full-catalogue entry.
  ///
  /// Returns `null` when no cache entry exists. Because [fetchAll] and
  /// `fetchByGroup('active')` share one cache entry, this reports the same age
  /// as `groupAge('active')`.
  Future<Duration?> allAge();

  /// Clears cached SATCAT entries.
  ///
  /// When [keyPrefix] is `null` (the default) only the SATCAT namespace is
  /// cleared (keys beginning `dataset:satcat`), so GP cache entries are left
  /// untouched. When [keyPrefix] is supplied it is used verbatim.
  Future<void> clearCache({String? keyPrefix});
}
