import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:test/test.dart';

void main() {
  group('CacheStore.validateKey', () {
    test('valid alphanumeric key passes without throwing', () {
      expect(
        () => CacheStore.validateKey('norad:25544~fmt:omm~src:celestrak'),
        returnsNormally,
      );
    });

    test('key with all allowed separators passes', () {
      expect(
        () => CacheStore.validateKey('a-b_c:d~e'),
        returnsNormally,
      );
    });

    test('key with path traversal slash throws ArgumentError', () {
      expect(
        () => CacheStore.validateKey('../evil'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'key',
          ),
        ),
      );
    });

    test('key with backslash throws ArgumentError', () {
      expect(
        () => CacheStore.validateKey(r'path\key'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('key with space throws ArgumentError', () {
      expect(
        () => CacheStore.validateKey('key with space'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty key throws ArgumentError', () {
      expect(
        () => CacheStore.validateKey(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('key with pipe character throws ArgumentError', () {
      expect(
        () => CacheStore.validateKey('a|b'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
