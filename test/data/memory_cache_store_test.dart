import 'dart:typed_data';

import 'package:celestrak/src/data/local/memory_cache_store.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  late MemoryCacheStore store;
  late FakeClock clock;

  setUp(() {
    store = MemoryCacheStore();
    clock = FakeClock(DateTime.utc(2026, 1, 1));
  });

  group('MemoryCacheStore - round-trip', () {
    test('write then read returns the same bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await store.write('key1', bytes, clock.now);

      final result = await store.read('key1');
      expect(result, equals(bytes));
    });

    test('read on missing key returns null', () async {
      final result = await store.read('missing');
      expect(result, isNull);
    });
  });

  group('MemoryCacheStore - age', () {
    test('age returns Duration via fake clock', () async {
      await store.write('key1', Uint8List.fromList([0]), clock.now);
      clock.advance(const Duration(minutes: 30));

      final result = await store.age('key1', clock.now);
      expect(result, equals(const Duration(minutes: 30)));
    });

    test('age returns null for missing key', () async {
      final result = await store.age('missing', clock.now);
      expect(result, isNull);
    });

    test('age is zero immediately after write', () async {
      await store.write('key1', Uint8List.fromList([0]), clock.now);
      final result = await store.age('key1', clock.now);
      expect(result, equals(Duration.zero));
    });
  });

  group('MemoryCacheStore - clear', () {
    test('clear() removes all entries', () async {
      await store.write('key1', Uint8List.fromList([1]), clock.now);
      await store.write('key2', Uint8List.fromList([2]), clock.now);

      await store.clear();

      expect(await store.read('key1'), isNull);
      expect(await store.read('key2'), isNull);
    });

    test('clear() causes age to return null', () async {
      await store.write('key1', Uint8List.fromList([0]), clock.now);
      await store.clear();

      final result = await store.age('key1', clock.now);
      expect(result, isNull);
    });

    test('clear(keyPrefix:) removes only matching keys', () async {
      await store.write('sat:25544', Uint8List.fromList([1]), clock.now);
      await store.write('sat:25545', Uint8List.fromList([2]), clock.now);
      await store.write('config:foo', Uint8List.fromList([3]), clock.now);

      await store.clear(keyPrefix: 'sat:');

      expect(await store.read('sat:25544'), isNull);
      expect(await store.read('sat:25545'), isNull);
      expect(await store.read('config:foo'), isNotNull);
    });

    test('clear(keyPrefix:) that matches nothing is a no-op', () async {
      await store.write('key1', Uint8List.fromList([1]), clock.now);
      await store.clear(keyPrefix: 'nomatch:');
      expect(await store.read('key1'), isNotNull);
    });
  });

  group('MemoryCacheStore - TTL boundary', () {
    test('age exactly equals TTL at boundary', () async {
      const ttl = Duration(hours: 1);
      await store.write('key1', Uint8List.fromList([0]), clock.now);
      clock.advance(ttl);

      final result = await store.age('key1', clock.now);
      expect(result, equals(ttl));
    });

    test('age exceeds TTL past boundary', () async {
      const ttl = Duration(hours: 1);
      await store.write('key1', Uint8List.fromList([0]), clock.now);
      clock.advance(ttl + const Duration(seconds: 1));

      final result = await store.age('key1', clock.now);
      expect(result!.compareTo(ttl), greaterThan(0));
    });
  });
}
