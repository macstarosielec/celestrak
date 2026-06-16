# celestrak

A pure-Dart client for fetching, parsing, and caching satellite **TLE** and
**OMM** orbital data from [CelesTrak](https://celestrak.org) and optionally
[Space-Track](https://www.space-track.org).

No Flutter dependency - works on the Dart VM, servers, and Flutter alike.

> **Web / WASM:** The default `CelestrakClient(cacheDir: ...)` constructor is
> web- and WASM-compatible. On web/WASM, `cacheDir` is ignored and an in-memory
> `MemoryCacheStore` is used automatically (no persistence). For a custom or
> persistent store on any platform, use `CelestrakClient.withStore(...)`.

---

## Accuracy warning

**TLE and OMM data ages quickly.** Orbital elements degrade within days; a
week-old TLE can place a satellite kilometres from its true position. Always
check `client.isStale(tle)` before acting on propagated results, and
refresh data when it is stale.

```dart
// client is a CelestrakClient - see the quickstart below.
final tle = await client.fetchByNoradId(25544);
if (client.isStale(tle)) {
  // Data is older than staleThreshold - refresh or warn the user.
}
```

The default `staleThreshold` is **3 days**. You can tighten it at construction
time by passing a shorter `Duration` (e.g. `staleThreshold: const Duration(days: 1)`).

---

## 30-second quickstart

### 1. Add the dependency

```yaml
dependencies:
  celestrak: ^1.2.0
```

### 2. Fetch by NORAD ID (ISS = 25544)

```dart
import 'dart:io' show Directory;

import 'package:celestrak/celestrak.dart';

Future<void> main() async {
  // Use Directory.systemTemp for cross-platform VM/server usage.
  // Flutter users: see the "Flutter: supplying the cache directory" section below.
  final client = CelestrakClient(cacheDir: Directory.systemTemp.path);
  try {
    final tle = await client.fetchByNoradId(25544);
    print('${tle.name}  epoch: ${tle.epoch}  stale: ${client.isStale(tle)}');
    // Pass tle.line1 / tle.line2 to an SGP4 propagator.
  } finally {
    client.dispose();
  }
}
```

### 3. Fetch a whole category

```dart
final satellites = await client.fetchCategory(SatelliteCategory.stations);
for (final sat in satellites) {
  print('${sat.noradId}  ${sat.name}');
}
```

### 4. Offline fallback with `allowStale`

When the network is unavailable, pass `allowStale: true` to get the
most-recent cached data instead of throwing a `NetworkException`.
Check `isStale` afterwards to decide whether the data is usable.

```dart
try {
  final tle = await client.fetchByNoradId(
    25544,
    allowStale: true,
  );
  if (client.isStale(tle)) {
    print('Warning: data is stale (${tle.epoch})');
  }
} on NetworkException {
  // Network failed and no cached entry exists.
} on SatelliteNotFoundException {
  // NORAD ID does not exist in the CelesTrak catalog.
}
```

---

## Staleness pipeline

Every fetch goes through three distinct freshness checks. Understanding how
they interact helps you tune the client for your accuracy requirements.

### 1. TTL (time-to-live) - cache freshness

When you call any `fetch*` method, the client first checks whether a cache
entry exists and how old it is. The age of the cache entry is the elapsed
time since the raw payload was downloaded and written to disk (or memory).

If that age is **less than** `ttl` (which defaults to `defaultTtl`, 2 hours),
the cached data is returned immediately with no network request. The returned
`SatelliteTle` carries `source == TleSource.local`.

If the cache entry is older than `ttl`, or no entry exists at all, the client
fetches a fresh copy from CelesTrak, writes it to the cache, and returns the
result with `source == TleSource.celestrak`.

This TTL is a cache-management concept. It answers: "is this downloaded
payload fresh enough to re-use?" It has nothing to do with the orbital
accuracy of the data itself.

### 2. `isStale` - orbital accuracy

`isStale` answers a different question: "are the orbital elements themselves
accurate enough to propagate?"

When you call `client.isStale(tle)`, the client computes how long ago the
TLE or OMM epoch was published by CelesTrak. If that duration exceeds
`staleThreshold` (default 3 days), `isStale` returns `true`.

This is independent of the cache. A TLE can be cache-fresh (downloaded 30
minutes ago) but orbitally stale (published 5 days ago and not updated since).
Conversely, a freshly updated TLE that was just published will be orbitally
fresh regardless of how old the cache entry is.

Always check `isStale` before passing orbital elements to a propagator.

### 3. `allowStale` - offline fallback

`allowStale` is a policy for what to do when a fetch would normally hit the
network but the network is unavailable.

With the default `allowStale: false`, a transport failure throws
`NetworkException`. With `allowStale: true`, the client instead returns the
most-recent cached entry even if it is older than `ttl`. The entry is still
served with `source == TleSource.local`. Check `isStale` after the call to
decide whether the data is usable for your application.

`allowStale` does not affect TTL-fresh cache hits. If the cache is within
TTL, the network is not consulted at all, so `allowStale` is irrelevant.

`allowStale` only masks **network** failures. Parse failures
(`TleParseException`, `OmmParseException`) are always re-thrown and never
masked by `allowStale`, even when a stale cache entry exists.

### How they interact

```
fetch called
  |
  +-- cache age < ttl? → return cached data (source=local), no network call
  |
  +-- cache expired or missing → attempt network fetch
        |
        +-- success → cache + return fresh data (source=celestrak)
        |
        +-- network failure
              |
              +-- allowStale=false → throw NetworkException
              |
              +-- allowStale=true + cached entry exists → return stale data
              |
              +-- allowStale=true + no cache entry → throw NetworkException
```

After any successful return, call `isStale(tle)` to check orbital accuracy
independent of where the data came from.

---

## Cache configuration guide

### `defaultTtl`

Controls how long a downloaded payload is reused before the client goes back
to CelesTrak. The default is **2 hours**, matching CelesTrak's own update
cycle. Setting it lower increases network traffic without giving you fresher
data (CelesTrak typically updates each group every 2 hours). Setting it higher
trades freshness for fewer requests.

Option 1 - shorter TTL (re-check every 30 minutes):

```dart
final client = CelestrakClient(
  cacheDir: Directory.systemTemp.path,
  defaultTtl: const Duration(minutes: 30),
);
```

Option 2 - longer TTL (cache for 6 hours, useful when multiple instances
on the same host share a single cache directory):

```dart
final client = CelestrakClient(
  cacheDir: '/shared/celestrak-cache',
  defaultTtl: const Duration(hours: 6),
);
```

You can also override TTL per call without changing the client default:

```dart
final tle = await client.fetchByNoradId(
  25544,
  ttl: const Duration(hours: 4),
);
```

### `staleThreshold`

Controls when `isStale` considers orbital elements too old to be accurate.
The default is **3 days**, which is conservative for LEO satellites. Orbits
that decay quickly (debris, very low satellites) or that require high
accuracy (rendezvous, proximity operations) may need a shorter threshold.

```dart
// Tighter threshold: flag anything older than 1 day.
final client = CelestrakClient(
  cacheDir: Directory.systemTemp.path,
  staleThreshold: const Duration(days: 1),
);
```

`staleThreshold` does not affect caching or network behaviour. It only
changes what `isStale` returns.

### `forceCache`

Pass `forceCache: true` to any `fetch*` call to make it consult only the
cache and never touch the network. This is useful for offline-first
applications that pre-populate the cache at startup.

```dart
try {
  final tle = await client.fetchByNoradId(25544, forceCache: true);
  // Came from cache; no network request was made.
} on CacheMissException catch (e) {
  // No cached entry - you must fetch without forceCache first.
  print('Cache miss for key ${e.key}');
}
```

When `forceCache: true` and no entry exists, `CacheMissException` is thrown
immediately. The network is never consulted, even if it is available.

### Sharing a cache directory

All instances pointing at the same `cacheDir` share cache entries. If you
run multiple scripts or processes against CelesTrak from the same host,
point them all at a single directory. Each process will serve cache hits
from the shared store rather than fetching independently, keeping your total
download count within CelesTrak's fair-use policy.

---

## Error handling guide

All errors thrown by this package are subtypes of `CelestrakException`. No
raw `http` or `dart:io` exception escapes the public API. You can catch the
base type to handle anything the package throws, or catch specific subtypes
to handle individual failure modes.

```dart
try {
  final tle = await client.fetchByNoradId(25544);
} on SatelliteNotFoundException catch (e) {
  // The NORAD ID does not exist in the CelesTrak catalog.
  // e.noradId - the queried NORAD ID, or 0 when the exception relates to a group/category query.
  // e.uri - the CelesTrak URL that returned "No GP data found".
  print('Not found: NORAD ${e.noradId}');
} on NetworkException catch (e) {
  // Transport failure (socket error, timeout, unexpected HTTP status)
  // after all retry attempts, with no usable cache entry available.
  // e.statusCode - HTTP status if a response was received (or null).
  // e.uri - the URL that failed.
  // e.cause - underlying exception (SocketException, TimeoutException, …).
  print('Network error ${e.statusCode}: ${e.message}');
} on CacheMissException catch (e) {
  // forceCache: true was used but no cache entry exists.
  // e.key - the cache key that was looked up.
  print('Cache miss: ${e.key}');
} on TleParseException catch (e) {
  // Malformed TLE structure or failed checksum.
  // e.field - the TLE field that caused the failure ('line1', 'line2', …).
  print('TLE parse error in ${e.field}: ${e.message}');
} on OmmParseException catch (e) {
  // Malformed OMM JSON (missing mandatory field, wrong type, etc.).
  // e.field - the OMM keyword that failed, when the failure is field-specific.
  print('OMM parse error at ${e.field}: ${e.message}');
} on CelestrakException catch (e) {
  // Catch-all for any other package exception.
  print('Celestrak error: ${e.message}');
}
```

### When each exception is thrown

| Exception | Thrown when |
|---|---|
| `SatelliteNotFoundException` | CelesTrak returns "No GP data found" for the requested NORAD ID or group name. Never masked by `allowStale`. |
| `NetworkException` | All retry attempts fail (socket error, timeout, or unexpected HTTP status) and no usable cache entry is available. Also thrown when `allowStale: true` but no cache entry exists at all. `allowStale` does **not** mask `TleParseException` or `OmmParseException` - those always propagate. |
| `CacheMissException` | `forceCache: true` is passed and the cache contains no entry for the requested key. No network call is made. |
| `TleParseException` | A downloaded TLE body has a malformed structure or a failed mod-10 checksum. |
| `OmmParseException` | A downloaded OMM JSON body is missing a mandatory field, or a field has an unexpected type or format. |
| `AuthenticationException` | Space-Track returns HTTP 401 or 403 (wrong credentials or expired session). Only relevant when using `SpaceTrackClient`. |
| `RateLimitException` | Space-Track returns HTTP 429. Only relevant when using `SpaceTrackClient`. |

Parse exceptions (`TleParseException`, `OmmParseException`) are not expected
in normal use against CelesTrak - they indicate that the remote data does not
conform to the published format. If you encounter them repeatedly, check
whether CelesTrak has changed its output format.

Retry behaviour applies to 5xx responses, socket errors, and timeouts.
4xx responses (including 404) are not retried. `SatelliteNotFoundException`
is derived from CelesTrak's body content, not from an HTTP status code.

---

## Platform notes

This package is **pure Dart** and has no dependency on Flutter. It runs on:

- **Dart VM** - servers, CLI tools, background workers.
- **Flutter** - Android, iOS, macOS, Windows, Linux.
- **Flutter Web / WASM** - the default constructor works; on web it
  transparently falls back to an in-memory cache (`cacheDir` is ignored). For
  persistent caching on web, supply your own `CacheStore` (see the Web section below).

No Flutter SDK is required to use this package in a Dart-only project.

The only runtime dependencies are `http` (cross-platform HTTP client) and
`meta` (annotations). The `http` package works on all Dart platforms; you
supply any compatible `http.Client` implementation for your target
(the default `IOClient` on VM/Flutter native, `BrowserClient` on web).

File caching (`FileCacheStore`) uses `dart:io` and is the default on all
non-web platforms. On Flutter Web and WASM, `dart:io` is unavailable, so the
default constructor **transparently falls back to a `MemoryCacheStore`**: a
conditional import ignores `cacheDir`, and the package compiles and runs on web
with no code change.

For explicit control, or a persistent store on web, construct the client via
`CelestrakClient.withStore` and pass a `MemoryCacheStore` (or any
`CacheStore` implementation that does not rely on `dart:io`):

```dart
final client = CelestrakClient.withStore(
  store: MemoryCacheStore(),
  httpClient: BrowserClient(), // from package:http/browser_client.dart
);
```

`MemoryCacheStore` keeps data in memory for the lifetime of the page - cache
is lost on reload. For cross-session persistence, provide your own `CacheStore`
backed by `localStorage`, IndexedDB, or similar.

---

## SATCAT metadata (owner, launch, decay, object type)

`SatcatClient` fetches CelesTrak **SATCAT** (Satellite Catalog) metadata for a
catalogued object: owner/country, launch date and site, decay date, object
type, operational status, and radar cross section. It is a **separate concern**
from the GP/OMM orbital data - metadata only, no orbital propagation - and is
**joinable to a `SatelliteTle` by NORAD ID**. The package never merges the two:
the `SatelliteTle`/`Omm` contract is unchanged.

`SatcatClient` mirrors `CelestrakClient`'s construction and caching, with a
longer default TTL (7 days) and staleness threshold (30 days) because SATCAT
metadata changes slowly.

```dart
import 'package:celestrak/celestrak.dart';

final satcat = SatcatClient(cacheDir: '.dart_tool/celestrak_cache');
try {
  final iss = await satcat.fetchByNoradId(25544);
  final owner = iss.owner;
  print('${iss.name}: ${owner.name} (EU-sovereign: ${owner.isEuSovereign})');
  print('On orbit: ${iss.isOnOrbit}, launched ${iss.launchDate}');
} finally {
  satcat.dispose();
}
```

### Indexed lookup over the full catalogue

`lookup(noradId)` answers repeated point queries against the cached full
catalogue in O(1), returning `null` when the object is absent. The first call
fetches and indexes the catalogue; subsequent calls while the cache is fresh
are served from memory with zero network calls.

```dart
final entry = await satcat.lookup(25544); // null if not catalogued
```

### Owner mapping (offline)

`SatcatEntry.owner` resolves the raw owner code to a `SatcatOwner` with a human
country name, region, and an EU-sovereign flag. The mapping is a compile-time
`const`, so it works offline with no network or runtime dependency. Use
`satcatOwnerForCode('FR')` directly when you only have a code.

### Joining GP and SATCAT

```dart
final celestrak = CelestrakClient(cacheDir: '.dart_tool/celestrak_cache');
final satcat = SatcatClient(cacheDir: '.dart_tool/celestrak_cache');

final tle = await celestrak.fetchByNoradId(25544);   // orbital elements
final meta = await satcat.fetchByNoradId(25544);      // SATCAT metadata
assert(tle.noradId == meta.noradId);                  // join key
```

See `example/satcat_lookup.dart` for a runnable program.

Space-Track SATCAT is also available, credential-gated, via
`SpaceTrackClient.fetchSatcatByQuery`.

---

## Space-Track data source (optional)

[CelesTrak](https://celestrak.org) works with no credentials and covers the
vast majority of use cases. **Space-Track is entirely optional.**

[Space-Track.org](https://www.space-track.org) is the US Space Force catalog,
updated more frequently than CelesTrak for certain object classes. Access
requires a free registered account (email + password from
[space-track.org/account/create](https://www.space-track.org/account/create)).

### Creating a SpaceTrackClient

```dart
import 'package:celestrak/celestrak.dart';

final client = SpaceTrackClient(
  identity: 'user@example.com', // your Space-Track email
  password: 'secret',           // your Space-Track password
);
try {
  final iss = await client.fetchByQuery(
    SpaceTrackQuery.byNoradId(25544),
  );
  print('${iss.name}  epoch: ${iss.epoch}  source: ${iss.source}');
  // iss.source == TleSource.spacetrack
} finally {
  client.dispose();
}
```

### Disabled client (no credentials)

Passing `null` or an empty string for either credential creates a
**disabled** client: construction succeeds without error, but calling
`fetchByQuery` throws a `StateError`. Gate on `isEnabled` to detect this:

```dart
import 'dart:io' show Platform;

final client = SpaceTrackClient(
  identity: Platform.environment['SPACETRACK_USER'],
  password: Platform.environment['SPACETRACK_PASS'],
);
if (client.isEnabled) {
  final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
}
```

### Throttling

Space-Track enforces a rate limit of 30 requests per minute and 300 per hour.
The client applies a conservative minimum inter-request interval (default:
**2 seconds**) to avoid hitting those limits. You can widen the gap at
construction time if your usage pattern is bursty:

```dart
final client = SpaceTrackClient(
  identity: 'user@example.com',
  password: 'secret',
  minRequestInterval: const Duration(seconds: 5),
);
```

Do not set `minRequestInterval` below 2 seconds in production - Space-Track
may suspend accounts that hammer the API.

### Error handling

```dart
try {
  final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
} on AuthenticationException catch (e) {
  // HTTP 401 or 403 - wrong credentials or session expired.
  // e.statusCode is 401 or 403; e.message describes the failure.
  print('Login failed (${e.statusCode}): ${e.message}');
} on RateLimitException catch (e) {
  // HTTP 429 - rate limit exceeded.
  // e.retryAfter is the Duration from the Retry-After header (or null).
  final wait = e.retryAfter ?? const Duration(minutes: 1);
  print('Rate limited; retry after ${wait.inSeconds}s');
} on NetworkException catch (e) {
  // Transport failure (socket error, timeout, unexpected HTTP status).
  print('Network error: ${e.message}');
} on SatelliteNotFoundException {
  // Space-Track returned no record for the requested NORAD ID.
}
```

### Privacy note

Credentials are held **in memory only** for the lifetime of the
`SpaceTrackClient` instance - never written to disk, never included in cache
files. They are released when the object is garbage-collected.

---

## Rate limits and fair use

> **CelesTrak only** - Space-Track uses a different mechanism (429 responses +
> `minRequestInterval`); see the Throttling section above.

CelesTrak has enforced a **one-download-per-update-cycle** policy since
March 2026. Each group or category is updated roughly every two hours, so
fetching the same dataset more than once per two-hour window violates the
policy.

This package respects that limit by default: the cache TTL (`defaultTtl`,
backed by the `kDefaultTtl` constant) is **2 hours**, so repeated calls within
the same update window are served from the local cache and produce no outbound
request.

**What happens if you exceed the limit.** CelesTrak does not return an HTTP
error code. Instead, it adds your IP address to a firewall block-list when
your IP address exceeds **100 MB of downloads per day**. Subsequent requests
from that IP simply time out at the TCP level - they appear as connection
timeouts or socket errors rather than as a 429 or 403 response.

**If you start seeing connection timeouts against CelesTrak** and other sites
are reachable, your IP is likely blocked. Options:

- Wait and retry later (exact block duration is not publicly documented).
- Switch to a different network (mobile hotspot, home broadband if you were
  on a server, etc.).
- Connect through a VPN to exit from a different IP.

**To stay within the limit:**

- Do not lower `defaultTtl` below 2 hours when fetching categories or groups.
- Avoid fetching large categories (e.g. `SatelliteCategory.starlink`) in a
  tight loop or from multiple concurrent processes sharing the same IP.
- If you run multiple applications or scripts against CelesTrak from the same
  host, point them all at a shared `cacheDir` so they read from one cached
  copy rather than each fetching independently.

---

## Flutter: supplying the cache directory

This package has no `path_provider` dependency so it stays usable on
servers and the Dart VM. Flutter apps obtain a suitable directory with one
line and pass it in:

```dart
import 'package:path_provider/path_provider.dart';

final dir = await getApplicationSupportDirectory();
final client = CelestrakClient(cacheDir: dir.path);
```

Add `path_provider` to your Flutter app's own `pubspec.yaml`; it is not
pulled in by this package.

---

## Web: memory-only cache

On Flutter Web and WASM, `dart:io` is unavailable, so persistent file caching is
not supported. The default `CelestrakClient` constructor handles this
**automatically**: via a conditional import it ignores `cacheDir` and uses an
in-memory `MemoryCacheStore` on web, so it compiles and runs there with no code
change.

For explicit control, construct the client via `CelestrakClient.withStore` and
pass a `MemoryCacheStore` (or any `CacheStore` implementation that does not rely
on `dart:io`). Data is cached for the lifetime of the page but nothing is written
to disk and the cache is lost on reload.

If you need cross-session persistence on web, supply your own `CacheStore`
implementation backed by `IndexedDB` or `localStorage` and pass it via
`CelestrakClient.withStore`.

---

## Error types

All errors are subtypes of `CelestrakException`. No raw `http` or `dart:io`
exceptions escape the public API.

| Type | When thrown |
|---|---|
| `SatelliteNotFoundException` | NORAD ID or group not in CelesTrak catalog |
| `NetworkException` | Transport failure and no usable cache |
| `TleParseException` | Malformed TLE checksum or structure |
| `OmmParseException` | Malformed OMM JSON |
| `CacheMissException` | `forceCache: true` and no cache entry |
| `AuthenticationException` | Space-Track credential rejected |
| `RateLimitException` | Space-Track rate limit hit |

---

## License

[MIT](LICENSE) © Maciej Starosielec
