// ignore_for_file: avoid_print
import 'dart:io' show Directory;

import 'package:celestrak/celestrak.dart';

/// Demonstrates core [CelestrakClient] features: fetching by NORAD ID, cache
/// inspection, category fetching, and error handling.
Future<void> main() async {
  final cacheDir = Directory.systemTemp.path;
  final client = CelestrakClient(cacheDir: cacheDir);

  try {
    await _fetchByNoradId(client);
    await _fetchCategory(client);
    await _demonstrateCache(client);
    await _demonstrateAllowStale(client);
    await _demonstrateErrors(client);
  } finally {
    client.dispose();
  }
}

// 1. Fetch a single satellite by NORAD ID ─────────────────────────────────────

Future<void> _fetchByNoradId(CelestrakClient client) async {
  print('\n── fetchByNoradId (ISS = 25544) ──────────────────────────');
  final iss = await client.fetchByNoradId(25544);

  print('Name   : ${iss.name}');
  print('Epoch  : ${iss.epoch}');
  print('Source : ${iss.source}');
  print('Stale  : ${client.isStale(iss)}');
  print('Age    : ${await client.cacheAge(25544)}');
}

// 2. Fetch an entire satellite category ───────────────────────────────────────

Future<void> _fetchCategory(CelestrakClient client) async {
  print('\n── fetchCategory (stations) ──────────────────────────────');
  final satellites = await client.fetchCategory(SatelliteCategory.stations);

  print('Count  : ${satellites.length}');
  print('First  : ${satellites.first.name}');
  print('Age    : ${await client.categoryAge(SatelliteCategory.stations)}');
}

// 3. Demonstrate the cache pipeline ───────────────────────────────────────────

Future<void> _demonstrateCache(CelestrakClient client) async {
  print('\n── cache demo ────────────────────────────────────────────');

  final sw = Stopwatch()..start();
  await client.fetchByNoradId(25544);
  final networkMs = sw.elapsedMilliseconds;

  sw.reset();
  await client.fetchByNoradId(25544);
  final cacheMs = sw.elapsedMilliseconds;

  print('Network fetch : ${networkMs}ms');
  print('Cache hit     : ${cacheMs}ms');
  print('Cache age     : ${await client.cacheAge(25544)}');
}

// 4. Demonstrate allowStale ───────────────────────────────────────────────────

Future<void> _demonstrateAllowStale(CelestrakClient client) async {
  print('\n── allowStale demo ───────────────────────────────────────');

  // Force a very short TTL so the entry expires immediately.
  final tle = await client.fetchByNoradId(
    25544,
    ttl: Duration.zero,
    allowStale: true,
  );

  print('Got stale entry: ${tle.name} (stale=${client.isStale(tle)})');
}

// 5. Demonstrate typed exceptions ─────────────────────────────────────────────

Future<void> _demonstrateErrors(CelestrakClient client) async {
  print('\n── error handling ────────────────────────────────────────');

  // SatelliteNotFoundException - NORAD ID does not exist in the catalog.
  try {
    await client.fetchByNoradId(99999999);
  } on SatelliteNotFoundException catch (e) {
    print('SatelliteNotFoundException: ${e.message}');
  }

  // CacheMissException - forceCache=true but nothing is cached for this ID.
  await client.clearCache();
  try {
    await client.fetchByNoradId(99999, forceCache: true);
  } on CacheMissException catch (e) {
    print('CacheMissException: ${e.message}');
  }
}
