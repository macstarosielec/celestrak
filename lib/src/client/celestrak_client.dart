/// Public facade for fetching and caching satellite orbital data from
/// CelesTrak.
///
/// Two constructors are provided:
/// - The default [CelestrakClient.new] constructor: supply a `cacheDir` path;
///   the client creates and *owns* an `http.Client` and a [FileCacheStore]
///   backed by that directory. Call `dispose` when done.
/// - [CelestrakClient.withStore]: inject your own [CacheStore] and
///   `http.Client`. The client does **not** close the supplied `http.Client`;
///   its lifecycle remains the caller's responsibility.
///
/// Configuration options (`defaultTtl`, `defaultFormat`, `timeout`,
/// `maxAttempts`, `staleThreshold`) have sensible defaults and can be
/// overridden at construction time.
///
/// See also:
/// - [TleRepository] — the cache/fetch/parse pipeline.
library;

import 'dart:io' show Directory;

import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/file_cache_store.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/data/tle_repository_impl.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:celestrak/src/domain/staleness.dart';
import 'package:celestrak/src/domain/tle_repository.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;

/// High-level facade for the CelesTrak GP API.
///
/// Handles the full cache → TTL → fetch → parse → stamp pipeline for both
/// individual objects ([fetchByNoradId]) and named satellite groups
/// ([fetchCategory]). Cache age can be queried via [cacheAge] and
/// [categoryAge].
///
/// ## Lifecycle
///
/// Instances created with the default constructor own their internal
/// `http.Client`. Call [dispose] to release it. Instances created with
/// [CelestrakClient.withStore] do **not** own the supplied client; the caller
/// is responsible for closing it.
///
/// ## Example — default constructor (file cache)
///
/// ```dart
/// final client = CelestrakClient(cacheDir: '/tmp/celestrak');
/// try {
///   final iss = await client.fetchByNoradId(25544);
///   print(iss.name);
/// } finally {
///   client.dispose();
/// }
/// ```
///
/// ## Example — withStore constructor (injected store)
///
/// ```dart
/// final httpClient = http.Client();
/// final store = MemoryCacheStore();
/// final client = CelestrakClient.withStore(
///   httpClient: httpClient,
///   cacheStore: store,
/// );
/// ```
final class CelestrakClient {
  /// Creates a [CelestrakClient] that stores cached data under [cacheDir].
  ///
  /// [cacheDir] is the filesystem path used as the root of the
  /// [FileCacheStore]. The directory is created on first write if it does not
  /// already exist.
  ///
  /// The client creates and **owns** an internal `http.Client`. Call
  /// [dispose] to close it when the client is no longer needed.
  ///
  /// All other parameters configure the underlying pipeline:
  /// - [defaultTtl] — cache time-to-live (default 2 hours).
  /// - [defaultFormat] — wire format for remote requests.
  /// - [timeout] — per-attempt HTTP deadline.
  /// - [maxAttempts] — total number of HTTP attempts (1 initial + up to
  ///   `maxAttempts − 1` retries). Must be at least 1.
  /// - [staleThreshold] — epoch age beyond which data is considered stale.
  /// - [clock] — injectable time source for TTL and staleness.
  /// - [useIsolate] — when `true`, multi-record category parses are offloaded
  ///   to a worker isolate via `Isolate.run`, keeping the main isolate free
  ///   during large responses (e.g. Starlink). Defaults to `false`.
  CelestrakClient({
    required String cacheDir,
    Duration defaultTtl = kDefaultTtl,
    CelestrakFormat defaultFormat = CelestrakFormat.omm,
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kDefaultMaxAttempts,
    Duration staleThreshold = defaultStaleThreshold,
    Clock clock = const SystemClock(),
    bool useIsolate = false,
  }) : this._init(
          httpClient: http.Client(),
          cacheStore: FileCacheStore(Directory(cacheDir)),
          defaultTtl: defaultTtl,
          defaultFormat: defaultFormat,
          timeout: timeout,
          maxAttempts: maxAttempts,
          staleThreshold: staleThreshold,
          clock: clock,
          ownsClient: true,
          useIsolate: useIsolate,
        );

  /// Private initialising constructor. Ownership tracking is expressed only
  /// here; external callers cannot set [ownsClient].
  CelestrakClient._init({
    required http.Client httpClient,
    required CacheStore cacheStore,
    required Duration defaultTtl,
    required CelestrakFormat defaultFormat,
    required Duration timeout,
    required int maxAttempts,
    required Duration staleThreshold,
    required Clock clock,
    required bool ownsClient,
    required bool useIsolate,
  })  : _defaultTtl = defaultTtl,
        _defaultFormat = defaultFormat,
        _timeout = timeout,
        _maxAttempts = _checkedMaxAttempts(maxAttempts),
        _staleness = StalenessChecker(
          clock: clock,
          staleThreshold: staleThreshold,
        ),
        _ownsClient = ownsClient,
        _httpClient = httpClient,
        _repository = TleRepositoryImpl(
          dataSource: CelestrakDataSource(
            transport: HttpTransport(
              client: httpClient,
              maxAttempts: maxAttempts,
              timeout: timeout,
            ),
          ),
          cacheStore: cacheStore,
          clock: clock,
          useIsolate: useIsolate,
        );

  /// Creates a [CelestrakClient] with a caller-supplied [CacheStore] and
  /// `http.Client`.
  ///
  /// The client does **not** close [httpClient] on [dispose]. The caller is
  /// responsible for managing the lifecycle of both [httpClient] and
  /// [cacheStore].
  ///
  /// [maxAttempts] is the total number of HTTP attempts (1 initial + up to
  /// `maxAttempts − 1` retries). Must be at least 1.
  ///
  /// [useIsolate] when `true`, multi-record category parses are offloaded to a
  /// worker isolate via `Isolate.run`. Defaults to `false`.
  CelestrakClient.withStore({
    required http.Client httpClient,
    required CacheStore cacheStore,
    Duration defaultTtl = kDefaultTtl,
    CelestrakFormat defaultFormat = CelestrakFormat.omm,
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kDefaultMaxAttempts,
    Duration staleThreshold = defaultStaleThreshold,
    Clock clock = const SystemClock(),
    bool useIsolate = false,
  }) : this._init(
          httpClient: httpClient,
          cacheStore: cacheStore,
          defaultTtl: defaultTtl,
          defaultFormat: defaultFormat,
          timeout: timeout,
          maxAttempts: maxAttempts,
          staleThreshold: staleThreshold,
          clock: clock,
          ownsClient: false,
          useIsolate: useIsolate,
        );

  /// Validates [maxAttempts] and returns it unchanged, or throws
  /// [ArgumentError].
  ///
  /// Used in the initializer list so validation fires before any field or
  /// subobject is constructed.
  static int _checkedMaxAttempts(int maxAttempts) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'maxAttempts must be at least 1 (got $maxAttempts)',
      );
    }
    return maxAttempts;
  }

  final TleRepository _repository;
  final http.Client _httpClient;
  final Duration _defaultTtl;
  final CelestrakFormat _defaultFormat;
  // Stored for introspection via [timeout] / [maxAttempts] getters; the actual
  // values are forwarded to [HttpTransport] during construction.
  final Duration _timeout;
  final int _maxAttempts;
  final StalenessChecker _staleness;
  final bool _ownsClient;

  /// Default TTL for cache entries.
  Duration get defaultTtl => _defaultTtl;

  /// Default wire format for remote requests.
  CelestrakFormat get defaultFormat => _defaultFormat;

  /// Per-attempt HTTP deadline.
  Duration get timeout => _timeout;

  /// Total number of HTTP attempts
  /// (1 initial + up to `maxAttempts − 1` retries).
  int get maxAttempts => _maxAttempts;

  /// Staleness threshold used when calling [isStale].
  Duration get staleThreshold => _staleness.staleThreshold;

  /// Fetches the [SatelliteTle] for [noradId].
  ///
  /// Returns a cached record (with [TleSource.local]) when one exists and
  /// its age is within [ttl] (defaults to [defaultTtl]).
  ///
  /// Otherwise, fetches from CelesTrak in [format] (defaults to
  /// [defaultFormat]), caches the raw payload, and returns the record
  /// stamped with [TleSource.celestrak].
  ///
  /// When [allowStale] is `true` and the network request fails, the
  /// repository returns a stale cached entry if one exists.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [SatelliteNotFoundException] when the object is not in the
  /// CelesTrak catalog and no usable cache entry exists.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatelliteTle> fetchByNoradId(
    int noradId, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByNoradId(
        noradId,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatelliteTle] records for a [SatelliteCategory].
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and
  /// its age is within [ttl] (defaults to [defaultTtl]).
  ///
  /// Otherwise, fetches from CelesTrak in [format] (defaults to
  /// [defaultFormat]), caches the raw payload, and returns records stamped
  /// with [TleSource.celestrak].
  ///
  /// Each category maps to its own cache key so fetching one category does
  /// not evict another.
  ///
  /// When [allowStale] is `true` and the network request fails, the
  /// repository returns a stale cached list if one exists.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  Future<List<SatelliteTle>> fetchCategory(
    SatelliteCategory category, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchCategory(
        category,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatelliteTle] records for an arbitrary CelesTrak group
  /// string.
  ///
  /// The [group] string is passed through verbatim to the CelesTrak `GROUP=`
  /// query parameter — no validation against [SatelliteCategory] is performed.
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and
  /// its age is within [ttl] (defaults to [defaultTtl]).
  ///
  /// Otherwise, fetches from CelesTrak in [format] (defaults to
  /// [defaultFormat]), caches the raw payload, and returns records stamped
  /// with [TleSource.celestrak].
  ///
  /// Each group string maps to its own cache key so fetching one group does
  /// not evict another.
  ///
  /// When [allowStale] is `true` and the network request fails, the
  /// repository returns a stale cached list if one exists.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [SatelliteNotFoundException] when the group name is not known to
  /// CelesTrak. This exception is never masked by the `allowStale` fallback.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<List<SatelliteTle>> fetchCategoryByGroup(
    String group, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchCategoryByGroup(
        group,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatelliteTle] records whose name contains [name].
  ///
  /// Uses `NAME=<name>` as the CelesTrak query key. CelesTrak performs a
  /// case-insensitive substring match on `OBJECT_NAME`.
  ///
  /// Returns an **empty list** when no satellites match — this is the
  /// expected result, not an error.
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and
  /// its age is within [ttl] (defaults to [defaultTtl]).
  ///
  /// Otherwise, fetches from CelesTrak in [format] (defaults to
  /// [defaultFormat]), caches the raw payload, and returns records stamped
  /// with [TleSource.celestrak].
  ///
  /// When [allowStale] is `true` and the network request fails, the
  /// repository returns a stale cached list if one exists.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] if [name] is empty.
  Future<List<SatelliteTle>> fetchByName(
    String name, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByName(
        name,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatelliteTle] records matching an international designator.
  ///
  /// Uses `INTDES=<intlDesignator>` as the CelesTrak query key.
  ///
  /// Returns an **empty list** when no satellites match — this is the expected
  /// result, not an error.
  ///
  /// Returns a cached list (with [TleSource.local]) when one exists and its
  /// age is within [ttl] (defaults to [defaultTtl]).
  ///
  /// Otherwise, fetches from CelesTrak in [format] (defaults to
  /// [defaultFormat]), caches the raw payload, and returns records stamped
  /// with [TleSource.celestrak].
  ///
  /// When [allowStale] is `true` and the network request fails, the repository
  /// returns a stale cached list if one exists.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [CacheMissException] when [forceCache] is `true` and no cached
  /// entry exists.
  ///
  /// Throws [ArgumentError] when [intlDesignator] is malformed.
  Future<List<SatelliteTle>> fetchByIntlDesignator(
    String intlDesignator, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByIntlDesignator(
        intlDesignator,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Returns the current cache age for the entry keyed to [intlDesignator].
  ///
  /// Returns `null` when no cache entry exists for [intlDesignator] in
  /// [format] (defaults to [defaultFormat]).
  Future<Duration?> intlDesignatorAge(
    String intlDesignator, {
    CelestrakFormat? format,
  }) =>
      _repository.intlDesignatorAge(
        intlDesignator,
        format: format ?? _defaultFormat,
      );

  /// Returns the current cache age for the entry keyed to [name].
  ///
  /// Returns `null` when no cache entry exists for [name] in [format]
  /// (defaults to [defaultFormat]).
  Future<Duration?> nameAge(
    String name, {
    CelestrakFormat? format,
  }) =>
      _repository.nameAge(
        name,
        format: format ?? _defaultFormat,
      );

  /// Returns the current cache age for the entry keyed to [group].
  ///
  /// Returns `null` when no cache entry exists for the group string in
  /// [format] (defaults to [defaultFormat]).
  Future<Duration?> groupAge(
    String group, {
    CelestrakFormat? format,
  }) =>
      _repository.groupAge(
        group,
        format: format ?? _defaultFormat,
      );

  /// Returns the current cache age for [category].
  ///
  /// Returns `null` when no cache entry exists for the category in [format]
  /// (defaults to [defaultFormat]).
  Future<Duration?> categoryAge(
    SatelliteCategory category, {
    CelestrakFormat? format,
  }) =>
      _repository.categoryAge(
        category,
        format: format ?? _defaultFormat,
      );

  /// Returns the current cache age for the entry keyed to [noradId].
  ///
  /// Returns `null` when no cache entry exists for [noradId] in [format]
  /// (defaults to [defaultFormat]).
  Future<Duration?> cacheAge(
    int noradId, {
    CelestrakFormat? format,
  }) =>
      _repository.cacheAge(
        noradId,
        format: format ?? _defaultFormat,
      );

  /// Removes all cache entries, or only those matching [keyPrefix].
  Future<void> clearCache({String? keyPrefix}) =>
      _repository.clearCache(keyPrefix: keyPrefix);

  /// Returns `true` when the epoch of [tle] exceeds [staleThreshold].
  ///
  /// This is a convenience method; it does not perform any I/O.
  bool isStale(SatelliteTle tle) => _staleness.isStale(tle.epoch);

  /// Releases the internal `http.Client` if this instance owns it.
  ///
  /// Has no effect when the client was created via [CelestrakClient.withStore]
  /// (caller-owned lifecycle).
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
