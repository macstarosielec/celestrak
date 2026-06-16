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

    test('FRIT (joint France/Italy, all-EU-member) is EU-sovereign', () {
      final owner = satcatOwnerForCode('FRIT');
      expect(owner.isEuSovereign, isTrue);
      expect(owner.region, 'Europe');
      expect(owner.name, 'France/Italy');
    });

    test('ESRO (ESA predecessor) is EU-sovereign', () {
      expect(satcatOwnerForCode('ESRO').isEuSovereign, isTrue);
    });

    // Ground-truth list: every EU-27 member state that has a CelesTrak owner
    // code. Cyprus, Latvia, Malta, and Slovakia have no code on the
    // authoritative list and so are absent. The European multinational
    // organisations (ESA, ESRO, EUME, EUTE, FGER, FRIT) are asserted above.
    const euMemberCodes = <String, String>{
      'ASRA': 'Austria',
      'BEL': 'Belgium',
      'BUL': 'Bulgaria',
      'HRV': 'Croatia',
      'CZCH': 'Czechia',
      'DEN': 'Denmark',
      'EST': 'Estonia',
      'FIN': 'Finland',
      'FR': 'France',
      'GER': 'Germany',
      'GREC': 'Greece',
      'HUN': 'Hungary',
      'IRL': 'Ireland',
      'IT': 'Italy',
      'LTU': 'Lithuania',
      'LUXE': 'Luxembourg',
      'NETH': 'Netherlands',
      'POL': 'Poland',
      'POR': 'Portugal',
      'ROM': 'Romania',
      'SVN': 'Slovenia',
      'SPN': 'Spain',
      'SWED': 'Sweden',
    };

    test('every EU member-state code is EU-sovereign and in Europe', () {
      euMemberCodes.forEach((code, expectedName) {
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
      // The only EU-sovereign owners are the member states plus the six
      // European multinational organisations; nothing else may carry the flag.
      const euOrgCodes = <String>{
        'ESA',
        'ESRO',
        'EUME',
        'EUTE',
        'FGER',
        'FRIT',
      };
      final expectedEuCodes = <String>{
        ...euMemberCodes.keys,
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

    test('carries the full reconciled CelesTrak source list', () {
      // The authoritative celestrak.org/satcat/sources.php list has 132 codes;
      // we map all but the TBD/UNK administrative sentinels (= 130). Guards
      // against an accidental bulk drop on a future edit.
      expect(kSatcatOwnerCodes, hasLength(130));
      expect(kSatcatOwnerCodes.containsKey('TBD'), isFalse);
      expect(kSatcatOwnerCodes.containsKey('UNK'), isFalse);
    });
  });

  group('CEL-150 reconciliation regressions (corrected owner codes)', () {
    // The pre-reconciliation knowledge-built table swapped Austria/Australia
    // and invented non-CelesTrak codes (AUST, RSA, TWN). Lock the fixes in.
    test('AUS is Australia in Oceania, not EU-sovereign', () {
      final owner = satcatOwnerForCode('AUS');
      expect(owner.name, 'Australia');
      expect(owner.region, 'Oceania');
      expect(owner.isEuSovereign, isFalse);
    });

    test('Austria is ASRA in Europe, EU-sovereign', () {
      final owner = satcatOwnerForCode('ASRA');
      expect(owner.name, 'Austria');
      expect(owner.region, 'Europe');
      expect(owner.isEuSovereign, isTrue);
    });

    test('South Africa is SAFR, Taiwan is ROC', () {
      expect(satcatOwnerForCode('SAFR').name, 'South Africa');
      expect(satcatOwnerForCode('SAFR').region, 'Africa');
      expect(satcatOwnerForCode('ROC').name, 'Taiwan');
      expect(satcatOwnerForCode('ROC').region, 'Asia');
    });

    test('invented non-CelesTrak codes are gone (now passthrough)', () {
      for (final bogus in <String>['AUST', 'RSA', 'TWN']) {
        final owner = satcatOwnerForCode(bogus);
        expect(owner.name, bogus, reason: '$bogus must not be a mapped owner');
        expect(owner.region, isNull, reason: '$bogus must be passthrough');
      }
    });
  });
}
