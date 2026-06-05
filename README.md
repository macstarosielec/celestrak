# celestrak

A pure-Dart client for fetching, parsing, and caching satellite **TLE** and
**OMM** orbital data from [CelesTrak](https://celestrak.org).

No Flutter dependency — works on the Dart VM, servers, and Flutter alike.

---

## Accuracy warning

**TLE and OMM data ages quickly.** Orbital elements degrade within days; a
week-old TLE can place a satellite kilometres from its true position. Always
check `client.isStale(tle)` before acting on propagated results, and
refresh data when it is stale.

```dart
// client is a CelestrakClient — see the quickstart below.
final tle = await client.fetchByNoradId(25544);
if (client.isStale(tle)) {
  // Data is older than staleThreshold — refresh or warn the user.
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
