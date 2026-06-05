/// Fetch a single satellite by NORAD ID.
///
/// This program fetches the ISS (NORAD 25544) from CelesTrak, prints its
/// orbital elements, then shows that a second call within the TTL is served
/// from the local cache.  A second satellite (Hubble, NORAD 20580) is fetched
/// in legacy TLE format to show format switching.
///
/// Run from the package root:
///
/// ```sh
/// dart example/fetch_iss.dart
/// ```
///
/// ## Example
///
/// ```dart
/// import 'package:celestrak/celestrak.dart';
///
/// final client = CelestrakClient(
///   cacheDir: '.dart_tool/celestrak_cache',
///   defaultFormat: CelestrakFormat.omm,
///   timeout: const Duration(seconds: 10),
/// );
/// try {
///   final iss = await client.fetchByNoradId(25544);
///   print('${iss.name} — epoch: ${iss.epoch}');
/// } finally {
///   client.dispose();
/// }
/// ```
// ignore_for_file: avoid_print
library;

import 'package:celestrak/celestrak.dart';

Future<void> main() async {
  final client = CelestrakClient(
    cacheDir: '.dart_tool/celestrak_cache',
    defaultFormat: CelestrakFormat.omm,
    timeout: const Duration(seconds: 10),
    maxAttempts: 2,
  );

  try {
    print('Fetching ISS (NORAD 25544) in OMM format...');
    final iss = await client.fetchByNoradId(25544);

    print('');
    print('Name        : ${iss.name}');
    print('NORAD ID    : ${iss.noradId}');
    print('Epoch       : ${iss.epoch}');
    print('Source      : ${iss.source}');
    print('Inclination : ${iss.omm?.inclination}°');
    print('Eccentricity: ${iss.omm?.eccentricity}');
    print('TLE line 1  : ${iss.line1}');
    print('TLE line 2  : ${iss.line2}');

    print('');
    print('Fetching again (should be a cache hit)...');
    final iss2 = await client.fetchByNoradId(25544);
    final cacheHit = iss2.source == TleSource.local
        ? 'cache hit (correct)'
        : 'WARNING: expected cache hit, got ${iss2.source}';
    print('Source      : ${iss2.source}  — $cacheHit');

    print('');
    print('Fetching Hubble (NORAD 20580) in TLE format...');
    final hubble = await client.fetchByNoradId(
      20580,
      format: CelestrakFormat.tle,
    );
    print('Name        : ${hubble.name}');
    print('NORAD ID    : ${hubble.noradId}');
    print('TLE line 1  : ${hubble.line1}');
    print('TLE line 2  : ${hubble.line2}');
  } on SatelliteNotFoundException catch (e) {
    print('ERROR — satellite not found: $e');
  } on NetworkException catch (e) {
    print('');
    print('ERROR — network failure: ${e.message}');
    if (e.statusCode != null) print('  HTTP status : ${e.statusCode}');
    if (e.uri != null) print('  URL         : ${e.uri}');
    if (e.cause != null) print('  Cause       : ${e.cause}');
    print('');
    print('Tip: celestrak.org may be temporarily unreachable.');
    print('     Check https://celestrak.org in a browser and retry.');
  } finally {
    client.dispose();
  }
}
