# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-06-20

### Added

- `OmmParseObserver`, an optional callback (`void Function(Map<String, int>)`)
  on `OmmParser`, `CelestrakClient`, `SpaceTrackClient`, and `TleRepositoryImpl`.
  It is invoked once per parse operation with the aggregate count of CCSDS
  metadata fields (`CENTER_NAME`, `REF_FRAME`, `TIME_SYSTEM`,
  `MEAN_ELEMENT_THEORY`) that were absent and defaulted. See
  [ADR-0014](doc/adr/0014-omm-parse-observer.md).

### Changed

- **OMM parsing is now silent by default.** `OmmParser` no longer writes a
  `dart:developer` warning when it defaults a missing CCSDS metadata field.
  CelesTrak GP data always omits these fields, so the previous behaviour
  produced one warning per field per record (tens of thousands of lines for a
  large category fetch). Supply an `OmmParseObserver` to be notified instead.

### Removed

- The unconditional `dart:developer` logging in `OmmParser`.

## [1.2.0] - 2026-06-16

### Added

- Full reconciliation of the offline SATCAT owner-code table
  (`satcatOwnerForCode`) against the authoritative
  `celestrak.org/satcat/sources.php` list, expanding it from a conservative
  46-code subset to the complete 130-code set (all CelesTrak source codes
  except the `TBD` / `UNK` administrative sentinels, which remain passthrough).
  This resolves CEL-150.

### Fixed

- Corrected owner-code errors in the previous knowledge-built table: `AUS` now
  resolves to Australia (Oceania) rather than Austria, and Austria is the
  separate code `ASRA`; South Africa is `SAFR` (was the non-CelesTrak `RSA`)
  and Taiwan is `ROC` (was the non-CelesTrak `TWN`). The invented `AUST` /
  `RSA` / `TWN` codes are gone and now degrade to passthrough.
- Verified every `isEuSovereign` flag against the real source list; added the
  EU members `ASRA`, `BUL`, `HRV`, `EST`, `IRL`, `LTU`, `ROM`, `SVN` and the
  all-EU-participant operators `FRIT` (France/Italy) and `ESRO` (the ESA
  predecessor) to the EU-sovereign set.

## [1.1.0] - 2026-06-16

### Added

- SATCAT (Satellite Catalog) metadata support: per-object owner/country, launch
  date and site, decay date, object type, operational status, and radar cross
  section. SATCAT is a separate concern joinable to a `SatelliteTle` by NORAD
  ID; it does not change the existing `SatelliteTle`/`Omm` contract and adds no
  orbital propagation.
- `SatcatClient` facade, a parallel to `CelestrakClient` with the same
  construction ergonomics (`SatcatClient.new` with a `cacheDir`, or
  `SatcatClient.withStore`). Methods: `fetchByNoradId`, `fetchCategory`,
  `fetchCategoryByGroup`, `fetchByIntlDesignator`, `fetchAll`, an indexed
  `lookup(noradId)` (O(1) over the cached full catalogue, `null` when absent),
  per-query `*Age` cache-age inspection, `clearCache`, and `dispose`.
- `SatcatEntry` immutable model and `SatcatObjectType` enum, parsed from the
  CelesTrak `satcat/records.php` JSON and CSV formats (`SatcatParser`).
- `SatcatOwner` and the offline `satcatOwnerForCode` mapping that resolves a
  raw owner code to a country/region with an EU-sovereign flag. The mapping is
  a compile-time `const`, so it is always available offline and adds no runtime
  dependency.
- Dataset-discriminated SATCAT cache with a longer default TTL (7 days) and
  staleness threshold (30 days) than the GP path, sharing the existing
  cache-dir seam and `CacheStore` interface. New constants `kSatcatDefaultTtl`
  and `kSatcatStaleThreshold`.
- `SatcatParseException`, a sibling of `OmmParseException` in the sealed
  exception tree, for malformed single-record SATCAT responses.
- Optional Space-Track SATCAT support via `SpaceTrackClient.fetchSatcatByQuery`,
  credential-gated and throttled exactly like the GP path.
- New example `example/satcat_lookup.dart`: fetches the ISS SATCAT record and
  prints its owner country and EU-sovereign flag.

## [1.0.5] - 2026-06-10

### Fixed

- Fixed WASM incompatibility caused by an unconditional `dart:isolate` import
  in `tle_repository_impl.dart`. The `Isolate.run` call used for the optional
  `useIsolate` performance feature is now gated behind a conditional import:
  `parse_runner_native.dart` (loaded on native via `dart.library.io`) wraps
  `Isolate.run`; `parse_runner_stub.dart` (loaded on web/WASM) runs the parse
  synchronously instead. The `useIsolate` API is unchanged; the flag is
  silently ignored on web/WASM.

## [1.0.4] - 2026-06-10

### Fixed

- Completed WASM compatibility. Removed all unconditional `dart:io` imports
  from the public API chain:
  - `celestrak_client.dart` — replaced `import 'dart:io' show Directory` and
    `FileCacheStore(Directory(cacheDir))` with a conditional-import factory
    (`default_cache_store_io.dart` / `default_cache_store_stub.dart`). On
    web/WASM, `cacheDir` is ignored and a `MemoryCacheStore` is used; on
    native, behaviour is unchanged.
  - `spacetrack_data_source.dart` — replaced `import 'dart:io' show
    SocketException` with the same conditional-import shim introduced in
    v1.0.3 (`socket_exception_io.dart` / `socket_exception_stub.dart`).

## [1.0.3] - 2026-06-09

### Fixed

- Fixed WASM incompatibility in `http_transport.dart`. The unconditional
  `import 'dart:io'` (used only for `SocketException`) is replaced with a
  conditional import: `dart:io` is loaded on native platforms, a no-op stub on
  web/WASM. `SocketException` handling is preserved on native; the package now
  passes WASM compatibility checks on pub.dev.

## [1.0.2] - 2026-06-09

### Fixed

- Removed `dart:io` import from `failures.dart` — it was only referenced in a
  doc comment. The package now passes WASM compatibility checks on pub.dev.

## [1.0.1] - 2026-06-09

### Added

- `example/main.dart` — runnable CLI script demonstrating every public API:
  `fetchByNoradId`, `fetchCategory`, `fetchCategoryByGroup`, `fetchByName`,
  `fetchByIntlDesignator`, `cacheAge`, `clearCache`, `isStale`, and all cache
  control parameters (`allowStale`, `forceCache`, `ttl`).

## [1.0.0] - 2026-06-05

First stable release. Public API frozen (`package:celestrak`); no breaking changes from the 0.0.1 scaffold.

### Added

#### Domain models

- `SatelliteTle` — immutable orbital record carrying `noradId`, `name`,
  verbatim `line1`/`line2` strings, `epoch`, `fetchedAt`, `source`, and an
  optional `Omm` payload. Provides `age`, `ageAt(DateTime)`, `isStale`,
  `classification`, `copyWith`, and value equality.
- `Omm` — full CCSDS Orbit Mean-Elements Message mapping all mandatory OMM
  keywords plus CelesTrak header fields. `null` `objectName`/`objectId` are
  tolerated for analyst (80000-series) objects.
- `TleSource` enum — `celestrak`, `spacetrack`, `local`; stamps every
  `SatelliteTle` with its data provenance.
- `CelestrakFormat` enum — `omm` (recommended default, supports 9-digit
  catalog numbers) and `tle` (legacy 3-line format).
- `SatelliteCategory` enum — named CelesTrak groups: `stations`, `starlink`,
  `weather`, `amateur`, `visual`, `gps`, `galileo`, `glonass`,
  `cosmos2251Debris`, `active`, `lastThirtyDays`. Each value exposes a
  `.group` string for the `GROUP=` query parameter.

#### Parsers

- `OmmParser` — stateless, reusable parser for CelesTrak OMM JSON. Supports
  single-record `parse()` and lazy `parseAllLazy()` for large category
  responses. All failures surface as `OmmParseException`.
- TLE parser (internal) — splits 3-line records, validates mod-10 checksum
  (toggle-able), decodes 2-digit-year + fractional-DOY epoch, and handles
  1–9-digit NORAD catalog IDs.
- Dual-format stitch — when fetching in OMM format the pipeline issues a
  companion `FORMAT=TLE` request to obtain verbatim TLE lines required by
  SGP4 propagators. Objects with catalog numbers ≥ 100 000 (alpha-5 encoding)
  gracefully receive empty `line1`/`line2` when absent from the TLE response.

#### Cache pipeline

- `CacheStore` — abstract interface for key-value byte caching with
  `read`, `write`, `age`, and `clear` operations.
- `MemoryCacheStore` — in-memory `CacheStore` implementation for testing and
  web targets (where file I/O is unavailable).
- `FileCacheStore` (internal) — `dart:io`-backed store with write-temp-then-
  rename atomicity and sidecar timestamp files for age tracking. Corrupt or
  truncated files are treated as cache misses.
- `CacheKeyBuilder` (internal) — builds filename-safe, path-traversal-free
  cache keys encoding `{queryType, queryValue, format, source}`.
- `Clock` / `SystemClock` — injectable time source used throughout the
  pipeline for TTL checks, age calculations, and staleness classification.
- `StalenessChecker` — classifies orbital data against a configurable
  `staleThreshold` (default 3 days). `isFresh(cacheAge, ttl:)` determines
  cache validity; `isStale(epoch)` determines orbital data accuracy.
- `defaultStaleThreshold` constant — `Duration(days: 3)`; LEO-conservative
  default; override for highly elliptical orbits or debris with fast decay.

#### Cache policies: `allowStale` and `forceCache`

- `allowStale` parameter (all fetch methods) — when `true` and the network
  request fails, the repository returns a stale cached entry (if present)
  rather than re-throwing. The returned record carries `TleSource.local` and
  its `isStale` flag reflects the orbital epoch age. When `false` (default),
  any network failure with no fresh cache raises `NetworkException`.
- `forceCache` parameter (all fetch methods) — when `true`, the network is
  never contacted. If no cached entry exists a `CacheMissException` is thrown
  immediately. When both `forceCache: true` and `allowStale: true` are
  supplied, `forceCache` takes unconditional priority.
- Stale-while-revalidate — TTL-expired entries trigger a remote fetch; if
  the fetch succeeds the cache is refreshed. If the fetch fails and
  `allowStale: true`, the expired entry is returned with `TleSource.local`.

#### `isStale` on `SatelliteTle`

- `SatelliteTle.isStale({DateTime? now, Duration staleThreshold})` — checks
  whether the orbital epoch has aged past `staleThreshold` (default 3 days).
  Accepts an optional pinned `now` for deterministic tests.
- `CelestrakClient.isStale(SatelliteTle)` — convenience method on the
  facade that uses the client's configured `staleThreshold`.

#### Repository and client facades

- `TleRepository` — abstract interface describing the cache → TTL → fetch →
  parse → stamp pipeline. Supports `fetchByNoradId`, `fetchCategory`,
  `fetchCategoryByGroup`, `fetchByName`, `fetchByIntlDesignator`, per-method
  cache-age queries (`cacheAge`, `categoryAge`, `groupAge`, `nameAge`,
  `intlDesignatorAge`), and `clearCache`.
- `CelestrakClient` — high-level facade over `TleRepository`.
  - Default constructor: supply a `cacheDir` path; the client owns an
    internal `http.Client` and a `FileCacheStore`. Call `dispose` when done.
  - `CelestrakClient.withStore`: inject a custom `CacheStore` and
    `http.Client`; lifecycle remains the caller's responsibility.
  - Configuration parameters: `defaultTtl`, `defaultFormat`, `timeout`,
    `maxAttempts`, `staleThreshold`, `clock`, `useIsolate`.
  - `fetchByNoradId(int noradId, ...)` — single-object lookup via
    `CATNR=<id>`.
  - `fetchCategory(SatelliteCategory, ...)` — group lookup via
    `GROUP=<category.group>`.
  - `fetchCategoryByGroup(String group, ...)` — arbitrary group string
    passthrough.
  - `fetchByName(String name, ...)` — name substring search via `NAME=<name>`;
    returns an empty list on no match (never throws).
  - `fetchByIntlDesignator(String, ...)` — international designator lookup
    via `INTDES=<designator>`; returns an empty list on no match.
  - `cacheAge`, `categoryAge`, `groupAge`, `nameAge`, `intlDesignatorAge`
    — per-key cache-age inspection.
  - `clearCache({String? keyPrefix})` — removes all cache entries or those
    matching a prefix.
  - `isStale(SatelliteTle)` — staleness convenience using the client's
    configured threshold.
  - `dispose()` — closes the owned `http.Client` (no-op for `withStore`).
- `HttpTransport` (internal) — bounded retry with exponential backoff
  (5xx / `TimeoutException` / `SocketException` only; 4xx never retried),
  HTTPS enforcement, and injectable `http.Client`.

#### Space-Track support

- `SpaceTrackClient` — credentialed facade for Space-Track.org GP API.
  - Performs POST-based login and holds the session cookie in memory only;
    credentials are never written to disk.
  - `SpaceTrackClient.withClient` constructor for test injection.
  - Credential gating: pass `null` or empty credentials to construct a
    disabled client; `isEnabled` returns `false` and `fetchByQuery` throws
    `StateError` rather than an authentication error.
  - `fetchByQuery(SpaceTrackQuery)` — fetches and parses a single GP record;
    stamps result with `TleSource.spacetrack`.
  - Enforces a configurable minimum inter-request interval (`minRequestInterval`,
    default 2 s) as a courtesy to Space-Track rate limits.
  - Idempotent `dispose()`.
- `SpaceTrackQuery` — immutable value object for Space-Track queries.
  Currently supports `SpaceTrackQuery.byNoradId(int)`.
- `AuthenticationException` — raised on HTTP 401/403 from Space-Track.
- `RateLimitException` — raised on HTTP 429; carries optional `retryAfter`.

#### Error hierarchy

- `CelestrakException` (sealed base) — all library exceptions share a common
  `message` field and are exhaustively matchable in a `switch`.
- `NetworkException` — transport failure; carries optional `statusCode`,
  `uri`, and `cause`.
- `SatelliteNotFoundException` — CelesTrak returned the "No GP data found"
  sentinel. `noradId` is `0` for group/category queries.
- `OmmParseException` — OMM JSON parse failure; optional `field` names the
  offending keyword.
- `TleParseException` — TLE text parse failure; optional `field` names the
  offending line.
- `CacheMissException` — `forceCache: true` with no cached entry; `key`
  identifies the absent cache key.
- `AuthenticationException` — Space-Track 401/403; carries `statusCode`.
- `RateLimitException` — Space-Track 429; carries optional `retryAfter`.

#### Benchmark extension point

- `ParseBenchmarkHook` / `NullParseBenchmarkHook` — interface for measuring
  parse duration in multi-record category responses. Inject into `OmmParser`
  to collect timing signals without modifying the production code path.

#### Configuration constants

- `kDefaultTtl` — `Duration(hours: 2)`.
- `kDefaultMaxAttempts` — `5` (1 initial + 4 retries).
- `kDefaultTimeout` — `Duration(seconds: 30)`.

#### Public API surface

- Frozen public API surface: every symbol exported from `package:celestrak`
  is intentional and documented. Internal types (`HttpTransport`,
  `CacheKeyBuilder`, `TleOmmStitcher`, `FileCacheStore`, backoff constants)
  are not part of the public contract.

## [0.0.1] - 2026-05-30

### Added
- Initial package scaffold.

[1.2.0]: https://github.com/macstarosielec/celestrak/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/macstarosielec/celestrak/compare/v1.0.5...v1.1.0
[1.0.5]: https://github.com/macstarosielec/celestrak/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/macstarosielec/celestrak/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/macstarosielec/celestrak/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/macstarosielec/celestrak/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/macstarosielec/celestrak/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/macstarosielec/celestrak/compare/v0.0.1...v1.0.0
[0.0.1]: https://github.com/macstarosielec/celestrak/releases/tag/v0.0.1
