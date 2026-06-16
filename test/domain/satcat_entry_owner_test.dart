import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> loadFixture(String name) {
    final content = File('test/fixtures/satcat/$name').readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  group('SatcatEntry.owner getter (in-memory)', () {
    test('ownerCode US resolves to United States, not EU-sovereign', () {
      const entry = SatcatEntry(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      expect(entry.owner.name, 'United States');
      expect(entry.owner.isEuSovereign, isFalse);
      expect(entry.owner.code, 'US');
    });

    test('ownerCode ESA resolves to an EU-sovereign owner', () {
      const entry = SatcatEntry(
        noradId: 40697,
        name: 'SENTINEL-2A',
        ownerCode: 'ESA',
        objectType: SatcatObjectType.payload,
      );
      expect(entry.owner.isEuSovereign, isTrue);
      expect(entry.owner.name, contains('European Space Agency'));
    });

    test('empty ownerCode resolves to a passthrough owner, never throws', () {
      const entry = SatcatEntry(
        noradId: 1,
        name: 'NO OWNER',
        ownerCode: '',
        objectType: SatcatObjectType.unknown,
      );
      expect(entry.owner.code, '');
      expect(entry.owner.name, '');
      expect(entry.owner.region, isNull);
      expect(entry.owner.isEuSovereign, isFalse);
    });
  });

  group('SatcatEntry.owner getter (parsed from fixtures)', () {
    test('iss_25544_satcat.json -> owner International Space Station', () {
      final entry =
          SatcatEntry.fromCelestrakJson(loadFixture('iss_25544_satcat.json'));
      expect(entry.ownerCode, 'ISS');
      expect(entry.owner.name, 'International Space Station');
      expect(entry.owner.isEuSovereign, isFalse);
    });

    test('satcat_eu_owner.json -> ESA owner is EU-sovereign', () {
      final entry =
          SatcatEntry.fromCelestrakJson(loadFixture('satcat_eu_owner.json'));
      expect(entry.ownerCode, 'ESA');
      expect(entry.owner.isEuSovereign, isTrue);
      expect(entry.owner.region, 'Europe');
    });

    test('satcat_unknown_owner.json -> unmapped code passes through', () {
      final entry = SatcatEntry.fromCelestrakJson(
        loadFixture('satcat_unknown_owner.json'),
      );
      expect(entry.ownerCode, 'ZZZ');
      expect(entry.owner.name, 'ZZZ');
      expect(entry.owner.region, isNull);
      expect(entry.owner.isEuSovereign, isFalse);
    });
  });
}
