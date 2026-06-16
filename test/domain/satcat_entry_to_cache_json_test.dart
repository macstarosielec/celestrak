/// CEL-141: SatcatEntry.toCacheJson round-trip.
///
/// Verifies that `SatcatEntry.fromCelestrakJson(e.toCacheJson()) == e` for a
/// representative spread of entries: the ISS fixture, a fully-populated entry,
/// an all-nulls entry, a decayed entry, and one entry per [SatcatObjectType].
/// The round-trip is what makes the SATCAT cache layer lossless.
library;

import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:test/test.dart';

void main() {
  /// Asserts the CelesTrak-shaped JSON round-trip holds for [entry].
  void expectRoundTrips(SatcatEntry entry) {
    final reconstructed = SatcatEntry.fromCelestrakJson(entry.toCacheJson());
    expect(reconstructed, equals(entry));
    expect(reconstructed.hashCode, equals(entry.hashCode));
  }

  group('SatcatObjectType.code is the inverse of fromCode', () {
    test('every type round-trips through code -> fromCode', () {
      for (final type in SatcatObjectType.values) {
        expect(SatcatObjectType.fromCode(type.code), equals(type));
      }
    });

    test('emits the canonical CelesTrak short codes', () {
      expect(SatcatObjectType.payload.code, equals('PAY'));
      expect(SatcatObjectType.rocketBody.code, equals('R/B'));
      expect(SatcatObjectType.debris.code, equals('DEB'));
      expect(SatcatObjectType.unknown.code, equals('UNK'));
    });
  });

  group('SatcatEntry.toCacheJson round-trip', () {
    test('reconstructs the parsed ISS fixture entry', () async {
      final json = await File(
        'test/fixtures/satcat/iss_25544_satcat.json',
      ).readAsString();
      // Parse through the public parser, then round-trip via the cache JSON.
      const parser = SatcatParser();
      final entry = parser.parseJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expectRoundTrips(entry);
    });

    test('reconstructs a fully-populated entry', () {
      final entry = SatcatEntry(
        noradId: 25544,
        objectId: '1998-067A',
        name: 'ISS (ZARYA)',
        ownerCode: 'ISS',
        objectType: SatcatObjectType.payload,
        opsStatusCode: '+',
        launchDate: DateTime.utc(1998, 11, 20),
        launchSite: 'TYMSC',
        decayDate: DateTime.utc(2031, 1, 1),
        periodMinutes: 92.9,
        inclination: 51.64,
        apogeeKm: 421,
        perigeeKm: 416,
        rcs: 401.39,
      );
      expectRoundTrips(entry);
    });

    test('reconstructs an all-nulls / empty entry', () {
      const entry = SatcatEntry(
        noradId: 99999,
        name: '',
        ownerCode: '',
        objectType: SatcatObjectType.unknown,
      );
      expectRoundTrips(entry);
    });

    test('reconstructs a decayed (re-entered) entry', () {
      final entry = SatcatEntry(
        noradId: 877,
        objectId: '1964-002A',
        name: 'OLD SAT',
        ownerCode: 'US',
        objectType: SatcatObjectType.rocketBody,
        launchDate: DateTime.utc(1964, 1, 11),
        decayDate: DateTime.utc(1964, 6, 4),
      );
      expectRoundTrips(entry);
    });

    test('reconstructs an on-orbit entry (null decay date)', () {
      final entry = SatcatEntry(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        ownerCode: 'ISS',
        objectType: SatcatObjectType.payload,
        launchDate: DateTime.utc(1998, 11, 20),
      );
      expect(entry.decayDate, isNull);
      expectRoundTrips(entry);
    });

    test('reconstructs an entry of each SatcatObjectType', () {
      for (final type in SatcatObjectType.values) {
        final entry = SatcatEntry(
          noradId: 1000 + type.index,
          objectId: '2020-001${type.index}',
          name: 'OBJ ${type.name}',
          ownerCode: 'US',
          objectType: type,
          launchDate: DateTime.utc(2020),
        );
        expectRoundTrips(entry);
      }
    });
  });
}
