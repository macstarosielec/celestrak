/// Production implementation of [TleRepository].
///
/// Orchestrates the cache → TTL → fetch → parse → stamp pipeline. All
/// dependencies are injected, so the repository is fully testable without
/// real network calls or file I/O.
library;

import 'dart:convert' show jsonDecode, utf8;

import 'package:celestrak/src/data/local/cache_key_builder.dart';
import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/data/parsers/tle_omm_stitcher.dart';
import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:celestrak/src/domain/tle_repository.dart';

/// Production [TleRepository] that combines a [CacheStore], a
/// [CelestrakDataSource], and a [Clock] to deliver the full
/// cache → TTL → fetch → parse → stamp pipeline.
///
/// ## Cache behaviour
///
/// On each [fetchByNoradId] call:
/// 1. Compute the cache key from `noradId`, `format`, and
///    [TleSource.celestrak].
/// 2. If a cache entry exists and its age is within `ttl`, deserialize the
///    stored payload, stamp `source = TleSource.local`, and return without
///    any network call.
/// 3. Otherwise, fetch from [CelestrakDataSource], parse, write the raw
///    UTF-8 payload to the cache, and return with
///    `source = TleSource.celestrak`.
///
/// ## OMM dual-format stitch
///
/// When [CelestrakFormat.omm] is requested the implementation makes a second
/// `FORMAT=TLE` request (also cached under its own key) and passes both
/// payloads to [TleOmmStitcher], which picks the record matching
/// `omm.noradCatId` and fills in [SatelliteTle.line1] /
/// [SatelliteTle.line2]. If the matching TLE record is absent (e.g. NORAD IDs
/// ≥ 100 000 (alpha-5 encoded)) the stitcher falls back to empty lines.
///
/// ## `allowStale` fallback
///
/// When `allowStale` is `true` and the remote fetch throws any [Exception]
/// that is not a `SatelliteNotFoundException`, the repository falls back to a
/// stale cached entry if one exists. `SatelliteNotFoundException` is never
/// masked — an unknown object is not a transient network failure.
///
/// [OmmParseException] and [TleParseException] are also never masked: a
/// corrupt remote payload is not a transient error, so the stale cache would
/// hide a data-quality problem.
///
/// This fallback applies to all five fetch methods: [fetchByNoradId],
/// [fetchCategory], [fetchCategoryByGroup], [fetchByName], and
/// [fetchByIntlDesignator]. When no cached entry is available the original
/// exception is re-thrown regardless of `allowStale`.
///
/// ## `forceCache` and `allowStale` interaction
///
/// When both `forceCache: true` and `allowStale: true` are supplied,
/// `forceCache` takes unconditional priority: the network is never contacted
/// and `allowStale` is silently ignored. If no cached entry exists a
/// [CacheMissException] is thrown regardless of `allowStale`. Callers who
/// want "try cache, fall back to network on miss" should omit `forceCache`
/// and use `allowStale` alone.
final class TleRepositoryImpl implements TleRepository {
  /// Creates a [TleRepositoryImpl].
  ///
  /// [dataSource] is the raw CelesTrak HTTP data source.
  /// [cacheStore] is the backing key-value store.
  /// [clock] supplies the current UTC time for TTL and age calculations;
  /// defaults to [SystemClock].
  const TleRepositoryImpl({
    required CelestrakDataSource dataSource,
    required CacheStore cacheStore,
    Clock clock = const SystemClock(),
  })  : _dataSource = dataSource,
        _cacheStore = cacheStore,
        _clock = clock;

  final CelestrakDataSource _dataSource;
  final CacheStore _cacheStore;
  final Clock _clock;

  static const _ommParser = OmmParser();
  static const _stitcher = TleOmmStitcher();
  static const _tleParser = TleParser();

  @override
  Future<SatelliteTle> fetchByNoradId(
    int noradId, {
    CelestrakFormat format = CelestrakFormat.omm,
    Duration ttl = kDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    final key = CacheKeyBuilder.forNoradId(noradId, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached entry for NORAD ID $noradId.',
          key: key,
        );
      }
      return _readFromCache(noradId, format, key, now.subtract(cacheAge));
    }

    if (isFresh) {
      // Pass the original write timestamp so fetchedAt reflects when the entry
      // was stored, not when this read call occurred.
      return _readFromCache(noradId, format, key, now.subtract(cacheAge));
    }

    // Attempt remote fetch.
    try {
      return await _fetchAndCache(noradId, format, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on OmmParseException {
      rethrow;
    } on TleParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        // Network failed but a stale entry exists — return it.
        // Pass the original write timestamp so fetchedAt is accurate.
        return _readFromCache(noradId, format, key, now.subtract(cacheAge));
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> cacheAge(
    int noradId, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final key = CacheKeyBuilder.forNoradId(noradId, format: format);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatelliteTle>> fetchCategory(
    SatelliteCategory category, {
    CelestrakFormat format = CelestrakFormat.omm,
    Duration ttl = kDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    final key = CacheKeyBuilder.forCategory(category, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached entry for category ${category.group}.',
          key: key,
        );
      }
      return _readCategoryFromCache(
        category,
        format,
        key,
        now.subtract(cacheAge),
      );
    }

    if (isFresh) {
      return _readCategoryFromCache(
        category,
        format,
        key,
        now.subtract(cacheAge),
      );
    }

    try {
      return await _fetchAndCacheCategory(category, format, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on OmmParseException {
      rethrow;
    } on TleParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        return _readCategoryFromCache(
          category,
          format,
          key,
          now.subtract(cacheAge),
        );
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> categoryAge(
    SatelliteCategory category, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final key = CacheKeyBuilder.forCategory(category, format: format);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatelliteTle>> fetchCategoryByGroup(
    String group, {
    CelestrakFormat format = CelestrakFormat.omm,
    Duration ttl = kDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    if (group.isEmpty) {
      throw ArgumentError.value(group, 'group', 'group must not be empty');
    }
    final key = CacheKeyBuilder.forGroup(group, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached entry for group "$group".',
          key: key,
        );
      }
      return _readGroupFromCache(group, format, key, now.subtract(cacheAge));
    }

    if (isFresh) {
      return _readGroupFromCache(group, format, key, now.subtract(cacheAge));
    }

    try {
      return await _fetchAndCacheGroup(group, format, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on OmmParseException {
      rethrow;
    } on TleParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        // Network failed but a stale entry exists — return it.
        return _readGroupFromCache(group, format, key, now.subtract(cacheAge));
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> groupAge(
    String group, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final key = CacheKeyBuilder.forGroup(group, format: format);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatelliteTle>> fetchByName(
    String name, {
    CelestrakFormat format = CelestrakFormat.omm,
    Duration ttl = kDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'name must not be empty or whitespace-only',
      );
    }
    final key = CacheKeyBuilder.forName(name, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached entry for name "$name".',
          key: key,
        );
      }
      return _readNameFromCache(name, format, key, now.subtract(cacheAge));
    }

    if (isFresh) {
      return _readNameFromCache(name, format, key, now.subtract(cacheAge));
    }

    try {
      return await _fetchAndCacheName(name, format, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on OmmParseException {
      rethrow;
    } on TleParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        return _readNameFromCache(name, format, key, now.subtract(cacheAge));
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> nameAge(
    String name, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final key = CacheKeyBuilder.forName(name, format: format);
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<List<SatelliteTle>> fetchByIntlDesignator(
    String intlDesignator, {
    CelestrakFormat format = CelestrakFormat.omm,
    Duration ttl = kDefaultTtl,
    bool allowStale = false,
    bool forceCache = false,
  }) async {
    // Validate before touching the cache. ArgumentError extends Error (not
    // Exception), so it bypasses the allowStale fallback by language
    // semantics — no explicit rethrow guard is needed.
    if (!CelestrakDataSource.isValidIntlDesignator(intlDesignator)) {
      throw ArgumentError.value(
        intlDesignator,
        'intlDesignator',
        'International designator must match YYYY-NNNP… '
            '(e.g. "1998-067A"). Got: "$intlDesignator"',
      );
    }
    final key = CacheKeyBuilder.forIntlDesignator(
      intlDesignator,
      format: format,
    );
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    // forceCache: serve from cache only, zero network.
    if (forceCache) {
      if (cacheAge == null) {
        throw CacheMissException(
          'No cached entry for international designator "$intlDesignator".',
          key: key,
        );
      }
      return _readIntlDesFromCache(
        intlDesignator,
        format,
        key,
        now.subtract(cacheAge),
      );
    }

    if (isFresh) {
      return _readIntlDesFromCache(
        intlDesignator,
        format,
        key,
        now.subtract(cacheAge),
      );
    }

    try {
      return await _fetchAndCacheIntlDes(intlDesignator, format, key, now);
    } on SatelliteNotFoundException {
      rethrow;
    } on OmmParseException {
      rethrow;
    } on TleParseException {
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        return _readIntlDesFromCache(
          intlDesignator,
          format,
          key,
          now.subtract(cacheAge),
        );
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> intlDesignatorAge(
    String intlDesignator, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final key = CacheKeyBuilder.forIntlDesignator(
      intlDesignator,
      format: format,
    );
    return _cacheStore.age(key, _clock.now);
  }

  @override
  Future<void> clearCache({String? keyPrefix}) =>
      _cacheStore.clear(keyPrefix: keyPrefix);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Reads a cached payload and parses it into a [SatelliteTle].
  ///
  /// `source` is stamped as [TleSource.local] on the returned record.
  ///
  /// [writtenAt] must be the timestamp at which the cache entry was originally
  /// written (i.e. `now - cacheAge` from the caller). It is forwarded as
  /// [SatelliteTle.fetchedAt] so the field reflects the actual fetch time,
  /// not the time of this read call.
  ///
  /// Throws [NetworkException] when the cache entry was evicted between the
  /// [CacheStore.age] call and this [CacheStore.read] call (i.e. a concurrent
  /// eviction race). Falling back to a live network call inside the stale
  /// path would suppress the original failure with a new, unrelated exception,
  /// so we surface a clear error instead.
  Future<SatelliteTle> _readFromCache(
    int noradId,
    CelestrakFormat format,
    String key,
    DateTime writtenAt,
  ) async {
    final bytes = await _cacheStore.read(key);
    // Cache entry evicted between age() and read() — throw rather than
    // silently making a new network call that would hide the original error.
    if (bytes == null) {
      throw NetworkException(
        'Cache entry for NORAD ID $noradId evicted before it could be read; '
        'no stale fallback available.',
      );
    }

    final body = utf8.decode(bytes);

    final tle = switch (format) {
      CelestrakFormat.omm => await _parseOmm(
          noradId,
          body,
          fetchedAt: writtenAt,
          fromCache: true,
        ),
      CelestrakFormat.tle => _parseTle(
          noradId,
          body,
          fetchedAt: writtenAt,
          fromCache: true,
        ),
    };

    return tle;
  }

  /// Fetches from [CelestrakDataSource], caches the raw payload, parses, and
  /// returns the record stamped with [TleSource.celestrak].
  Future<SatelliteTle> _fetchAndCache(
    int noradId,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    final body = await _dataSource.fetchByNoradId(noradId, format: format);
    await _cacheStore.write(key, utf8.encode(body), now);

    return switch (format) {
      CelestrakFormat.omm => await _parseOmm(
          noradId,
          body,
          fetchedAt: now,
          fromCache: false,
        ),
      CelestrakFormat.tle => _parseTle(
          noradId,
          body,
          fetchedAt: now,
          fromCache: false,
        ),
    };
  }

  /// Parses an OMM JSON body for [noradId], performing the dual-format stitch.
  ///
  /// When [fromCache] is `false` the TLE body is fetched and cached under the
  /// TLE key; when `true` the TLE cache is consulted first.
  ///
  /// ## Exception propagation
  ///
  /// A [SatelliteNotFoundException] from [_tleBodyFor] propagates upward
  /// through this method and is caught by the `on SatelliteNotFoundException
  /// { rethrow; }` guard in each public method's try/catch block — it is
  /// never masked by the [Exception] catch-all or the `allowStale` fallback.
  /// [OmmParseException] and [TleParseException] are similarly re-thrown
  /// by dedicated guards in each public method. A corrupt remote payload is
  /// not a transient network failure and must not be hidden by a stale cache.
  Future<SatelliteTle> _parseOmm(
    int noradId,
    String ommBody, {
    required DateTime fetchedAt,
    required bool fromCache,
  }) async {
    final jsonList =
        (jsonDecode(ommBody) as List<dynamic>).cast<Map<String, dynamic>>();
    final ommJson = jsonList.firstWhere(
      (m) => (m['NORAD_CAT_ID'] as num).toInt() == noradId,
      orElse: () => throw SatelliteNotFoundException(
        'No matching OMM record for NORAD ID $noradId',
        noradId: noradId,
      ),
    );
    final omm = _ommParser.parse(ommJson);

    // Dual-format stitch: fetch or read TLE lines.
    final tleBody = await _tleBodyFor(
      noradId,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );

    final tle = _stitcher.stitch(
      omm,
      tleBody,
      fetchedAt: fetchedAt,
    );

    return fromCache ? tle.copyWith(source: TleSource.local) : tle;
  }

  /// Parses a TLE body for [noradId].
  SatelliteTle _parseTle(
    int noradId,
    String body, {
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    final records = _tleParser.parseAll(body, fetchedAt: fetchedAt);
    final match = records.firstWhere(
      (r) => r.noradId == noradId,
      orElse: () => throw SatelliteNotFoundException(
        'No matching TLE record for NORAD ID $noradId',
        noradId: noradId,
      ),
    );
    return fromCache ? match.copyWith(source: TleSource.local) : match;
  }

  /// Reads a cached category payload and parses it into a list of
  /// [SatelliteTle] records stamped with [TleSource.local].
  ///
  /// [writtenAt] must be the timestamp at which the cache entry was originally
  /// written (i.e. `now - cacheAge` from the caller). It is forwarded as
  /// [SatelliteTle.fetchedAt] so the field reflects the actual fetch time.
  ///
  /// Throws [NetworkException] when the primary cache entry was evicted between
  /// the [CacheStore.age] call and this [CacheStore.read] call (concurrent
  /// eviction race). See [_readFromCache] for rationale.
  ///
  /// Throws [CacheMissException] (not [NetworkException]) when the OMM path
  /// finds its companion TLE sub-key independently evicted — returning OMM
  /// records with blank TLE lines would silently corrupt the stitch result, and
  /// the correct exception for a missing cache entry is [CacheMissException],
  /// not a transport error.
  Future<List<SatelliteTle>> _readCategoryFromCache(
    SatelliteCategory category,
    CelestrakFormat format,
    String key,
    DateTime writtenAt,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'Cache entry for category ${category.group} evicted before it could '
        'be read; no stale fallback available.',
      );
    }
    final body = utf8.decode(bytes);

    switch (format) {
      case CelestrakFormat.omm:
        // Read the group TLE body from its own cache key for the stitch.
        final tleKey = CacheKeyBuilder.forCategory(
          category,
          format: CelestrakFormat.tle,
        );
        final tleBytes = await _cacheStore.read(tleKey);
        // Treat an independently-evicted TLE sub-key as a CacheMissException:
        // returning records with empty line1/line2 would silently corrupt the
        // stitch, and the failure is a cache integrity issue, not a transport
        // error.
        if (tleBytes == null) {
          throw CacheMissException(
            'TLE cache entry for category ${category.group} evicted before it '
            'could be read.',
            key: tleKey,
          );
        }
        final tleBody = utf8.decode(tleBytes);
        return _parseCategoryOmm(
          body,
          tleBody: tleBody,
          fetchedAt: writtenAt,
          fromCache: true,
        );
      case CelestrakFormat.tle:
        return _parseCategoryTle(body, fetchedAt: writtenAt, fromCache: true);
    }
  }

  /// Fetches a category payload from [CelestrakDataSource], caches the raw
  /// bytes, parses into a list, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// For [CelestrakFormat.omm], the group TLE body is fetched once and cached
  /// under the TLE-format key so the OMM stitch avoids per-record HTTP calls.
  Future<List<SatelliteTle>> _fetchAndCacheCategory(
    SatelliteCategory category,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    switch (format) {
      case CelestrakFormat.omm:
        // Fetch the OMM group body and cache it.
        final ommBody = await _dataSource.fetchByGroup(
          category.group,
          format: CelestrakFormat.omm,
        );
        await _cacheStore.write(key, utf8.encode(ommBody), now);

        // Fetch the TLE group body once for the stitch and cache it
        // separately so subsequent OMM cache hits can stitch without I/O.
        final tleKey = CacheKeyBuilder.forCategory(
          category,
          format: CelestrakFormat.tle,
        );
        String tleBody;
        try {
          tleBody = await _dataSource.fetchByGroup(
            category.group,
            format: CelestrakFormat.tle,
          );
          await _cacheStore.write(tleKey, utf8.encode(tleBody), now);
        } on CelestrakException {
          // Transport failure or empty group for the supplementary TLE fetch —
          // fall back to empty string so the OMM stitch proceeds with blank
          // TLE lines rather than failing the whole category request.
          tleBody = '';
        }

        return _parseCategoryOmm(
          ommBody,
          tleBody: tleBody,
          fetchedAt: now,
          fromCache: false,
        );

      case CelestrakFormat.tle:
        final body = await _dataSource.fetchByGroup(
          category.group,
          format: CelestrakFormat.tle,
        );
        await _cacheStore.write(key, utf8.encode(body), now);
        return _parseCategoryTle(body, fetchedAt: now, fromCache: false);
    }
  }

  /// Parses a multi-record OMM JSON body into a list of [SatelliteTle].
  ///
  /// [tleBody] is the full group TLE text (fetched or cached once at the
  /// caller level) used for the dual-format stitch. Each record's lines are
  /// looked up by `noradCatId` from this in-memory string — no additional
  /// HTTP calls are made.
  ///
  /// Records are decoded lazily via [OmmParser.parseAllLazy]: each
  /// `Omm` is stitched and added to the result list in-turn so the decoded
  /// JSON entries can be garbage-collected as iteration proceeds.
  List<SatelliteTle> _parseCategoryOmm(
    String ommBody, {
    required String tleBody,
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    final jsonList =
        (jsonDecode(ommBody) as List<dynamic>).cast<Map<String, dynamic>>();

    final results = <SatelliteTle>[];
    for (final omm in _ommParser.parseAllLazy(jsonList)) {
      final tle = _stitcher.stitch(omm, tleBody, fetchedAt: fetchedAt);
      results.add(
        fromCache ? tle.copyWith(source: TleSource.local) : tle,
      );
    }
    return results;
  }

  /// Parses a multi-record TLE body into a list of [SatelliteTle].
  ///
  /// Records are decoded lazily via [TleParser.parseAllLazy]: each
  /// [SatelliteTle] is produced one-at-a-time, avoiding a full output list
  /// in memory during iteration. The input line buffer is materialised upfront
  /// for the multiple-of-3 guard; see [TleParser.parseAllLazy] for details.
  List<SatelliteTle> _parseCategoryTle(
    String body, {
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    final records =
        _tleParser.parseAllLazy(body, fetchedAt: fetchedAt).toList();
    if (fromCache) {
      return records.map((r) => r.copyWith(source: TleSource.local)).toList();
    }
    return records;
  }

  /// Reads a cached group payload and parses it into a list of [SatelliteTle]
  /// records stamped with [TleSource.local].
  ///
  /// [writtenAt] must be the timestamp at which the cache entry was originally
  /// written (i.e. `now - cacheAge` from the caller). It is forwarded as
  /// [SatelliteTle.fetchedAt] so the field reflects the actual fetch time.
  ///
  /// Throws [NetworkException] when the primary cache entry was evicted between
  /// the [CacheStore.age] call and this [CacheStore.read] call (concurrent
  /// eviction race). See [_readFromCache] for rationale.
  ///
  /// Throws [CacheMissException] (not [NetworkException]) when the OMM path
  /// finds its companion TLE sub-key independently evicted. See
  /// [_readCategoryFromCache] for rationale.
  Future<List<SatelliteTle>> _readGroupFromCache(
    String group,
    CelestrakFormat format,
    String key,
    DateTime writtenAt,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'Cache entry for group "$group" evicted before it could be read; '
        'no stale fallback available.',
      );
    }
    final body = utf8.decode(bytes);

    switch (format) {
      case CelestrakFormat.omm:
        final tleKey = CacheKeyBuilder.forGroup(
          group,
          format: CelestrakFormat.tle,
        );
        final tleBytes = await _cacheStore.read(tleKey);
        // Treat an independently-evicted TLE sub-key as a CacheMissException.
        // See _readCategoryFromCache for rationale.
        if (tleBytes == null) {
          throw CacheMissException(
            'TLE cache entry for group "$group" evicted before it could be'
            ' read.',
            key: tleKey,
          );
        }
        final tleBody = utf8.decode(tleBytes);
        return _parseCategoryOmm(
          body,
          tleBody: tleBody,
          fetchedAt: writtenAt,
          fromCache: true,
        );
      case CelestrakFormat.tle:
        return _parseCategoryTle(body, fetchedAt: writtenAt, fromCache: true);
    }
  }

  /// Fetches a group payload from [CelestrakDataSource], caches the raw
  /// bytes, parses into a list, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// For [CelestrakFormat.omm], the group TLE body is fetched once and cached
  /// under the TLE-format key so the OMM stitch avoids per-record HTTP calls.
  Future<List<SatelliteTle>> _fetchAndCacheGroup(
    String group,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    switch (format) {
      case CelestrakFormat.omm:
        final ommBody = await _dataSource.fetchByGroup(
          group,
          format: CelestrakFormat.omm,
        );
        await _cacheStore.write(key, utf8.encode(ommBody), now);

        final tleKey = CacheKeyBuilder.forGroup(
          group,
          format: CelestrakFormat.tle,
        );
        String tleBody;
        try {
          tleBody = await _dataSource.fetchByGroup(
            group,
            format: CelestrakFormat.tle,
          );
          await _cacheStore.write(tleKey, utf8.encode(tleBody), now);
        } on CelestrakException {
          tleBody = '';
        }

        return _parseCategoryOmm(
          ommBody,
          tleBody: tleBody,
          fetchedAt: now,
          fromCache: false,
        );

      case CelestrakFormat.tle:
        final body = await _dataSource.fetchByGroup(
          group,
          format: CelestrakFormat.tle,
        );
        await _cacheStore.write(key, utf8.encode(body), now);
        return _parseCategoryTle(body, fetchedAt: now, fromCache: false);
    }
  }

  /// Reads a cached name payload and parses it into a list of [SatelliteTle]
  /// records stamped with [TleSource.local].
  ///
  /// [writtenAt] must be the timestamp at which the cache entry was originally
  /// written (i.e. `now - cacheAge` from the caller). It is forwarded as
  /// [SatelliteTle.fetchedAt] so the field reflects the actual fetch time.
  ///
  /// An empty cached payload (stored after a no-match response) returns `[]`.
  ///
  /// Throws [NetworkException] when the primary cache entry was evicted between
  /// the [CacheStore.age] call and this [CacheStore.read] call (concurrent
  /// eviction race). See [_readFromCache] for rationale.
  ///
  /// Throws [CacheMissException] (not [NetworkException]) when the OMM path
  /// finds its companion TLE sub-key independently evicted. See
  /// [_readCategoryFromCache] for rationale.
  Future<List<SatelliteTle>> _readNameFromCache(
    String name,
    CelestrakFormat format,
    String key,
    DateTime writtenAt,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'Cache entry for name "$name" evicted before it could be read; '
        'no stale fallback available.',
      );
    }
    final body = utf8.decode(bytes);
    if (body.isEmpty) return [];

    switch (format) {
      case CelestrakFormat.omm:
        final tleKey = CacheKeyBuilder.forName(
          name,
          format: CelestrakFormat.tle,
        );
        final tleBytes = await _cacheStore.read(tleKey);
        // Treat an independently-evicted TLE sub-key as a CacheMissException.
        // See _readCategoryFromCache for rationale.
        if (tleBytes == null) {
          throw CacheMissException(
            'TLE cache entry for name "$name" evicted before it could be read.',
            key: tleKey,
          );
        }
        final tleBody = utf8.decode(tleBytes);
        return _parseCategoryOmm(
          body,
          tleBody: tleBody,
          fetchedAt: writtenAt,
          fromCache: true,
        );
      case CelestrakFormat.tle:
        return _parseCategoryTle(body, fetchedAt: writtenAt, fromCache: true);
    }
  }

  /// Fetches a name payload from [CelestrakDataSource], caches the raw
  /// bytes, parses into a list, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// Stores an empty payload when the remote returns no match so the cache
  /// key exists and subsequent calls within TTL short-circuit without
  /// hitting the network.
  Future<List<SatelliteTle>> _fetchAndCacheName(
    String name,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    switch (format) {
      case CelestrakFormat.omm:
        final ommBody = await _dataSource.fetchByName(
          name,
          format: CelestrakFormat.omm,
        );
        await _cacheStore.write(key, utf8.encode(ommBody), now);

        // No match — return empty list without attempting the TLE stitch.
        if (ommBody.isEmpty) return [];

        final tleKey = CacheKeyBuilder.forName(
          name,
          format: CelestrakFormat.tle,
        );
        String tleBody;
        try {
          tleBody = await _dataSource.fetchByName(
            name,
            format: CelestrakFormat.tle,
          );
          await _cacheStore.write(tleKey, utf8.encode(tleBody), now);
        } on CelestrakException {
          tleBody = '';
        }

        return _parseCategoryOmm(
          ommBody,
          tleBody: tleBody,
          fetchedAt: now,
          fromCache: false,
        );

      case CelestrakFormat.tle:
        final body = await _dataSource.fetchByName(
          name,
          format: CelestrakFormat.tle,
        );
        await _cacheStore.write(key, utf8.encode(body), now);
        if (body.isEmpty) return [];
        return _parseCategoryTle(body, fetchedAt: now, fromCache: false);
    }
  }

  /// Reads a cached INTDES payload and parses it into a list of [SatelliteTle]
  /// records stamped with [TleSource.local].
  ///
  /// [writtenAt] must be the timestamp at which the cache entry was originally
  /// written (i.e. `now - cacheAge` from the caller). It is forwarded as
  /// [SatelliteTle.fetchedAt] so the field reflects the actual fetch time.
  ///
  /// An empty cached payload (stored after a no-match response) returns `[]`.
  ///
  /// Throws [NetworkException] when the primary cache entry was evicted between
  /// the [CacheStore.age] call and this [CacheStore.read] call (concurrent
  /// eviction race). See [_readFromCache] for rationale.
  ///
  /// Throws [CacheMissException] (not [NetworkException]) when the OMM path
  /// finds its companion TLE sub-key independently evicted. See
  /// [_readCategoryFromCache] for rationale.
  Future<List<SatelliteTle>> _readIntlDesFromCache(
    String intlDesignator,
    CelestrakFormat format,
    String key,
    DateTime writtenAt,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      throw NetworkException(
        'Cache entry for international designator "$intlDesignator" evicted '
        'before it could be read; no stale fallback available.',
      );
    }
    final body = utf8.decode(bytes);
    if (body.isEmpty) return [];

    switch (format) {
      case CelestrakFormat.omm:
        final tleKey = CacheKeyBuilder.forIntlDesignator(
          intlDesignator,
          format: CelestrakFormat.tle,
        );
        final tleBytes = await _cacheStore.read(tleKey);
        // Treat an independently-evicted TLE sub-key as a CacheMissException.
        // See _readCategoryFromCache for rationale.
        if (tleBytes == null) {
          throw CacheMissException(
            'TLE cache entry for international designator "$intlDesignator" '
            'evicted before it could be read.',
            key: tleKey,
          );
        }
        final tleBody = utf8.decode(tleBytes);
        return _parseCategoryOmm(
          body,
          tleBody: tleBody,
          fetchedAt: writtenAt,
          fromCache: true,
        );
      case CelestrakFormat.tle:
        return _parseCategoryTle(body, fetchedAt: writtenAt, fromCache: true);
    }
  }

  /// Fetches an INTDES payload from [CelestrakDataSource], caches the raw
  /// bytes, parses into a list, and returns records stamped with
  /// [TleSource.celestrak].
  Future<List<SatelliteTle>> _fetchAndCacheIntlDes(
    String intlDesignator,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    switch (format) {
      case CelestrakFormat.omm:
        final ommBody = await _dataSource.fetchByIntlDesignator(
          intlDesignator,
          format: CelestrakFormat.omm,
        );
        await _cacheStore.write(key, utf8.encode(ommBody), now);

        if (ommBody.isEmpty) return [];

        final tleKey = CacheKeyBuilder.forIntlDesignator(
          intlDesignator,
          format: CelestrakFormat.tle,
        );
        String tleBody;
        try {
          tleBody = await _dataSource.fetchByIntlDesignator(
            intlDesignator,
            format: CelestrakFormat.tle,
          );
          await _cacheStore.write(tleKey, utf8.encode(tleBody), now);
        } on CelestrakException {
          tleBody = '';
        }

        return _parseCategoryOmm(
          ommBody,
          tleBody: tleBody,
          fetchedAt: now,
          fromCache: false,
        );

      case CelestrakFormat.tle:
        final body = await _dataSource.fetchByIntlDesignator(
          intlDesignator,
          format: CelestrakFormat.tle,
        );
        await _cacheStore.write(key, utf8.encode(body), now);
        if (body.isEmpty) return [];
        return _parseCategoryTle(body, fetchedAt: now, fromCache: false);
    }
  }

  /// Returns the TLE body for [noradId], either from cache or from the
  /// remote source.
  ///
  /// The TLE body is always cached under the TLE-format key so that
  /// subsequent OMM-format cache hits can perform the stitch without network
  /// calls.
  Future<String> _tleBodyFor(
    int noradId, {
    required DateTime fetchedAt,
    required bool fromCache,
  }) async {
    final tleKey = CacheKeyBuilder.forNoradId(
      noradId,
      format: CelestrakFormat.tle,
    );

    if (fromCache) {
      final bytes = await _cacheStore.read(tleKey);
      if (bytes != null) return utf8.decode(bytes);
      // TLE sub-key was independently evicted while the OMM key survived.
      // Honour the forceCache contract: no network call permitted.
      throw CacheMissException(
        'TLE sub-key evicted for NORAD ID $noradId; '
        'retry without forceCache to refresh from the network.',
        key: tleKey,
      );
    }

    // Fetch and cache the TLE body.
    try {
      final tleBody = await _dataSource.fetchByNoradId(
        noradId,
        format: CelestrakFormat.tle,
      );
      await _cacheStore.write(tleKey, utf8.encode(tleBody), fetchedAt);
      return tleBody;
    } on SatelliteNotFoundException {
      // NORAD ID absent from TLE catalog — propagate; do not mask with empty
      // lines (the OMM path already validated the ID, so this is a data
      // inconsistency, not an alpha-5 encoding gap).
      rethrow;
    } on NetworkException {
      // Transient transport failure — fall back to empty lines (alpha-5
      // IDs ≥ 100 000 may legitimately lack a TLE body).
      return '';
    }
  }
}
