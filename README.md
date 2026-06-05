# celestrak

A pure-Dart client for fetching, parsing, and caching satellite **TLE** and
**OMM** orbital data from [CelesTrak](https://celestrak.org) and optionally
[Space-Track](https://www.space-track.org).

No Flutter dependency - works on the Dart VM, servers, and Flutter alike.

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
  celestrak: ^0.0.1
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

> **CelesTrak only** — Space-Track uses a different mechanism (429 responses +
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
from that IP simply time out at the TCP level — they appear as connection
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

On Flutter Web, `dart:io` is unavailable, so persistent file caching is not
supported. The package automatically uses `MemoryCacheStore` on web: data is
fetched and cached for the lifetime of the page, but nothing is written to
disk and the cache is lost on reload.

If you need cross-session persistence on web, supply your own `CacheStore`
implementation and pass it via `CelestrakClient.withStore`.

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
