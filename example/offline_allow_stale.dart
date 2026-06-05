/// Offline fallback using allowStale.
///
/// This program demonstrates how to keep your app working when CelesTrak is
/// unreachable.  It fetches weather satellites once to warm the cache, then
/// simulates an offline scenario by setting an extremely short TTL so the
/// cached copy is considered expired.  With `allowStale: true` the library
/// returns the expired entry rather than throwing a [NetworkException].
///
/// Run from the package root:
///
/// ```sh
/// dart example/offline_allow_stale.dart
/// ```
///
/// ## Example
///
/// ```dart
/// import 'package:celestrak/celestrak.dart';
///
/// // Use a short TTL so the cache expires quickly for demonstration purposes.
/// final client = CelestrakClient(
///   cacheDir: '.dart_tool/celestrak_cache_stale',
///   defaultTtl: const Duration(seconds: 1),
/// );
///
/// // Step 1: populate the cache while online.
/// final satellites = await client.fetchCategory(SatelliteCategory.weather);
/// print('Fetched ${satellites.length} satellites.');
///
/// // Step 2: wait for the TTL to expire.
/// await Future<void>.delayed(const Duration(seconds: 2));
///
/// // Step 3: with allowStale: true the library attempts the network first.
/// // If the network succeeds you get fresh data; if it fails and a cached
/// // copy exists, the cached data is returned (marked with TleSource.local).
/// // NetworkException is only thrown when the network fails AND there is no
/// // cached copy at all.
/// try {
///   final result = await client.fetchCategory(
///     SatelliteCategory.weather,
///     allowStale: true,
///   );
///   print('Received ${result.length} satellites '
///       '(source: ${result.first.source}).');
/// } on NetworkException catch (e) {
///   // Thrown when the network fails and there is no stale cached copy.
///   print('No data available: $e');
/// }
/// ```
// ignore_for_file: avoid_print
library;

import 'package:celestrak/celestrak.dart';

Future<void> main() async {
  // Use a very short TTL so the first fetch immediately ages out, letting us
  // demonstrate the stale fallback without waiting hours.
  final client = CelestrakClient(
    cacheDir: '.dart_tool/celestrak_cache_stale',
    defaultFormat: CelestrakFormat.omm,
    timeout: const Duration(seconds: 15),
    maxRetries: 2,
    // A 1-second TTL ages out the cache entry almost immediately.  Note that
    // reading from the stale cache (with allowStale: true) does NOT reset the
    // TTL or write a new cache entry — the next call without allowStale will
    // still hit the network.
    defaultTtl: const Duration(seconds: 1),
  );

  try {
    // Step 1: fetch while online to warm the cache.
    print('Step 1 — fetching weather satellites to warm the cache...');
    final fresh = await client.fetchCategory(SatelliteCategory.weather);
    if (fresh.isEmpty) {
      print('No satellites returned — weather group may be empty.');
      return;
    }
    print('Fetched ${fresh.length} satellites (source: ${fresh.first.source})');

    // Step 2: wait for the TTL to expire.
    print('');
    print('Waiting 2 s for the TTL to expire...');
    await Future<void>.delayed(const Duration(seconds: 2));

    // Step 2: try with allowStale: true.
    // The library attempts the network first; if it fails and a cached copy
    // exists, the cached data is returned (marked with TleSource.local).
    print('');
    print('Step 2 — fetching with allowStale: true (TTL has expired)...');
    try {
      final stale = await client.fetchCategory(
        SatelliteCategory.weather,
        allowStale: true,
      );
      if (stale.isEmpty) {
        print('No satellites returned — weather group may be empty.');
        return;
      }
      final src = stale.first.source;
      print(
        'Received ${stale.length} satellites '
        '(source: $src — TleSource.local means stale cache was used)',
      );

      // Check whether the data should be treated as stale.
      final age = await client.categoryAge(SatelliteCategory.weather);
      if (age != null) {
        print('Cache age: ${age.inSeconds}s');
      }
    } on NetworkException catch (e) {
      // Raised when the network fails and there is no stale cached copy.
      print('Network failed and no stale copy was available: $e');
    }

    // Step 3: show what happens without allowStale when the TTL has expired
    // and the network is working — the library fetches fresh data.
    print('');
    print('Step 3 — fetching without allowStale (will hit network again)...');
    final refreshed = await client.fetchCategory(SatelliteCategory.weather);
    if (refreshed.isEmpty) {
      print('No satellites returned — weather group may be empty.');
      return;
    }
    print(
      'Refreshed ${refreshed.length} satellites '
      '(source: ${refreshed.first.source})',
    );
  } on NetworkException catch (e) {
    print('');
    print('Network error during initial warm-up: ${e.message}');
    if (e.statusCode != null) print('  HTTP status: ${e.statusCode}');
    if (e.uri != null) print('  URL        : ${e.uri}');
    print('');
    print('Tip: start this example while online to warm the cache first.');
  } finally {
    client.dispose();
  }
}
