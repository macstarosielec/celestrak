/// Unit tests for [SpaceTrackQuery] — no network, no integration tag.
library;

import 'package:celestrak/celestrak.dart';
import 'package:test/test.dart';

void main() {
  group('SpaceTrackQuery.byNoradId', () {
    test('throws ArgumentError for noradId < 1', () {
      expect(
        () => SpaceTrackQuery.byNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SpaceTrackQuery.byNoradId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('equality is value-based', () {
      final q1 = SpaceTrackQuery.byNoradId(25544);
      final q2 = SpaceTrackQuery.byNoradId(25544);
      final q3 = SpaceTrackQuery.byNoradId(20580);

      expect(q1, equals(q2));
      expect(q1, isNot(equals(q3)));
      expect(q1.hashCode, equals(q2.hashCode));
    });
  });
}
