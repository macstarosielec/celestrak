import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> loadFixture(String name) {
    final content = File('test/fixtures/satcat/$name').readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  SatcatEntry buildEntry() => const SatcatEntry(
        noradId: 25544,
        objectId: '1998-067A',
        name: 'ISS (ZARYA)',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
        launchSite: 'TYMSC',
        periodMinutes: 92.9,
        inclination: 51.64,
        apogeeKm: 421,
        perigeeKm: 416,
        rcs: 401.39,
        opsStatusCode: '+',
      );

  group('SatcatObjectType.fromCode', () {
    // CelesTrak SATCAT OBJECT_TYPE values are short codes, not full words.
    test('PAY -> payload', () {
      expect(SatcatObjectType.fromCode('PAY'), SatcatObjectType.payload);
    });

    test('R/B -> rocketBody', () {
      expect(SatcatObjectType.fromCode('R/B'), SatcatObjectType.rocketBody);
    });

    test('DEB -> debris', () {
      expect(SatcatObjectType.fromCode('DEB'), SatcatObjectType.debris);
    });

    test('UNK -> unknown', () {
      expect(SatcatObjectType.fromCode('UNK'), SatcatObjectType.unknown);
    });

    test('full-word forms accepted as tolerant aliases', () {
      expect(SatcatObjectType.fromCode('PAYLOAD'), SatcatObjectType.payload);
      expect(
        SatcatObjectType.fromCode('ROCKET BODY'),
        SatcatObjectType.rocketBody,
      );
      expect(SatcatObjectType.fromCode('DEBRIS'), SatcatObjectType.debris);
    });

    test('unrecognised value -> unknown', () {
      expect(SatcatObjectType.fromCode('TBA'), SatcatObjectType.unknown);
    });

    test('null -> unknown', () {
      expect(SatcatObjectType.fromCode(null), SatcatObjectType.unknown);
    });

    test('empty string -> unknown', () {
      expect(SatcatObjectType.fromCode(''), SatcatObjectType.unknown);
    });

    test('case-insensitive and whitespace-tolerant', () {
      expect(SatcatObjectType.fromCode('  pay '), SatcatObjectType.payload);
      expect(SatcatObjectType.fromCode('r/b'), SatcatObjectType.rocketBody);
    });
  });

  group('SatcatEntry.fromCelestrakJson - ISS', () {
    late SatcatEntry iss;

    setUp(() {
      iss = SatcatEntry.fromCelestrakJson(loadFixture('iss_25544_satcat.json'));
    });

    test('parses core identity fields', () {
      expect(iss.noradId, 25544);
      expect(iss.objectId, '1998-067A');
      expect(iss.name, 'ISS (ZARYA)');
      expect(iss.ownerCode, 'ISS');
    });

    test('is a payload', () {
      expect(iss.isPayload, isTrue);
      expect(iss.objectType, SatcatObjectType.payload);
    });

    test('is on-orbit (null decayDate)', () {
      expect(iss.decayDate, isNull);
      expect(iss.isOnOrbit, isTrue);
    });

    test('parses launch date as UTC', () {
      expect(iss.launchDate, DateTime.utc(1998, 11, 20));
      expect(iss.launchDate!.isUtc, isTrue);
    });

    test('parses numeric fields', () {
      expect(iss.periodMinutes, 92.9);
      expect(iss.inclination, 51.64);
      expect(iss.apogeeKm, 421);
      expect(iss.perigeeKm, 416);
      expect(iss.rcs, 401.39);
    });

    test('parses ops status and launch site', () {
      expect(iss.opsStatusCode, '+');
      expect(iss.launchSite, 'TYMSC');
    });
  });

  group('SatcatEntry.fromCelestrakJson - variants', () {
    test('6-digit NORAD id parses; N/A RCS -> null', () {
      final e =
          SatcatEntry.fromCelestrakJson(loadFixture('satcat_6digit.json'));
      expect(e.noradId, 270544);
      expect(e.rcs, isNull);
      expect(e.isPayload, isTrue);
    });

    test('null/absent fields -> null, empty name -> ""', () {
      final e =
          SatcatEntry.fromCelestrakJson(loadFixture('satcat_null_fields.json'));
      expect(e.name, '');
      expect(e.launchDate, isNull);
      expect(e.decayDate, isNull);
      expect(e.launchSite, isNull);
      expect(e.rcs, isNull);
      expect(e.periodMinutes, isNull);
      expect(e.inclination, isNull);
      expect(e.apogeeKm, isNull);
      expect(e.perigeeKm, isNull);
      expect(e.opsStatusCode, isNull);
      expect(e.objectType, SatcatObjectType.debris);
      expect(e.isOnOrbit, isTrue);
      expect(e.ownerCode, 'CIS');
    });

    test('decayed object -> isOnOrbit == false', () {
      final e =
          SatcatEntry.fromCelestrakJson(loadFixture('satcat_decayed.json'));
      expect(e.decayDate, DateTime.utc(1958, 6, 26));
      expect(e.isOnOrbit, isFalse);
      expect(e.objectType, SatcatObjectType.rocketBody);
      expect(e.isPayload, isFalse);
    });
  });

  group('SatcatEntry.fromCelestrakJson - field parsing', () {
    test('accepts numeric strings for numeric fields', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': '25544',
        'PERIOD': '92.9',
        'INCLINATION': '51.64',
        'APOGEE': '421',
        'PERIGEE': '416',
        'RCS': '1.5',
      });
      expect(e.noradId, 25544);
      expect(e.periodMinutes, 92.9);
      expect(e.apogeeKm, 421);
      expect(e.rcs, 1.5);
    });

    test('unparseable numeric string -> null', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': 1,
        'PERIOD': 'not-a-number',
      });
      expect(e.periodMinutes, isNull);
    });

    test('explicit JSON null and N/A string for numeric -> null', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': 1,
        'PERIOD': null,
        'RCS': 'N/A',
      });
      expect(e.periodMinutes, isNull);
      expect(e.rcs, isNull);
    });

    test('object type mapping for PAY via JSON', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': 1,
        'OBJECT_TYPE': 'PAY',
      });
      expect(e.objectType, SatcatObjectType.payload);
    });

    test('unrecognised OBJECT_TYPE -> unknown', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': 1,
        'OBJECT_TYPE': 'MYSTERY',
      });
      expect(e.objectType, SatcatObjectType.unknown);
    });

    test('absent OBJECT_TYPE -> unknown; absent OWNER/NAME -> ""', () {
      final e = SatcatEntry.fromCelestrakJson(const <String, dynamic>{
        'NORAD_CAT_ID': 1,
      });
      expect(e.objectType, SatcatObjectType.unknown);
      expect(e.ownerCode, '');
      expect(e.name, '');
      expect(e.objectId, isNull);
    });
  });

  group('SatcatEntry.fromCelestrakJson - required NORAD_CAT_ID', () {
    test('missing NORAD_CAT_ID throws FormatException', () {
      expect(
        () => SatcatEntry.fromCelestrakJson(const <String, dynamic>{
          'OBJECT_NAME': 'X',
        }),
        throwsFormatException,
      );
    });

    test('non-integer NORAD_CAT_ID throws FormatException', () {
      expect(
        () => SatcatEntry.fromCelestrakJson(const <String, dynamic>{
          'NORAD_CAT_ID': 'abc',
        }),
        throwsFormatException,
      );
    });
  });

  group('SatcatEntry value equality', () {
    test('same field values are equal', () {
      expect(buildEntry(), equals(buildEntry()));
    });

    test('hashCode consistent with equality', () {
      expect(buildEntry().hashCode, equals(buildEntry().hashCode));
    });

    test('identical instance equals itself', () {
      final e = buildEntry();
      expect(e, equals(e));
    });

    test('different noradId -> not equal', () {
      expect(buildEntry(), isNot(equals(buildEntry().copyWith(noradId: 1))));
    });

    test('different objectType -> not equal', () {
      expect(
        buildEntry(),
        isNot(
          equals(buildEntry().copyWith(objectType: SatcatObjectType.debris)),
        ),
      );
    });

    test('different decayDate -> not equal', () {
      expect(
        buildEntry(),
        isNot(equals(buildEntry().copyWith(decayDate: DateTime.utc(2020)))),
      );
    });
  });

  group('SatcatEntry.copyWith', () {
    test('no args returns equal copy', () {
      final base = buildEntry();
      expect(base.copyWith(), equals(base));
    });

    test('replaces a single field', () {
      final updated = buildEntry().copyWith(name: 'RENAMED');
      expect(updated.name, 'RENAMED');
      expect(updated.noradId, buildEntry().noradId);
    });

    test('can set a nullable field', () {
      final decayed = buildEntry().copyWith(decayDate: DateTime.utc(2020, 5));
      expect(decayed.decayDate, DateTime.utc(2020, 5));
      expect(decayed.isOnOrbit, isFalse);
    });

    test('can clear a nullable field to null', () {
      final withSite = buildEntry();
      final cleared = withSite.copyWith(launchSite: null);
      expect(cleared.launchSite, isNull);
      expect(cleared.noradId, withSite.noradId);
    });

    test('omitting a nullable arg keeps current value', () {
      final updated = buildEntry().copyWith(noradId: 99);
      expect(updated.launchSite, 'TYMSC');
      expect(updated.rcs, 401.39);
    });

    test('copyWith does not mutate the original', () {
      final base = buildEntry();
      final copy = base.copyWith(noradId: 1);
      expect(copy.noradId, 1);
      expect(base.noradId, 25544);
    });
  });

  group('SatcatEntry.toString', () {
    test('contains noradId and name', () {
      final s = buildEntry().toString();
      expect(s, contains('25544'));
      expect(s, contains('ISS (ZARYA)'));
    });
  });
}
