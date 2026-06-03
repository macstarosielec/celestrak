/// Production implementation of [TleRepository].
///
/// Orchestrates the cache → TTL → fetch → parse → stamp pipeline (FR-12,
/// FR-17). All dependencies are injected, so the repository is fully
/// testable without real network calls or file I/O.
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
/// ## Cache behaviour (FR-12)
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
/// ## OMM dual-format stitch (ADR-3)
///
/// When [CelestrakFormat.omm] is requested the implementation makes a second
/// `FORMAT=TLE` request (also cached under its own key) and passes both
/// payloads to [TleOmmStitcher], which picks the record matching
/// `omm.noradCatId` and fills in [SatelliteTle.line1] /
/// [SatelliteTle.line2]. If the matching TLE record is absent (e.g. 6+-digit
/// IDs, RK-1) the stitcher falls back to empty lines.
///
/// ## `allowStale` fallback (FR-17 partial)
///
/// When `allowStale` is `true` and the remote fetch throws any
/// [Exception], the repository falls back to a stale cached entry if one
/// exists. When no cached entry is available the original exception is
/// re-thrown regardless of `allowStale`.
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
  }) async {
    final key = CacheKeyBuilder.forNoradId(noradId, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    if (isFresh) {
      return _readFromCache(noradId, format, key, now);
    }

    // Attempt remote fetch.
    try {
      return await _fetchAndCache(noradId, format, key, now);
    } on SatelliteNotFoundException {
      // Not-found is never a transient network error; always propagate.
      rethrow;
    } on Exception {
      if (allowStale && cacheAge != null) {
        // Network failed but a stale entry exists — return it (FR-17).
        return _readFromCache(noradId, format, key, now);
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
  }) async {
    final key = CacheKeyBuilder.forCategory(category, format: format);
    final now = _clock.now;
    final cacheAge = await _cacheStore.age(key, now);
    final isFresh = cacheAge != null && cacheAge < ttl;

    if (isFresh) {
      return _readCategoryFromCache(category, format, key, now);
    }

    try {
      return await _fetchAndCacheCategory(category, format, key, now);
    } on Exception {
      if (allowStale && cacheAge != null) {
        return _readCategoryFromCache(category, format, key, now);
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
  Future<void> clearCache({String? keyPrefix}) =>
      _cacheStore.clear(keyPrefix: keyPrefix);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Reads a cached payload and parses it into a [SatelliteTle].
  ///
  /// `source` is stamped as [TleSource.local] on the returned record.
  Future<SatelliteTle> _readFromCache(
    int noradId,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    final bytes = await _cacheStore.read(key);
    // If bytes were somehow evicted between age() and read(), fall through
    // to the remote path by re-fetching.
    if (bytes == null) {
      return _fetchAndCache(noradId, format, key, now);
    }

    final body = utf8.decode(bytes);

    final tle = switch (format) {
      CelestrakFormat.omm => await _parseOmm(
          noradId,
          body,
          fetchedAt: now,
          fromCache: true,
        ),
      CelestrakFormat.tle => _parseTle(
          noradId,
          body,
          fetchedAt: now,
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
  Future<List<SatelliteTle>> _readCategoryFromCache(
    SatelliteCategory category,
    CelestrakFormat format,
    String key,
    DateTime now,
  ) async {
    final bytes = await _cacheStore.read(key);
    if (bytes == null) {
      return _fetchAndCacheCategory(category, format, key, now);
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
        final tleBody = tleBytes != null ? utf8.decode(tleBytes) : '';
        return _parseCategoryOmm(
          body,
          tleBody: tleBody,
          fetchedAt: now,
          fromCache: true,
        );
      case CelestrakFormat.tle:
        return _parseCategoryTle(body, fetchedAt: now, fromCache: true);
    }
  }

  /// Fetches a category payload from [CelestrakDataSource], caches the raw
  /// bytes, parses into a list, and returns records stamped with
  /// [TleSource.celestrak].
  ///
  /// For [CelestrakFormat.omm], the group TLE body is fetched once and cached
  /// under the TLE-format key so the OMM stitch (ADR-3) avoids per-record
  /// HTTP calls.
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
  /// caller level) used for the ADR-3 dual-format stitch. Each record's lines
  /// are looked up by `noradCatId` from this in-memory string — no additional
  /// HTTP calls are made.
  List<SatelliteTle> _parseCategoryOmm(
    String ommBody, {
    required String tleBody,
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    final jsonList =
        (jsonDecode(ommBody) as List<dynamic>).cast<Map<String, dynamic>>();

    final results = <SatelliteTle>[];
    for (final ommJson in jsonList) {
      final omm = _ommParser.parse(ommJson);
      final tle = _stitcher.stitch(omm, tleBody, fetchedAt: fetchedAt);
      results.add(
        fromCache ? tle.copyWith(source: TleSource.local) : tle,
      );
    }
    return results;
  }

  /// Parses a multi-record TLE body into a list of [SatelliteTle].
  List<SatelliteTle> _parseCategoryTle(
    String body, {
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    final records = _tleParser.parseAll(body, fetchedAt: fetchedAt);
    if (fromCache) {
      return records.map((r) => r.copyWith(source: TleSource.local)).toList();
    }
    return records;
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
      // TLE cache evicted; fall through to fetch.
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
      // Transient transport failure — fall back to empty lines (RK-1
      // tolerance: alpha-5 IDs may legitimately lack a TLE body).
      return '';
    }
  }
}
