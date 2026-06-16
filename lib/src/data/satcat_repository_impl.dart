/// Production implementation of [SatcatRepository].
///
/// Orchestrates the cache -> TTL -> fetch -> parse pipeline for SATCAT
/// metadata. All dependencies are injected, so the repository is fully testable
/// without real network calls or file I/O.
library;

import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:celestrak/src/data/local/cache_key_builder.dart';
import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/parsers/satcat_parser.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/failures.dart'
    show
        CacheMissException,
        NetworkException,
        SatcatParseException,
        SatelliteNotFoundException;
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:celestrak/src/domain/satcat_repository.dart';

/// Production [SatcatRepository] that combines a [SatcatDataSource], a
/// [CacheStore], and a [Clock] to deliver the full cache -> TTL -> fetch ->
/// parse pipeline.
///
/// ## Cache behaviour
///
/// On each fetch call the implementation:
/// 1. Builds the dataset-discriminated SATCAT cache key (never collides with a
///    GP key - see [CacheKeyBuilder]).
/// 2. If a cache entry exists and its age is within `ttl`, decodes and parses
///    the stored payload and returns it without any network call.
/// 3. Otherwise fetches from [SatcatDataSource], caches the re-serialised
///    payload, and returns the parsed records.
///
/// The data source owns the URL construction, transport, and not-found /
/// empty-list semantics; this type never duplicates that logic. It re-fetches
/// through the data source and persists the parsed result via
/// [SatcatEntry.toCacheJson], so a cache read reconstructs an equal entry.
///
/// ## `allowStale` fallback
///
/// When `allowStale` is `true` and the remote fetch throws any [Exception]
/// that is not a [SatelliteNotFoundException] or a [SatcatParseException], the
/// repository falls back to a stale cached entry if one exists.
/// [SatelliteNotFoundException] (an unknown object) and [SatcatParseException]
/// (a corrupt payload) are never masked: neither is a transient network
/// failure, so a stale cache must not hide them. When no cached entry is
/// available the original exception is re-thrown regardless of `allowStale`.
///
/// ## `forceCache` and `allowStale` interaction
///
/// When both `forceCache: true` and `allowStale: true` are supplied,
/// `forceCache` takes unconditional priority: the network is never contacted
/// and `allowStale` is silently ignored. If no cached entry exists a
/// [CacheMissException] is thrown regardless of `allowStale`.
final class SatcatRepositoryImpl implements SatcatRepository {
  /// Creates a [SatcatRepositoryImpl].
  ///
  /// [dataSource] is the raw CelesTrak SATCAT HTTP data source.
  /// [cacheStore] is the backing key-value store.
  /// [clock] supplies the current UTC time for TTL and age calculations;
  /// defaults to [SystemClock].
  const SatcatRepositoryImpl({
    required SatcatDataSource dataSource,
    required CacheStore cacheStore,
    Clock clock = const SystemClock(),
  })  : _dataSource = dataSource,
        _cacheStore = cacheStore,
        _clock = clock;

  final SatcatDataSource _dataSource;
  final CacheStore _cacheStore;
  final Clock _clock;

  static const _parser = SatcatParser();

  // Single-record path
  @override
  Future<SatcatEntry> fetchByNoradId(
    int noradId, {
    Duration ttl = kSatcatDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'must be a positive NORAD catalog number',
      );
    }

    final key = CacheKeyBuilder.forSatcatNoradId(noradId);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached SATCAT entry for NORAD ID $noradId.',
          key: key,
        );
      }
      return _readSingleFromCache(noradId, key);
    }

    if (isFresh) {
      return _readSingleFromCache(noradId, key);
    }

    try {
      return await _fetchAndCacheSingle(noradId, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on SatcatParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        // Network failed but a stale entry exists - return it.
        return _readSingleFromCache(noradId, key);
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> noradIdAge(int noradId) async {
    final key = CacheKeyBuilder.forSatcatNoradId(noradId);
    return _cacheStore.age(key, _clock.now);
  }

  // Bulk paths
  @override
  Future<List<SatcatEntry>> fetchByGroup(
    String group, {
    Duration ttl = kSatcatDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) {
    if (group.trim().isEmpty) {
      throw ArgumentError.value(
        group,
        'group',
        'group must not be empty or whitespace-only',
      );
    }
    return _fetchBulk(
      key: CacheKeyBuilder.forSatcatGroup(group),
      label: 'group "$group"',
      fetch: () => _dataSource.fetchByGroup(group),
      ttl: ttl,
      allowStale: allowStale,
      forceCache: forceCache,
    );
  }

  @override
  Future<Duration?> groupAge(String group) async {
    final key = CacheKeyBuilder.forSatcatGroup(group);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatcatEntry>> fetchByIntlDesignator(
    String intlDesignator, {
    Duration ttl = kSatcatDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) {
    if (intlDesignator.trim().isEmpty) {
      throw ArgumentError.value(
        intlDesignator,
        'intlDesignator',
        'international designator must not be empty or whitespace-only',
      );
    }
    return _fetchBulk(
      key: CacheKeyBuilder.forSatcatIntlDesignator(intlDesignator),
      label: 'international designator "$intlDesignator"',
      fetch: () => _dataSource.fetchByIntlDesignator(intlDesignator),
      ttl: ttl,
      allowStale: allowStale,
      forceCache: forceCache,
    );
  }

  @override
  Future<Duration?> intlDesignatorAge(String intlDesignator) async {
    final key = CacheKeyBuilder.forSatcatIntlDesignator(intlDesignator);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatcatEntry>> fetchAll({
    Duration ttl = kSatcatDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) {
    return _fetchBulk(
      key: CacheKeyBuilder.forSatcatAll(),
      label: 'the full SATCAT catalogue',
      fetch: _dataSource.fetchAll,
      ttl: ttl,
      allowStale: allowStale,
      forceCache: forceCache,
    );
  }

  @override
  Future<Duration?> allAge() async {
    final key = CacheKeyBuilder.forSatcatAll();
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<void> clearCache({String? keyPrefix}) =>
      _cacheStore.clear(
        keyPrefix: keyPrefix ?? CacheKeyBuilder.satcatDatasetPrefix,
      );

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Orchestrates a bulk fetch (group, INTDES, or full catalogue) through the
  /// shared cache -> TTL -> fetch -> cache pipeline.
  ///
  /// A bulk path never raises [CacheMissException] on a remote miss: an empty
  /// list is a valid result and is cached and served like any other payload.
  Future<List<SatcatEntry>> _fetchBulk({
    required String key,
    required String label,
    required Future<List<SatcatEntry>> Function() fetch,
    required Duration ttl,
    required bool allowStale,
    required bool forceCache,
  }) async {
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached SATCAT entry for $label.',
          key: key,
        );
      }
      return _readBulkFromCache(key, label);
    }

    if (isFresh) {
      return _readBulkFromCache(key, label);
    }

    try {
      final entries = await fetch();
      await _writeBulk(key, entries, now);
      return entries;
    } on SatelliteNotFoundException {
      rethrow;
    } on SatcatParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        // Network failed but a stale entry exists - return it.
        return _readBulkFromCache(key, label);
      }
      rethrow;
    }
  }

  /// Fetches a single record through the data source, caches its re-serialised
  /// payload, and returns the parsed [SatcatEntry].
  Future<SatcatEntry> _fetchAndCacheSingle(
    int noradId,
    String key,
    DateTime now,
  ) async {
    final entry = await _dataSource.fetchByNoradId(noradId);
    final bytes = utf8.encode(jsonEncode(entry.toCacheJson()));
    await _cacheStore.write(key, bytes, now);
    return entry;
  }

  /// Reads a cached single record and parses it back into a [SatcatEntry].
  ///
  /// Throws [NetworkException] when the cache entry was evicted between the
  /// [CacheStore.age] call and this [CacheStore.read] call (a concurrent
  /// eviction race). Falling back to a live network call here would suppress
  /// the original failure with a new, unrelated exception, so a clear error is
  /// surfaced instead.
  Future<SatcatEntry> _readSingleFromCache(int noradId, String key) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'SATCAT cache entry for NORAD ID $noradId evicted before it could be '
        'read; no stale fallback available.',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return _parser.parseJson(decoded);
  }

  /// Re-serialises [entries] and writes them as one bulk cache payload.
  ///
  /// [now] is the fetch-start timestamp captured before the remote call, not
  /// the wall-clock time at which the write completes, so the entry's recorded
  /// age reflects when the data was fetched.
  Future<void> _writeBulk(
    String key,
    List<SatcatEntry> entries,
    DateTime now,
  ) async {
    final payload = entries.map((e) => e.toCacheJson()).toList();
    final bytes = utf8.encode(jsonEncode(payload));
    await _cacheStore.write(key, bytes, now);
  }

  /// Reads a cached bulk payload and parses it back into a list.
  ///
  /// Throws [NetworkException] on an eviction race (see
  /// [_readSingleFromCache]).
  ///
  /// The cache only ever holds records this repository serialised from
  /// successfully parsed entries via [SatcatEntry.toCacheJson], so the payload
  /// is expected to be a JSON array of well-formed objects that all round-trip.
  /// A decode failure, a non-object element, or any skipped row therefore
  /// signals a corrupt cache entry rather than a benign remote quirk, and is
  /// surfaced as a [SatcatParseException] (matching the strict single-record
  /// read) instead of silently returning a truncated catalogue.
  Future<List<SatcatEntry>> _readBulkFromCache(
    String key,
    String label,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'SATCAT cache entry for $label evicted before it could be read; no '
        'stale fallback available.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw SatcatParseException(
        'corrupt SATCAT bulk cache payload for $label: ${e.message}',
      );
    }
    if (decoded is! List) {
      throw SatcatParseException(
        'corrupt SATCAT bulk cache payload for $label: expected a JSON array',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in decoded) {
      if (row is! Map<String, dynamic>) {
        throw SatcatParseException(
          'corrupt SATCAT bulk cache payload for $label: non-object row',
        );
      }
      rows.add(row);
    }

    final result = _parser.parseJsonList(rows);
    if (result.skipped > 0) {
      throw SatcatParseException(
        'corrupt SATCAT bulk cache payload for $label: ${result.skipped} '
        'row(s) failed to parse',
      );
    }
    return result.entries;
  }
}
