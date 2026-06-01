/// A pure-Dart client for fetching, parsing, and caching satellite TLE and OMM
/// orbital data from CelesTrak and Space-Track.
///
/// Core types:
/// - `SatelliteTle` — the primary orbital record consumed by downstream
///   packages such as `satellite_passes`.
/// - `Omm` — full CCSDS Orbit Mean-Elements Message, present when data is
///   fetched in OMM format.
/// - `OmmParser` — parses CelesTrak OMM JSON into `Omm` values.
/// - `SatelliteCategory`, `TleSource`, `CelestrakFormat` — enumerations for
///   category queries, record provenance, and wire format selection.
/// - `CelestrakException` and subtypes — typed error hierarchy; no raw
///   `http` or `dart:io` exception escapes the public API.
/// - `Clock` / `SystemClock` — injectable time source for TTL and staleness.
/// - `StalenessChecker` — classifies orbital data freshness against a
///   configurable `defaultStaleThreshold`.
library;

export 'src/data/parsers/omm_parser.dart';
export 'src/domain/clock.dart';
export 'src/domain/enums.dart';
export 'src/domain/failures.dart';
export 'src/domain/omm.dart';
export 'src/domain/satellite_tle.dart';
export 'src/domain/staleness.dart';
