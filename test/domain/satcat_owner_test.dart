import 'package:celestrak/src/data/static/satcat_owner_codes.dart';
import 'package:celestrak/src/domain/satcat_owner.dart';
import 'package:test/test.dart';

void main() {
  group('SatcatOwner value semantics', () {
    test('value equality and hashCode', () {
      const a = SatcatOwner(
        code: 'FR',
        name: 'France',
        region: 'Europe',
        isEuSovereign: true,
      );
      const b = SatcatOwner(
        code: 'FR',
        name: 'France',
        region: 'Europe',
        isEuSovereign: true,
      );
      const c = SatcatOwner(code: 'US', name: 'United States');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(identical(a, a), isTrue);
    });

    test('equality discriminates each field individually', () {
      const base = SatcatOwner(
        code: 'FR',
        name: 'France',
        region: 'Europe',
        isEuSovereign: true,
      );
      // Same code, differing name -> exercises the name comparison branch.
      const diffName = SatcatOwner(
        code: 'FR',
        name: 'Francia',
        region: 'Europe',
        isEuSovereign: true,
      );
      // Same code and name, differing region.
      const diffRegion = SatcatOwner(
        code: 'FR',
        name: 'France',
        region: 'Multinational',
        isEuSovereign: true,
      );
      // Same code, name, region, differing EU flag.
      const diffEu = SatcatOwner(
        code: 'FR',
        name: 'France',
        region: 'Europe',
      );
      expect(base, isNot(equals(diffName)));
      expect(base, isNot(equals(diffRegion)));
      expect(base, isNot(equals(diffEu)));
    });

    test('equality returns false against a non-SatcatOwner', () {
      const owner = SatcatOwner(code: 'US', name: 'United States');
      expect(owner == Object(), isFalse);
    });

    test('isEuSovereign defaults to false; region defaults to null', () {
      const owner = SatcatOwner(code: 'XX', name: 'XX');
      expect(owner.region, isNull);
      expect(owner.isEuSovereign, isFalse);
    });

    test('toString includes the key fields', () {
      const owner = SatcatOwner(
        code: 'ESA',
        name: 'European Space Agency',
        region: 'Europe',
        isEuSovereign: true,
      );
      expect(owner.toString(), contains('ESA'));
      expect(owner.toString(), contains('European Space Agency'));
      expect(owner.toString(), contains('isEuSovereign: true'));
    });
  });

  group('satcatOwnerForCode - known codes', () {
    test('US resolves to United States, not EU-sovereign', () {
      final owner = satcatOwnerForCode('US');
      expect(owner.code, 'US');
      expect(owner.name, 'United States');
      expect(owner.region, 'North America');
      expect(owner.isEuSovereign, isFalse);
    });

    test('PRC resolves to China, not EU-sovereign', () {
      final owner = satcatOwnerForCode('PRC');
      expect(owner.name, 'China');
      expect(owner.region, 'Asia');
      expect(owner.isEuSovereign, isFalse);
    });

    test('CIS resolves to the Commonwealth of Independent States', () {
      final owner = satcatOwnerForCode('CIS');
      expect(owner.name, contains('Commonwealth of Independent States'));
      expect(owner.isEuSovereign, isFalse);
    });

    test('input is trimmed and upper-cased before lookup', () {
      final owner = satcatOwnerForCode('  fr  ');
      expect(owner.code, 'FR');
      expect(owner.name, 'France');
      expect(owner.isEuSovereign, isTrue);
    });
  });

  group('satcatOwnerForCode - EU-sovereign set', () {
    test('France (FR) is EU-sovereign', () {
      expect(satcatOwnerForCode('FR').isEuSovereign, isTrue);
    });

    test('ESA is EU-sovereign', () {
      expect(satcatOwnerForCode('ESA').isEuSovereign, isTrue);
    });

    test('EUMETSAT (EUME) and EUTELSAT (EUTE) are EU-sovereign', () {
      expect(satcatOwnerForCode('EUME').isEuSovereign, isTrue);
      expect(satcatOwnerForCode('EUTE').isEuSovereign, isTrue);
    });

    test('FGER (joint France/Germany, all-EU-member) is EU-sovereign', () {
      final owner = satcatOwnerForCode('FGER');
      expect(owner.isEuSovereign, isTrue);
      expect(owner.region, 'Europe');
      expect(owner.name, 'France/Germany');
    });

    // Ground-truth list: the EU-sovereign codes the conservative table ships.
    // This is the kept EU-27 member-state subset (the speculative single-
    // country long tail was dropped in the conservative trim); the European
    // multinational organisations (ESA, EUME, EUTE, FGER) are asserted above.
    const keptEuMemberCodes = <String, String>{
      'AUS': 'Austria',
      'BEL': 'Belgium',
      'CZCH': 'Czechia',
      'DEN': 'Denmark',
      'FIN': 'Finland',
      'FR': 'France',
      'GER': 'Germany',
      'GREC': 'Greece',
      'HUN': 'Hungary',
      'IT': 'Italy',
      'LUXE': 'Luxembourg',
      'NETH': 'Netherlands',
      'POL': 'Poland',
      'POR': 'Portugal',
      'SPN': 'Spain',
      'SWED': 'Sweden',
    };

    test('every kept EU member-state code is EU-sovereign and in Europe', () {
      keptEuMemberCodes.forEach((code, expectedName) {
        final owner = satcatOwnerForCode(code);
        expect(
          owner.isEuSovereign,
          isTrue,
          reason: '$code (${owner.name}) should be EU-sovereign',
        );
        expect(owner.region, 'Europe', reason: '$code should be in Europe');
        expect(owner.name, expectedName, reason: '$code name');
      });
    });

    test('every EU-sovereign code in the table is an expected EU owner', () {
      // The only EU-sovereign owners are the kept member states plus the four
      // European multinational organisations; nothing else may carry the flag.
      const euOrgCodes = <String>{'ESA', 'EUME', 'EUTE', 'FGER'};
      final expectedEuCodes = <String>{
        ...keptEuMemberCodes.keys,
        ...euOrgCodes,
      };
      final actualEuCodes = <String>{
        for (final entry in kSatcatOwnerCodes.entries)
          if (entry.value.isEuSovereign) entry.key,
      };
      expect(actualEuCodes, equals(expectedEuCodes));
    });

    test('non-EU European nations are NOT EU-sovereign', () {
      for (final code in <String>['UK', 'NOR', 'SWTZ', 'CIS']) {
        expect(
          satcatOwnerForCode(code).isEuSovereign,
          isFalse,
          reason: '$code is European-region but not an EU member',
        );
      }
    });

    test('major non-EU powers are NOT EU-sovereign', () {
      for (final code in <String>['US', 'PRC', 'JPN', 'IND', 'CIS']) {
        expect(satcatOwnerForCode(code).isEuSovereign, isFalse);
      }
    });
  });

  group('satcatOwnerForCode - unknown / empty passthrough', () {
    test('unknown code passes through, never throws', () {
      final owner = satcatOwnerForCode('ZZZ');
      expect(owner.code, 'ZZZ');
      expect(owner.name, 'ZZZ');
      expect(owner.region, isNull);
      expect(owner.isEuSovereign, isFalse);
    });

    test('unknown code is normalised before passthrough', () {
      final owner = satcatOwnerForCode('  zzz ');
      expect(owner.code, 'ZZZ');
      expect(owner.name, 'ZZZ');
    });

    test('empty string passes through to an empty owner, never throws', () {
      final owner = satcatOwnerForCode('');
      expect(owner.code, '');
      expect(owner.name, '');
      expect(owner.region, isNull);
      expect(owner.isEuSovereign, isFalse);
    });

    test('whitespace-only string passes through to an empty owner', () {
      final owner = satcatOwnerForCode('   ');
      expect(owner.code, '');
      expect(owner.name, '');
    });
  });

  group('kSatcatOwnerCodes table is internally consistent', () {
    test('is non-empty', () {
      expect(kSatcatOwnerCodes, isNotEmpty);
    });

    test('every entry key equals its owner code and is normalised', () {
      kSatcatOwnerCodes.forEach((key, owner) {
        expect(owner.code, key, reason: 'code must equal map key');
        expect(key, key.trim(), reason: '$key must be trimmed');
        expect(key, key.toUpperCase(), reason: '$key must be upper-case');
        expect(key, isNotEmpty, reason: 'no empty keys');
      });
    });

    test('every entry has a non-empty human-readable name', () {
      kSatcatOwnerCodes.forEach((key, owner) {
        expect(owner.name, isNotEmpty, reason: '$key must have a name');
      });
    });

    test('every entry has a non-null, non-empty region', () {
      kSatcatOwnerCodes.forEach((key, owner) {
        expect(owner.region, isNotNull, reason: '$key must have a region');
        expect(owner.region, isNotEmpty, reason: '$key region non-empty');
      });
    });

    test('every EU-sovereign entry is in the Europe region', () {
      kSatcatOwnerCodes.forEach((key, owner) {
        if (owner.isEuSovereign) {
          expect(
            owner.region,
            'Europe',
            reason: '$key is EU-sovereign so must be region Europe',
          );
        }
      });
    });

    test('region values are drawn from the known set', () {
      const known = <String>{
        'Africa',
        'Asia',
        'Europe',
        'North America',
        'South America',
        'Oceania',
        'Multinational',
      };
      kSatcatOwnerCodes.forEach((key, owner) {
        expect(known, contains(owner.region), reason: '$key region known');
      });
    });

    test('every shipped code resolves via satcatOwnerForCode', () {
      kSatcatOwnerCodes.forEach((key, owner) {
        expect(satcatOwnerForCode(key), equals(owner));
      });
    });
  });
}
