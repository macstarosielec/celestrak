// FR-20: Validate every SatelliteCategory.group string against a fixture.
//
// Each [SatelliteCategory] must have a corresponding fixture file named
// `test/fixtures/group_<group>.tle`.  The tests are entirely offline —
// no network is touched.
import 'dart:io' show File;

import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:test/test.dart';

import '../support/fixture_loader.dart';

void main() {
  const parser = TleParser();

  group('SatelliteCategory.group — fixture coverage (FR-20)', () {
    for (final category in SatelliteCategory.values) {
      final groupString = category.group;
      final fixtureRelPath = 'test/fixtures/group_$groupString.tle';

      group('${category.name} (group="$groupString")', () {
        test('fixture file exists', () {
          final path = fixturePath(fixtureRelPath);
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Missing fixture for group "$groupString" — '
                'create $path',
          );
        });

        test('fixture file is non-empty', () {
          final path = fixturePath(fixtureRelPath);
          final content = File(path).readAsStringSync();
          expect(
            content.trim(),
            isNotEmpty,
            reason: 'Fixture for group "$groupString" must not be empty',
          );
        });

        test('fixture parses to at least one record', () {
          final path = fixturePath(fixtureRelPath);
          final content = File(path).readAsStringSync();
          final records = parser.parseAll(content);
          expect(
            records,
            isNotEmpty,
            reason: 'Fixture for group "$groupString" must contain '
                'at least one TLE record',
          );
        });
      });
    }
  });
}
