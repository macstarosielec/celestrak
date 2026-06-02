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
/// `maxRetries`, `staleThreshold`) have sensible defaults and can be
/// overridden at construction time.
///
/// See also:
/// - FR-6: Client facade with both constructors.
/// - US-12: `dispose` closes the owned `http.Client` only.
/// - [TleRepository] — the cache/fetch/parse pipeline.
library;

import 'dart:io' show Directory;

import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/file_cache_store.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/data/tle_repository_impl.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:celestrak/src/domain/staleness.dart';
import 'package:celestrak/src/domain/tle_repository.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;

/// High-level facade for the CelesTrak GP API.
///
/// Handles the full cache → TTL → fetch → parse → stamp pipeline behind a
/// single method, [fetchByNoradId].
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
  /// - [defaultTtl] — cache time-to-live (default 2 hours, FR-12).
  /// - [defaultFormat] — wire format for remote requests.
  /// - [timeout] — per-attempt HTTP deadline.
  /// - [maxRetries] — total number of attempts (1 initial + up to
  ///   `maxRetries − 1` retries). Must be at least 1.
  /// - [staleThreshold] — epoch age beyond which data is considered stale.
  /// - [clock] — injectable time source for TTL and staleness.
  CelestrakClient({
    required String cacheDir,
    Duration defaultTtl = kDefaultTtl,
    CelestrakFormat defaultFormat = CelestrakFormat.omm,
    Duration timeout = kDefaultTimeout,
    int maxRetries = kDefaultMaxAttempts,
    Duration staleThreshold = defaultStaleThreshold,
    Clock clock = const SystemClock(),
  }) : this._init(
          httpClient: http.Client(),
          cacheStore: FileCacheStore(Directory(cacheDir)),
          defaultTtl: defaultTtl,
          defaultFormat: defaultFormat,
          timeout: timeout,
          maxRetries: maxRetries,
          staleThreshold: staleThreshold,
          clock: clock,
          ownsClient: true,
        );

  /// Private initialising constructor. Ownership tracking is expressed only
  /// here; external callers cannot set [ownsClient].
  CelestrakClient._init({
    required http.Client httpClient,
    required CacheStore cacheStore,
    required Duration defaultTtl,
    required CelestrakFormat defaultFormat,
    required Duration timeout,
    required int maxRetries,
    required Duration staleThreshold,
    required Clock clock,
    required bool ownsClient,
  })  : _defaultTtl = defaultTtl,
        _defaultFormat = defaultFormat,
        _timeout = timeout,
        _maxRetries = _checkedMaxRetries(maxRetries),
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
              maxAttempts: maxRetries,
              timeout: timeout,
            ),
          ),
          cacheStore: cacheStore,
          clock: clock,
        );

  /// Creates a [CelestrakClient] with a caller-supplied [CacheStore] and
  /// `http.Client`.
  ///
  /// The client does **not** close [httpClient] on [dispose]. The caller is
  /// responsible for managing the lifecycle of both [httpClient] and
  /// [cacheStore].
  ///
  /// [maxRetries] is the total number of attempts (1 initial + up to
  /// `maxRetries − 1` retries). Must be at least 1.
  CelestrakClient.withStore({
    required http.Client httpClient,
    required CacheStore cacheStore,
    Duration defaultTtl = kDefaultTtl,
    CelestrakFormat defaultFormat = CelestrakFormat.omm,
    Duration timeout = kDefaultTimeout,
    int maxRetries = kDefaultMaxAttempts,
    Duration staleThreshold = defaultStaleThreshold,
    Clock clock = const SystemClock(),
  }) : this._init(
          httpClient: httpClient,
          cacheStore: cacheStore,
          defaultTtl: defaultTtl,
          defaultFormat: defaultFormat,
          timeout: timeout,
          maxRetries: maxRetries,
          staleThreshold: staleThreshold,
          clock: clock,
          ownsClient: false,
        );

  /// Validates [maxRetries] and returns it unchanged, or throws
  /// [ArgumentError].
  ///
  /// Used in the initializer list so validation fires before any field or
  /// subobject is constructed.
  static int _checkedMaxRetries(int maxRetries) {
    if (maxRetries < 1) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'maxRetries must be at least 1 (got $maxRetries)',
      );
    }
    return maxRetries;
  }

  final TleRepository _repository;
  final http.Client _httpClient;
  final Duration _defaultTtl;
  final CelestrakFormat _defaultFormat;
  final Duration _timeout;
  final int _maxRetries;
  final StalenessChecker _staleness;
  final bool _ownsClient;

  /// Default TTL for cache entries.
  Duration get defaultTtl => _defaultTtl;

  /// Default wire format for remote requests.
  CelestrakFormat get defaultFormat => _defaultFormat;

  /// Per-attempt HTTP deadline.
  Duration get timeout => _timeout;

  /// Total number of attempts (1 initial + up to [maxRetries] − 1 retries).
  int get maxRetries => _maxRetries;

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
  /// Throws [SatelliteNotFoundException] when the object is not in the
  /// CelesTrak catalog and no usable cache entry exists.
  ///
  /// Throws [NetworkException] on transport failure when no cached entry is
  /// available or [allowStale] is `false`.
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatelliteTle> fetchByNoradId(
    int noradId, {
    CelestrakFormat? format,
    Duration? ttl,
    bool allowStale = false,
  }) =>
      _repository.fetchByNoradId(
        noradId,
        format: format ?? _defaultFormat,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
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
