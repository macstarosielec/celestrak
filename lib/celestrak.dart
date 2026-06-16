/// A pure-Dart client for fetching, parsing, and caching satellite TLE and OMM
/// orbital data from CelesTrak and Space-Track.
///
/// ## Quick start
///
/// ```dart
/// final client = CelestrakClient(cacheDir: '/tmp/celestrak');
/// try {
///   final iss = await client.fetchByNoradId(25544);
///   print('${iss.name} epoch=${iss.epoch} stale=${client.isStale(iss)}');
/// } finally {
///   client.dispose();
/// }
/// ```
///
/// ## Core types
///
/// - [CelestrakClient] - high-level facade; covers `fetchByNoradId`,
///   `fetchCategory`, `fetchCategoryByGroup`, `fetchByName`,
///   `fetchByIntlDesignator`, cache-age inspection, and `clearCache`.
///   Constructor parameters: `defaultTtl`, `defaultFormat`, `timeout`,
///   `maxAttempts`, `staleThreshold`, `clock`, `useIsolate` (offloads
///   multi-record category parses to a worker isolate via `Isolate.run`,
///   keeping the main isolate free during large responses such as Starlink).
/// - [SatcatClient] - high-level SATCAT facade; covers `fetchByNoradId`,
///   `fetchCategory`, `fetchCategoryByGroup`, `fetchByIntlDesignator`,
///   `fetchAll`, an indexed `lookup`, per-key cache-age inspection, and
///   `clearCache`. A concern separate from [CelestrakClient] (ADR-14); join
///   the two datasets on `noradId`.
/// - [SpaceTrackClient] - credentialed Space-Track.org facade.
/// - [SpaceTrackQuery] - value object describing a Space-Track query.
/// - [SatelliteTle] - the primary orbital record; carries `line1`/`line2`,
///   `epoch`, `source`, `fetchedAt`, `omm`, and computed `age`/`isStale`.
/// - [Omm] - full CCSDS Orbit Mean-Elements Message, present when data is
///   fetched in OMM format.
/// - [OmmParser] - parses CelesTrak OMM JSON into [Omm] values; exposed for
///   advanced callers who process raw CelesTrak responses directly.
/// - [SatcatParser] - parses CelesTrak SATCAT JSON and CSV into [SatcatEntry]
///   values; bulk parses return a [SatcatParseResult] carrying the skip count.
/// - [SatcatEntry] / [SatcatObjectType] - SATCAT per-object metadata record
///   (owner, launch, decay, object type, status), joinable to GP data by
///   `noradId`. `SatcatEntry.owner` resolves the raw owner code via
///   [satcatOwnerForCode].
/// - [SatcatOwner] / [satcatOwnerForCode] - bundled, offline owner-code ->
///   country/region resolution; flags EU-sovereign assets (EU-27 plus ESA,
///   EUMETSAT, EUTELSAT). Unknown codes degrade to a passthrough owner.
/// - [SatelliteCategory], [TleSource], [CelestrakFormat] - enumerations for
///   category queries, record provenance, and wire format selection.
/// - [CelestrakException] and subtypes ([AuthenticationException],
///   [CacheMissException], [NetworkException], [OmmParseException],
///   [RateLimitException], [SatcatParseException],
///   [SatelliteNotFoundException], [TleParseException]) - typed error
///   hierarchy; no raw `http` or `dart:io` exception escapes the public API.
/// - [TleRepository] - abstract repository interface; implement to provide
///   a custom cache/fetch/parse pipeline.
/// - [SatcatRepository] - abstract repository interface for SATCAT metadata;
///   implement to provide a custom SATCAT fetch/parse pipeline (a concern
///   separate from [TleRepository]).
/// - [CacheStore] - abstract interface for key-value byte caching; pass a
///   custom implementation to [CelestrakClient.withStore].
/// - [MemoryCacheStore] - in-memory [CacheStore] for testing and short-lived
///   caches.
/// - [Clock] / [SystemClock] - injectable time source for TTL and staleness.
/// - [StalenessChecker] - classifies orbital data freshness against a
///   configurable [defaultStaleThreshold].
/// - [ParseBenchmarkHook] / [NullParseBenchmarkHook] - extension point for
///   measuring parse duration in large category responses.
///
/// ## Configuration constants
///
/// - [kDefaultTtl] - default GP cache TTL (2 hours).
/// - [kSatcatDefaultTtl] - default SATCAT cache TTL (7 days).
/// - [kSatcatStaleThreshold] - SATCAT staleness threshold (30 days;
///   informational, since SATCAT metadata is near-static).
/// - [kDefaultMaxAttempts] - default total HTTP attempts (5).
/// - [kDefaultTimeout] - default per-attempt HTTP deadline (30 seconds).
library;

// These imports make the type names in the library doc comment above
// resolvable by the analyzer's comment_references lint. The `export`
// directives below are the authoritative public-API surface; these imports
// are only required for doc-comment reference resolution in this file.
import 'package:celestrak/src/client/celestrak_client.dart';
import 'package:celestrak/src/client/satcat_client.dart';
import 'package:celestrak/src/client/spacetrack_client.dart';
import 'package:celestrak/src/client/spacetrack_query.dart';
import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';
import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/data/parsers/parse_benchmark_hook.dart';
import 'package:celestrak/src/data/parsers/satcat_parser.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/constants.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/omm.dart';
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:celestrak/src/domain/satcat_owner.dart';
import 'package:celestrak/src/domain/satcat_repository.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:celestrak/src/domain/staleness.dart';
import 'package:celestrak/src/domain/tle_repository.dart';
import 'package:celestrak/src/network/http_transport.dart'
    hide HttpTransport, kBackoffBase, kBackoffMax;

export 'src/client/celestrak_client.dart';
export 'src/client/satcat_client.dart';
export 'src/client/spacetrack_client.dart';
export 'src/client/spacetrack_query.dart';
export 'src/data/local/cache_store.dart';
export 'src/data/local/memory_cache_store.dart';
export 'src/data/parsers/omm_parser.dart';
export 'src/data/parsers/parse_benchmark_hook.dart';
export 'src/data/parsers/satcat_parser.dart';
export 'src/domain/clock.dart';
export 'src/domain/constants.dart';
export 'src/domain/enums.dart';
export 'src/domain/failures.dart';
export 'src/domain/omm.dart';
export 'src/domain/satcat_entry.dart';
export 'src/domain/satcat_owner.dart';
export 'src/domain/satcat_repository.dart';
export 'src/domain/satellite_tle.dart';
export 'src/domain/staleness.dart';
export 'src/domain/tle_repository.dart';
export 'src/network/http_transport.dart'
    hide HttpTransport, kBackoffBase, kBackoffMax;
