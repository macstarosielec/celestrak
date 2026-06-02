/// Quick smoke-test: fetches live ISS data from CelesTrak and prints it.
///
/// Run from the package root:
///   dart example/fetch_iss.dart
// ignore_for_file: avoid_print
library;

import 'package:celestrak/celestrak.dart';

void main() async {
  final client = CelestrakClient(
    cacheDir: '.dart_tool/celestrak_cache',
    defaultFormat: CelestrakFormat.omm,
    timeout: const Duration(seconds: 10),
    maxRetries: 2,
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
    print('Fetching again (should be cache hit)...');
    final iss2 = await client.fetchByNoradId(25544);
    print('Source      : ${iss2.source}  ← should be TleSource.local');

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
