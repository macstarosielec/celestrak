import 'package:celestrak/src/domain/staleness.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  final baseTime = DateTime.utc(2026, 6, 1, 12);

  group('defaultStaleThreshold', () {
    test('is 3 days', () {
      expect(defaultStaleThreshold, equals(const Duration(days: 3)));
    });
  });

  group('StalenessChecker - ageOf', () {
    test('returns positive duration for past epoch', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final epoch = baseTime.subtract(const Duration(hours: 2));

      final result = checker.ageOf(epoch);
      expect(result, equals(const Duration(hours: 2)));
    });

    test('returns zero for epoch equal to now', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);

      expect(checker.ageOf(baseTime), equals(Duration.zero));
    });

    test('returns negative duration for future epoch (propagated ahead)', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final futureEpoch = baseTime.add(const Duration(hours: 1));

      final result = checker.ageOf(futureEpoch);
      expect(result, equals(const Duration(hours: -1)));
    });

    test('normalises non-UTC epoch to UTC for comparison', () {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 12));
      final checker = StalenessChecker(clock: clock);
      // Build a DateTime in local time that represents the same instant as
      // 2026-06-01T10:00Z so that toUtc() always normalises to 10:00 UTC.
      final localEpoch = DateTime.fromMillisecondsSinceEpoch(
        DateTime.utc(2026, 6, 1, 10).millisecondsSinceEpoch,
      );

      final result = checker.ageOf(localEpoch);
      expect(result, equals(const Duration(hours: 2)));
    });

    test('advances with fake clock', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final epoch = baseTime;

      clock.advance(const Duration(hours: 5));
      expect(checker.ageOf(epoch), equals(const Duration(hours: 5)));
    });
  });

  group('StalenessChecker - isStale', () {
    test('returns false when age is less than staleThreshold', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final epoch = baseTime.subtract(const Duration(days: 2));

      expect(checker.isStale(epoch), isFalse);
    });

    test('returns false when age equals staleThreshold exactly', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final epoch = baseTime.subtract(const Duration(days: 3));

      // age == threshold → NOT stale (boundary is exclusive)
      expect(checker.isStale(epoch), isFalse);
    });

    test('returns true when age exceeds staleThreshold', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final epoch = baseTime.subtract(const Duration(days: 3, seconds: 1));

      expect(checker.isStale(epoch), isTrue);
    });

    test('respects custom staleThreshold', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(
        clock: clock,
        staleThreshold: const Duration(hours: 6),
      );
      final epoch = baseTime.subtract(const Duration(hours: 7));

      expect(checker.isStale(epoch), isTrue);
    });

    test('custom threshold: fresh when age is below it', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(
        clock: clock,
        staleThreshold: const Duration(hours: 6),
      );
      final epoch = baseTime.subtract(const Duration(hours: 5));

      expect(checker.isStale(epoch), isFalse);
    });

    test('future epoch (negative age) is never stale', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      final futureEpoch = baseTime.add(const Duration(hours: 1));

      expect(checker.isStale(futureEpoch), isFalse);
    });
  });

  group('StalenessChecker - staleThreshold getter', () {
    test('returns default threshold when not overridden', () {
      const checker = StalenessChecker();
      expect(checker.staleThreshold, equals(const Duration(days: 3)));
    });

    test('returns custom threshold when provided', () {
      const custom = Duration(hours: 12);
      final checker = StalenessChecker(staleThreshold: custom);
      expect(checker.staleThreshold, equals(custom));
    });
  });

  group('StalenessChecker - isFresh', () {
    test('returns false for null cacheAge (cache miss)', () {
      final checker = StalenessChecker();
      expect(
        checker.isFresh(null, ttl: const Duration(hours: 2)),
        isFalse,
      );
    });

    test('returns true when cacheAge is below ttl', () {
      final checker = StalenessChecker();
      expect(
        checker.isFresh(
          const Duration(minutes: 30),
          ttl: const Duration(hours: 1),
        ),
        isTrue,
      );
    });

    test('returns false when cacheAge equals ttl (boundary exclusive)', () {
      final checker = StalenessChecker();
      expect(
        checker.isFresh(
          const Duration(hours: 1),
          ttl: const Duration(hours: 1),
        ),
        isFalse,
      );
    });

    test('returns false when cacheAge exceeds ttl', () {
      final checker = StalenessChecker();
      expect(
        checker.isFresh(
          const Duration(hours: 2),
          ttl: const Duration(hours: 1),
        ),
        isFalse,
      );
    });

    test('returns true for Duration.zero age with positive ttl', () {
      final checker = StalenessChecker();
      expect(
        checker.isFresh(Duration.zero, ttl: const Duration(seconds: 1)),
        isTrue,
      );
    });
  });

  group('StalenessChecker - TTL boundary deterministic with fake clock', () {
    test('entry transitions from fresh to stale exactly at TTL', () {
      final clock = FakeClock(baseTime);
      final checker = StalenessChecker(clock: clock);
      const ttl = Duration(hours: 2);
      final writeTime = baseTime;

      // Fresh at t=0
      expect(
        checker.isFresh(clock.now.difference(writeTime), ttl: ttl),
        isTrue,
      );

      // Still fresh just before TTL
      clock.advance(const Duration(hours: 1, minutes: 59, seconds: 59));
      expect(
        checker.isFresh(clock.now.difference(writeTime), ttl: ttl),
        isTrue,
      );

      // Exactly at TTL — not fresh
      clock.advance(const Duration(seconds: 1));
      expect(
        checker.isFresh(clock.now.difference(writeTime), ttl: ttl),
        isFalse,
      );
    });
  });
}
