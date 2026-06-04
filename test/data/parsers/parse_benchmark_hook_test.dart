import 'package:celestrak/src/data/parsers/parse_benchmark_hook.dart';
import 'package:test/test.dart';

import '../../support/recording_benchmark_hook.dart';

void main() {
  group('NullParseBenchmarkHook', () {
    test('can be constructed as const', () {
      expect(const NullParseBenchmarkHook(), isA<ParseBenchmarkHook>());
    });

    test('onParseStart does not throw', () {
      expect(
        () => const NullParseBenchmarkHook().onParseStart('tle'),
        returnsNormally,
      );
    });

    test('onParseEnd does not throw', () {
      expect(
        () => const NullParseBenchmarkHook().onParseEnd(
          'omm',
          42,
          Duration.zero,
        ),
        returnsNormally,
      );
    });

    test('implements ParseBenchmarkHook', () {
      expect(
        const NullParseBenchmarkHook(),
        isA<ParseBenchmarkHook>(),
      );
    });
  });

  group('ParseBenchmarkHook contract (RecordingBenchmarkHook)', () {
    late RecordingBenchmarkHook hook;

    setUp(() => hook = RecordingBenchmarkHook());

    test('onParseStart receives the label', () {
      hook.onParseStart('tle');
      expect(hook.starts, equals(['tle']));
    });

    test('onParseEnd receives label, recordCount, and elapsed', () {
      hook.onParseEnd('omm', 3, const Duration(milliseconds: 5));
      expect(hook.ends, hasLength(1));
      expect(hook.ends.first.$1, equals('omm'));
      expect(hook.ends.first.$2, equals(3));
      expect(hook.ends.first.$3, equals(const Duration(milliseconds: 5)));
    });

    test('multiple calls accumulate independently', () {
      hook
        ..onParseStart('tle')
        ..onParseStart('omm');
      expect(hook.starts, equals(['tle', 'omm']));

      hook
        ..onParseEnd('tle', 10, const Duration(milliseconds: 1))
        ..onParseEnd('omm', 5, const Duration(milliseconds: 2));
      expect(hook.ends, hasLength(2));
    });
  });
}
