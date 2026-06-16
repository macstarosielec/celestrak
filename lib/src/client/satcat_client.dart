/// Public facade for fetching and caching CelesTrak SATCAT metadata.
///
/// SATCAT (per-object owner, launch, decay, object type, status) is a concern
/// distinct from the orbital GP/OMM data (ADR-14). This client is the SATCAT
/// parallel to `CelestrakClient`: it wraps the same cache -> TTL -> fetch ->
/// parse pipeline used for GP data, but keyed into its own SATCAT cache
/// namespace, and adds an indexed `lookup` for repeated point queries against
/// the full catalogue.
///
/// Two constructors are provided:
/// - The default [SatcatClient.new] constructor: supply a `cacheDir` path; the
///   client creates and *owns* an `http.Client` and a file-backed cache store
///   rooted at `cacheDir`. On web/WASM, falls back to an in-memory store (see
///   README). Call `dispose` when done.
/// - [SatcatClient.withStore]: inject your own [CacheStore] and `http.Client`.
///   The client does *not* close the supplied `http.Client`; its lifecycle
///   remains the caller's responsibility.
///
/// See also:
/// - [SatcatRepository] - the cache/fetch/parse pipeline this client wraps.
library;

import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/default_cache_store_stub.dart'
    if (dart.library.io) 'package:celestrak/src/data/local/default_cache_store_io.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/data/satcat_repository_impl.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart'
    show
        CacheMissException,
        NetworkException,
        SatcatParseException,
        SatelliteNotFoundException;
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:celestrak/src/domain/satcat_repository.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;

/// High-level facade for the CelesTrak SATCAT API.
///
/// Handles the full cache -> TTL -> fetch -> parse pipeline for single-object
/// lookups ([fetchByNoradId]), group queries ([fetchCategory],
/// [fetchCategoryByGroup]), international-designator queries
/// ([fetchByIntlDesignator]), and the full catalogue ([fetchAll]). Cache age
/// can be queried via the per-key `*Age` methods.
///
/// ## Join pattern
///
/// SATCAT is never merged into the orbital `SatelliteTle`. Consumers that need
/// both fetch a `SatelliteTle` from `CelestrakClient` and a [SatcatEntry] from
/// this client, then join the two on `noradId`:
///
/// ```dart
/// final tle = await celestrak.fetchByNoradId(25544);
/// final meta = await satcat.fetchByNoradId(25544);
/// // tle.noradId == meta.noradId
/// print('${tle.name} owned by ${meta.owner.name}');
/// ```
///
/// ## Staleness
///
/// SATCAT staleness is age-of-fetch based, not epoch based: SATCAT records
/// carry no orbital epoch. To decide whether a refresh is worthwhile, compare
/// the result of an `*Age` method against [staleThreshold]:
///
/// ```dart
/// final age = await satcat.noradIdAge(25544);
/// final isStale = age != null && age > satcat.staleThreshold;
/// ```
///
/// ## Lifecycle
///
/// Instances created with the default constructor own their internal
/// `http.Client`. Call [dispose] to release it. Instances created with
/// [SatcatClient.withStore] do *not* own the supplied client; the caller is
/// responsible for closing it.
///
/// ## Example - default constructor (file cache)
///
/// ```dart
/// final client = SatcatClient(cacheDir: '/tmp/celestrak-satcat');
/// try {
///   final entry = await client.fetchByNoradId(25544);
///   print('${entry.name} (${entry.owner.name})');
/// } finally {
///   client.dispose();
/// }
/// ```
///
/// ## Example - withStore constructor (injected store)
///
/// ```dart
/// final httpClient = http.Client();
/// final store = MemoryCacheStore();
/// final client = SatcatClient.withStore(
///   httpClient: httpClient,
///   cacheStore: store,
/// );
/// ```
final class SatcatClient {
  /// Creates a [SatcatClient] that stores cached SATCAT data under [cacheDir].
  ///
  /// [cacheDir] is the filesystem path used as the root of the file-backed
  /// cache store. The directory is created on first write if it does not
  /// already exist. On web/WASM, [cacheDir] is ignored and an in-memory store
  /// is used instead.
  ///
  /// The client creates and *owns* an internal `http.Client`. Call [dispose]
  /// to close it when the client is no longer needed.
  ///
  /// All other parameters configure the underlying pipeline:
  /// - [defaultTtl] - SATCAT cache time-to-live (default 7 days).
  /// - [staleThreshold] - age beyond which a cached entry is considered stale
  ///   (default 30 days; informational, since SATCAT metadata is near-static).
  /// - [timeout] - per-attempt HTTP deadline.
  /// - [maxAttempts] - total number of HTTP attempts (1 initial + up to
  ///   `maxAttempts - 1` retries). Must be at least 1.
  /// - [clock] - injectable time source for TTL and age calculations.
  SatcatClient({
    required String cacheDir,
    Duration defaultTtl = kSatcatDefaultTtl,
    Duration staleThreshold = kSatcatStaleThreshold,
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kDefaultMaxAttempts,
    Clock clock = const SystemClock(),
  }) : this._init(
          httpClient: http.Client(),
          cacheStore: defaultCacheStore(cacheDir),
          defaultTtl: defaultTtl,
          staleThreshold: staleThreshold,
          timeout: timeout,
          maxAttempts: maxAttempts,
          clock: clock,
          ownsClient: true,
        );

  /// Creates a [SatcatClient] with a caller-supplied [CacheStore] and
  /// `http.Client`.
  ///
  /// The client does *not* close [httpClient] on [dispose]. The caller is
  /// responsible for managing the lifecycle of both [httpClient] and
  /// [cacheStore].
  ///
  /// - [defaultTtl] - SATCAT cache time-to-live (default 7 days).
  /// - [staleThreshold] - age beyond which a cached entry is considered stale
  ///   (default 30 days).
  /// - [timeout] - per-attempt HTTP deadline.
  /// - [maxAttempts] - total number of HTTP attempts (1 initial + up to
  ///   `maxAttempts - 1` retries). Must be at least 1.
  /// - [clock] - injectable time source for TTL and age calculations.
  SatcatClient.withStore({
    required http.Client httpClient,
    required CacheStore cacheStore,
    Duration defaultTtl = kSatcatDefaultTtl,
    Duration staleThreshold = kSatcatStaleThreshold,
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kDefaultMaxAttempts,
    Clock clock = const SystemClock(),
  }) : this._init(
          httpClient: httpClient,
          cacheStore: cacheStore,
          defaultTtl: defaultTtl,
          staleThreshold: staleThreshold,
          timeout: timeout,
          maxAttempts: maxAttempts,
          clock: clock,
          ownsClient: false,
        );

  /// Private initialising constructor. Ownership tracking is expressed only
  /// here; external callers cannot set [ownsClient].
  SatcatClient._init({
    required http.Client httpClient,
    required CacheStore cacheStore,
    required Duration defaultTtl,
    required Duration staleThreshold,
    required Duration timeout,
    required int maxAttempts,
    required Clock clock,
    required bool ownsClient,
  })  : _defaultTtl = defaultTtl,
        _staleThreshold = staleThreshold,
        _timeout = timeout,
        _maxAttempts = _checkedMaxAttempts(maxAttempts),
        _ownsClient = ownsClient,
        _httpClient = httpClient,
        _clock = clock,
        _repository = SatcatRepositoryImpl(
          dataSource: SatcatDataSource(
            transport: HttpTransport(
              client: httpClient,
              maxAttempts: maxAttempts,
              timeout: timeout,
            ),
          ),
          cacheStore: cacheStore,
          clock: clock,
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

  final SatcatRepository _repository;
  final http.Client _httpClient;
  final Duration _defaultTtl;
  final Duration _staleThreshold;
  // Stored for introspection via [timeout] / [maxAttempts] getters; the actual
  // values are forwarded to [HttpTransport] during construction.
  final Duration _timeout;
  final int _maxAttempts;
  final bool _ownsClient;
  final Clock _clock;

  // Memoized full-catalogue index for [lookup]. [_indexFetchTime] is the
  // reconstructed cache write-time of the catalogue the index was built from,
  // used to detect when the catalogue has been refetched or evicted.
  Map<int, SatcatEntry>? _index;
  DateTime? _indexFetchTime;

  // In-flight index rebuild, used to coalesce concurrent [lookup] calls so a
  // cold cache is fetched once rather than once per concurrent caller. Cleared
  // when the rebuild completes (whether it succeeds or throws).
  Future<void>? _indexRebuild;

  /// Default TTL for cache entries.
  Duration get defaultTtl => _defaultTtl;

  /// Staleness threshold for cached SATCAT entries.
  ///
  /// Compare against an `*Age` result to decide whether a refresh is
  /// worthwhile. This client never throws on staleness; the threshold is
  /// purely informational (SATCAT metadata is near-static).
  Duration get staleThreshold => _staleThreshold;

  /// Per-attempt HTTP deadline.
  Duration get timeout => _timeout;

  /// Total number of HTTP attempts
  /// (1 initial + up to `maxAttempts - 1` retries).
  int get maxAttempts => _maxAttempts;

  /// Fetches the [SatcatEntry] for a single satellite by NORAD catalog number.
  ///
  /// Returns a cached record when one exists and its cache age is within [ttl]
  /// (defaults to [defaultTtl]). Otherwise fetches from CelesTrak, caches the
  /// re-serialised payload, and returns the parsed record.
  ///
  /// When [allowStale] is `true` and the network request fails, a stale cached
  /// entry is returned (if present) rather than re-throwing.
  ///
  /// When [forceCache] is `true`, only the cache is consulted and no network
  /// request is ever made. If no cached entry exists, [CacheMissException] is
  /// thrown immediately with zero transport calls.
  ///
  /// Throws [SatelliteNotFoundException] when the object is not in the SATCAT
  /// catalogue and no usable cache entry exists.
  ///
  /// Throws [SatcatParseException] when the response body is malformed.
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
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByNoradId(
        noradId,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatcatEntry] records for a [SatelliteCategory].
  ///
  /// Delegates to the underlying group query using `category.group` as the
  /// CelesTrak `GROUP` string.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl]
  /// (defaults to [defaultTtl]); otherwise fetches from CelesTrak, caches the
  /// payload, and returns the parsed records. Returns an empty list when the
  /// group matches no records.
  ///
  /// When [allowStale] is `true` and the network request fails, a stale cached
  /// list is returned (if present).
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
  Future<List<SatcatEntry>> fetchCategory(
    SatelliteCategory category, {
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByGroup(
        category.group,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatcatEntry] records for an arbitrary CelesTrak group string.
  ///
  /// The [group] string is passed through verbatim to the CelesTrak `GROUP=`
  /// query parameter - no validation against [SatelliteCategory] is performed.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl]
  /// (defaults to [defaultTtl]); otherwise fetches from CelesTrak, caches the
  /// payload, and returns the parsed records. Returns an empty list when the
  /// group matches no records.
  ///
  /// When [allowStale] is `true` and the network request fails, a stale cached
  /// list is returned (if present).
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
  Future<List<SatcatEntry>> fetchCategoryByGroup(
    String group, {
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByGroup(
        group,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches all [SatcatEntry] records matching an international designator.
  ///
  /// The [intlDesignator] is passed verbatim to the CelesTrak `INTDES=` query
  /// parameter. A launch-year prefix (e.g. `1998-067`) matches every object of
  /// that launch, so this is a bulk path.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl]
  /// (defaults to [defaultTtl]); otherwise fetches from CelesTrak, caches the
  /// payload, and returns the parsed records. Returns an empty list when the
  /// designator matches no records.
  ///
  /// When [allowStale] is `true` and the network request fails, a stale cached
  /// list is returned (if present).
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
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchByIntlDesignator(
        intlDesignator,
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Fetches the full active SATCAT catalogue.
  ///
  /// Returns a cached list when one exists and its cache age is within [ttl]
  /// (defaults to [defaultTtl]); otherwise fetches from CelesTrak, caches the
  /// payload, and returns the parsed records. The result is large (tens of
  /// thousands of records).
  ///
  /// This shares one cache entry with `fetchCategoryByGroup('active')` and with
  /// the [lookup] index.
  ///
  /// When [allowStale] is `true` and the network request fails, a stale cached
  /// list is returned (if present).
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
    Duration? ttl,
    bool allowStale = false,
    bool forceCache = false,
  }) =>
      _repository.fetchAll(
        ttl: ttl ?? _defaultTtl,
        allowStale: allowStale,
        forceCache: forceCache,
      );

  /// Looks up a single [SatcatEntry] by NORAD id against the full catalogue,
  /// returning `null` when no such object is in the catalogue.
  ///
  /// Unlike [fetchByNoradId], which issues a per-object SATCAT request, this is
  /// an O(1) lookup over an in-memory index built from the full-catalogue cache
  /// entry shared with [fetchAll] and `fetchCategoryByGroup('active')`. It is
  /// intended for repeated point lookups against the catalogue: the first call
  /// populates (or reuses) the catalogue cache and builds the index, and
  /// subsequent calls while the catalogue is fresh are served from memory with
  /// zero network calls and zero re-parsing.
  ///
  /// The index is rebuilt only when the catalogue is refetched (TTL expiry,
  /// eviction, or [clearCache]); a stable cache write-time is used to detect
  /// this, so repeated lookups while the catalogue is fresh never rebuild it.
  /// Concurrent first calls are coalesced into a single catalogue fetch.
  ///
  /// Freshness is always evaluated against [defaultTtl]; [lookup] does not take
  /// a per-call `ttl`. If you need a different freshness window, drive the
  /// shared catalogue cache via [fetchAll] with an explicit `ttl` first.
  ///
  /// When [allowStale] is `true` and the catalogue refetch fails, a stale
  /// cached catalogue is used (if present) rather than re-throwing.
  ///
  /// Throws [NetworkException] on transport failure when the catalogue must be
  /// (re)fetched but no usable cached entry is available and [allowStale] is
  /// `false`.
  Future<SatcatEntry?> lookup(int noradId, {bool allowStale = false}) async {
    final age = await _repository.allAge();
    // age == now - writeTime, so now.subtract(age) reconstructs the catalogue's
    // exact cache write-time regardless of the current instant. Comparing it to
    // the write-time the index was built from detects an out-of-band refetch
    // (e.g. a direct fetchAll) without re-parsing the catalogue.
    final fetchTime = age == null ? null : _clock.now.subtract(age);
    final isFresh = age != null && age < _defaultTtl;

    if (_index != null && isFresh && fetchTime == _indexFetchTime) {
      return _index![noradId];
    }

    // Coalesce concurrent rebuilds: the first caller owns the fetch; any others
    // arriving before it completes await the same future instead of refetching.
    await (_indexRebuild ??=
        _rebuildIndex(allowStale: allowStale).whenComplete(() {
      _indexRebuild = null;
    }));
    return _index?[noradId];
  }

  /// Refetches the full catalogue and rebuilds the in-memory [lookup] index.
  ///
  /// [_indexFetchTime] is set to the catalogue's reconstructed cache write-time
  /// so a subsequent [lookup] can recognise the index as current. If the entry
  /// was evicted between the fetch and this read, the write-time is left
  /// `null`, which simply forces the next [lookup] to rebuild again.
  Future<void> _rebuildIndex({required bool allowStale}) async {
    final catalog = await _repository.fetchAll(
      ttl: _defaultTtl,
      allowStale: allowStale,
    );
    final freshAge = await _repository.allAge();
    _indexFetchTime = freshAge == null ? null : _clock.now.subtract(freshAge);
    _index = {for (final e in catalog) e.noradId: e};
  }

  /// Returns the current cache age for the [noradId] entry.
  ///
  /// Returns `null` when no cache entry exists for this NORAD id.
  Future<Duration?> noradIdAge(int noradId) => _repository.noradIdAge(noradId);

  /// Returns the current cache age for [category].
  ///
  /// Resolves to the age of the underlying group entry (`category.group`).
  /// Returns `null` when no cache entry exists for that group.
  Future<Duration?> categoryAge(SatelliteCategory category) =>
      _repository.groupAge(category.group);

  /// Returns the current cache age for the [group] entry.
  ///
  /// Returns `null` when no cache entry exists for this group.
  Future<Duration?> groupAge(String group) => _repository.groupAge(group);

  /// Returns the current cache age for the [intlDesignator] entry.
  ///
  /// Returns `null` when no cache entry exists for this designator.
  Future<Duration?> intlDesignatorAge(String intlDesignator) =>
      _repository.intlDesignatorAge(intlDesignator);

  /// Returns the current cache age for the full-catalogue entry.
  ///
  /// Because [fetchAll] and `fetchCategoryByGroup('active')` share one cache
  /// entry, this reports the same age as `groupAge('active')`. Returns `null`
  /// when no cache entry exists.
  Future<Duration?> allAge() => _repository.allAge();

  /// Clears cached SATCAT entries and resets the [lookup] index.
  ///
  /// When [keyPrefix] is `null` (the default) only the SATCAT namespace is
  /// cleared, so GP cache entries are left untouched. When [keyPrefix] is
  /// supplied it is used verbatim.
  ///
  /// The in-memory [lookup] index is always discarded so the next [lookup]
  /// refetches the catalogue.
  Future<void> clearCache({String? keyPrefix}) async {
    _index = null;
    _indexFetchTime = null;
    await _repository.clearCache(keyPrefix: keyPrefix);
  }

  /// Releases the internal `http.Client` if this instance owns it.
  ///
  /// Has no effect when the client was created via [SatcatClient.withStore]
  /// (caller-owned lifecycle).
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
