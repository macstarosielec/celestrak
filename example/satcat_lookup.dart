/// Look up SATCAT metadata for a satellite by NORAD ID.
///
/// This program fetches the SATCAT (Satellite Catalog) record for the ISS
/// (NORAD 25544) from CelesTrak and prints its owner country, EU-sovereign
/// flag, object type, and on-orbit status. It then shows that a second call
/// within the TTL is served from the local cache, and uses the indexed
/// lookup() over the cached full catalogue.
///
/// SATCAT is a separate concern from the GP/OMM orbital data: it is metadata
/// only (owner, launch, decay, object type, size), joinable to a SatelliteTle
/// by NORAD ID. See the README "SATCAT metadata" section for the join pattern.
///
/// Run from the package root:
///
/// ```sh
/// dart example/satcat_lookup.dart
/// ```
///
/// ## Example
///
/// ```dart
/// import 'package:celestrak/celestrak.dart';
///
/// final client = SatcatClient(cacheDir: '.dart_tool/celestrak_cache');
/// try {
///   final iss = await client.fetchByNoradId(25544);
///   final owner = iss.owner;
///   print('${iss.name} owner: ${owner.name} (EU: ${owner.isEuSovereign})');
/// } finally {
///   client.dispose();
/// }
/// ```
// ignore_for_file: avoid_print
library;

import 'package:celestrak/celestrak.dart';

Future<void> main() async {
  final client = SatcatClient(
    cacheDir: '.dart_tool/celestrak_cache',
    timeout: const Duration(seconds: 10),
    maxAttempts: 2,
  );

  try {
    print('Fetching SATCAT metadata for the ISS (NORAD 25544)...');
    final iss = await client.fetchByNoradId(25544);
    final owner = iss.owner;

    print('');
    print('Name        : ${iss.name}');
    print('NORAD ID    : ${iss.noradId}');
    print('Int. desig. : ${iss.objectId}');
    print('Owner code  : ${iss.ownerCode}');
    print('Owner       : ${owner.name}');
    print('Region      : ${owner.region ?? "(unknown)"}');
    print('EU-sovereign: ${owner.isEuSovereign}');
    print('Object type : ${iss.objectType.name}');
    print('On orbit    : ${iss.isOnOrbit}');
    print('Launch date : ${iss.launchDate}');
    print('Launch site : ${iss.launchSite}');

    print('');
    print('Fetching again (should be a cache hit, zero network)...');
    final age = await client.noradIdAge(25544);
    print('Cache age   : ${age ?? "(not cached)"}');

    print('');
    print('Indexed lookup() over the cached full catalogue...');
    final viaLookup = await client.lookup(25544);
    if (viaLookup != null) {
      print('lookup(25544): ${viaLookup.name} (${viaLookup.owner.name})');
    } else {
      print('lookup(25544): not in the catalogue');
    }
    final absent = await client.lookup(99999999);
    print('lookup(99999999): ${absent == null ? "not found (correct)" : "?"}');
  } on SatelliteNotFoundException catch (e) {
    print('ERROR - satellite not found: ${e.message}');
  } on SatcatParseException catch (e) {
    print('ERROR - could not parse the SATCAT response: ${e.message}');
  } on NetworkException catch (e) {
    print('');
    print('ERROR - network failure: ${e.message}');
    if (e.statusCode != null) print('  HTTP status : ${e.statusCode}');
    if (e.uri != null) print('  URL         : ${e.uri}');
    print('');
    print('Tip: celestrak.org may be temporarily unreachable.');
    print('     Check https://celestrak.org in a browser and retry.');
  } finally {
    client.dispose();
  }
}
