import 'package:celestrak/src/domain/clock.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Clock - interface contract', () {
    test('FakeClock implements Clock', () {
      final Clock clock = FakeClock(DateTime.utc(2026, 1, 1));
      expect(clock, isA<Clock>());
    });

    test('SystemClock implements Clock', () {
      const Clock clock = SystemClock();
      expect(clock, isA<Clock>());
    });
  });

  group('SystemClock', () {
    test('now returns a UTC DateTime', () {
      const clock = SystemClock();
      expect(clock.now.isUtc, isTrue);
    });

    test('now is close to current wall-clock time', () {
      const clock = SystemClock();
      final before = DateTime.now().toUtc();
      final clockNow = clock.now;
      final after = DateTime.now().toUtc();

      expect(
        clockNow.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        clockNow.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('successive calls return non-decreasing times', () {
      const clock = SystemClock();
      final t1 = clock.now;
      final t2 = clock.now;
      expect(t2.isAfter(t1) || t2 == t1, isTrue);
    });
  });

  group('FakeClock - Clock contract', () {
    test('starts at the given initial time', () {
      final clock = FakeClock(DateTime.utc(2026, 6, 1));
      expect(clock.now, equals(DateTime.utc(2026, 6, 1)));
    });

    test('advance moves now forward', () {
      final clock = FakeClock(DateTime.utc(2026, 1, 1))
        ..advance(const Duration(hours: 2));
      expect(clock.now, equals(DateTime.utc(2026, 1, 1, 2)));
    });

    test('multiple advances accumulate', () {
      final clock = FakeClock(DateTime.utc(2026, 1, 1))
        ..advance(const Duration(hours: 1))
        ..advance(const Duration(minutes: 30));
      expect(clock.now, equals(DateTime.utc(2026, 1, 1, 1, 30)));
    });
  });
}
