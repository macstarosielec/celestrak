# celestrak

A **pure-Dart** client for fetching, parsing, and caching satellite **TLE** and
**OMM** orbital data from [CelesTrak](https://celestrak.org) and Space-Track.
No Flutter dependency — usable on the Dart VM, servers, and Flutter alike.

> **Status: pre-release.** This is an early scaffold — the public API is not yet
> implemented. Watch the repository for the first usable release.

## Why

The Dart ecosystem has low-level SGP4 math (`package:orbit`) but no
developer-friendly data layer: no TLE/OMM client, no caching, no staleness
handling. `celestrak` fills that gap and feeds higher-level packages such as
`satellite_passes` (pass prediction).

## Planned quickstart

```dart
import 'package:celestrak/celestrak.dart';

final client = CelesTrakClient(cacheDir: someDirectory);

// Fetch the ISS by NORAD ID (OMM JSON by default).
final iss = await client.fetchByNoradId(25544);

// Fetch a whole category.
final stations = await client.fetchCategory(SatelliteCategory.stations);
```

> ⚠️ **Orbital data ages.** TLE/OMM accuracy degrades over time; this package
> surfaces data age so you can decide when to refresh. (Details in a later
> release.)

## License

[MIT](LICENSE) © Maciej Starosielec
