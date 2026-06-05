/// Inspect the cache age of a satellite entry, then clear the cache.
///
/// This program fetches the ISS by NORAD ID so the cache has an entry, reads
/// the age of that entry using [CelestrakClient.cacheAge], then clears the
/// entire cache and confirms the entry is gone.
///
/// Run from the package root:
///
/// ```sh
/// dart example/cache_inspect_clear.dart
/// ```
///
/// ## Example
///
/// ```dart
/// final client = CelestrakClient(cacheDir: '.dart_tool/celestrak_cache');
/// try {
///   await client.fetchByNoradId(25544);
///
///   final age = await client.cacheAge(25544);
///   if (age != null) {
///     print('Cache entry is ${age.inSeconds}s old.');
///   }
///
///   await client.clearCache();
///   final gone = await client.cacheAge(25544);
///   print('After clear: ${gone == null ? "no entry" : "${gone.inSeconds}s"}');
/// } finally {
///   client.dispose();
/// }
/// ```
// ignore_for_file: avoid_print
library;

import 'package:celestrak/celestrak.dart';

Future<void> main() async {
  final client = CelestrakClient(
    cacheDir: '.dart_tool/celestrak_cache_inspect',
    defaultFormat: CelestrakFormat.omm,
    timeout: const Duration(seconds: 10),
    maxRetries: 2,
  );

  try {
    // Step 1: confirm there is no cache entry yet.
    final before = await client.cacheAge(25544);
    print(
      'Cache age before fetch: '
      '${before == null ? "no entry" : "${before.inSeconds}s"}',
    );

    // Step 2: fetch the ISS to create a cache entry.
    print('');
    print('Fetching ISS (NORAD 25544)...');
    final iss = await client.fetchByNoradId(25544);
    print('Fetched: ${iss.name} (source: ${iss.source})');

    // Step 3: read the cache age — should be a few milliseconds.
    print('');
    final age = await client.cacheAge(25544);
    if (age == null) {
      print('Unexpected: no cache entry found after fetch.');
    } else {
      print('Cache age after fetch : ${age.inMilliseconds}ms');
    }

    // Step 4: check staleness using the client helper.
    // Note: isStale measures the orbital *epoch* age against
    // defaultStaleThreshold (3 days), NOT how long ago the data was cached.
    // A freshly fetched TLE will only be stale here if the satellite's epoch
    // itself is older than 3 days, which is unusual for actively tracked
    // objects like the ISS.
    final stale = client.isStale(iss);
    print('Is data stale?        : $stale');

    // Step 5: clear all cache entries.
    print('');
    print('Clearing the cache...');
    await client.clearCache();

    // Step 6: confirm the entry is gone.
    final gone = await client.cacheAge(25544);
    print(
      'Cache age after clear : '
      '${gone == null ? "no entry (cleared)" : "${gone.inSeconds}s"}',
    );
  } on SatelliteNotFoundException catch (e) {
    print('ERROR — satellite not found: $e');
  } on NetworkException catch (e) {
    print('');
    print('ERROR — network failure: ${e.message}');
    if (e.statusCode != null) print('  HTTP status: ${e.statusCode}');
    if (e.uri != null) print('  URL        : ${e.uri}');
    print('');
    print('Tip: celestrak.org may be temporarily unreachable.');
    print('     Check https://celestrak.org in a browser and retry.');
  } finally {
    client.dispose();
  }
}
