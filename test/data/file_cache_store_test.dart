import 'dart:io';
import 'dart:typed_data';

import 'package:celestrak/src/data/local/file_cache_store.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/temp_cache.dart';

void main() {
  late TempCache tmp;
  late FileCacheStore store;
  late FakeClock clock;

  setUp(() async {
    tmp = await TempCache.create();
    store = FileCacheStore(tmp.directory);
    clock = FakeClock(DateTime.utc(2026, 1, 1));
  });

  tearDown(() => tmp.tearDown());

  group('FileCacheStore - round-trip', () {
    test('write then read returns the same bytes', () async {
      final bytes = Uint8List.fromList([10, 20, 30]);
      await store.write('entry1', bytes, clock.now);

      final result = await store.read('entry1');
      expect(result, equals(bytes));
    });

    test('read on missing key returns null', () async {
      final result = await store.read('missing');
      expect(result, isNull);
    });
  });

  group('FileCacheStore - age', () {
    test('age returns Duration via fake clock', () async {
      await store.write('entry1', Uint8List.fromList([0]), clock.now);
      clock.advance(const Duration(hours: 2));

      final result = await store.age('entry1', clock.now);
      expect(result, equals(const Duration(hours: 2)));
    });

    test('age returns null for missing key', () async {
      final result = await store.age('missing', clock.now);
      expect(result, isNull);
    });

    test('age is zero immediately after write', () async {
      await store.write('entry1', Uint8List.fromList([0]), clock.now);
      final result = await store.age('entry1', clock.now);
      expect(result, equals(Duration.zero));
    });
  });

  group('FileCacheStore - clear', () {
    test('clear() removes all entries', () async {
      await store.write('a', Uint8List.fromList([1]), clock.now);
      await store.write('b', Uint8List.fromList([2]), clock.now);

      await store.clear();

      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNull);
    });

    test('clear() causes age to return null', () async {
      await store.write('entry1', Uint8List.fromList([0]), clock.now);
      await store.clear();

      final result = await store.age('entry1', clock.now);
      expect(result, isNull);
    });

    test('clear(keyPrefix:) removes only matching files', () async {
      await store.write('sat_25544', Uint8List.fromList([1]), clock.now);
      await store.write('sat_25545', Uint8List.fromList([2]), clock.now);
      await store.write('cfg_foo', Uint8List.fromList([3]), clock.now);

      await store.clear(keyPrefix: 'sat_');

      expect(await store.read('sat_25544'), isNull);
      expect(await store.read('sat_25545'), isNull);
      expect(await store.read('cfg_foo'), isNotNull);
    });

    test('clear(keyPrefix:) causes age to return null for cleared key',
        () async {
      await store.write('sat_25544', Uint8List.fromList([1]), clock.now);
      await store.write('cfg_foo', Uint8List.fromList([2]), clock.now);

      await store.clear(keyPrefix: 'sat_');

      // Both .bin and .ts must be removed so age() returns null
      // (no orphan .ts).
      expect(await store.age('sat_25544', clock.now), isNull);
      // Non-matching key must remain untouched.
      expect(await store.age('cfg_foo', clock.now), isNotNull);
    });

    test('clear() on empty directory is a no-op', () async {
      await expectLater(store.clear(), completes);
    });

    test('clear(keyPrefix:) that matches nothing is a no-op', () async {
      await store.write('entry1', Uint8List.fromList([1]), clock.now);
      await store.clear(keyPrefix: 'nomatch_');
      expect(await store.read('entry1'), isNotNull);
    });
  });

  group('FileCacheStore - resilience', () {
    test('truncated .bin file is treated as a miss, not a crash', () async {
      // Write a valid entry first.
      await store.write('entry1', Uint8List.fromList([1, 2, 3]), clock.now);

      // Truncate the payload file to simulate corruption (FR-15/NFR-9).
      final binFile = File(
        '${tmp.directory.path}${Platform.pathSeparator}entry1.bin',
      );
      await binFile.writeAsBytes([]);

      final result = await store.read('entry1');
      expect(result, isNull);
    });

    test('missing .ts file causes age to return null', () async {
      await store.write('entry1', Uint8List.fromList([1]), clock.now);

      final tsFile = File(
        '${tmp.directory.path}${Platform.pathSeparator}entry1.ts',
      );
      await tsFile.delete();

      final result = await store.age('entry1', clock.now);
      expect(result, isNull);
    });

    test('corrupted .ts file causes age to return null', () async {
      await store.write('entry1', Uint8List.fromList([1]), clock.now);

      final tsFile = File(
        '${tmp.directory.path}${Platform.pathSeparator}entry1.ts',
      );
      await tsFile.writeAsString('not-a-date');

      final result = await store.age('entry1', clock.now);
      expect(result, isNull);
    });
  });

  group('FileCacheStore - TTL boundary', () {
    test('age exactly equals TTL at boundary', () async {
      const ttl = Duration(hours: 6);
      await store.write('entry1', Uint8List.fromList([0]), clock.now);
      clock.advance(ttl);

      final result = await store.age('entry1', clock.now);
      expect(result, equals(ttl));
    });
  });

  group('FileCacheStore - atomic write (FR-15)', () {
    test('no .tmp files remain after a successful write', () async {
      await store.write('entry1', Uint8List.fromList([1, 2, 3]), clock.now);

      final entities = await tmp.directory.list().toList();
      final names = entities.map((e) => e.uri.pathSegments.last).toList();
      expect(names, isNot(anyElement(endsWith('.tmp'))));
    });

    test('written data is immediately readable after rename', () async {
      final bytes = Uint8List.fromList([42, 43, 44]);
      await store.write('entry2', bytes, clock.now);

      final result = await store.read('entry2');
      expect(result, equals(bytes));
    });

    test('overwrites existing entry atomically', () async {
      final first = Uint8List.fromList([1]);
      final second = Uint8List.fromList([2, 3]);

      await store.write('entry3', first, clock.now);
      await store.write('entry3', second, clock.now);

      final result = await store.read('entry3');
      expect(result, equals(second));
    });

    test('age reflects timestamp of last write', () async {
      await store.write('entry4', Uint8List.fromList([0]), clock.now);
      clock.advance(const Duration(hours: 1));
      await store.write('entry4', Uint8List.fromList([1]), clock.now);
      clock.advance(const Duration(hours: 2));

      // Age is measured from the second write, not the first.
      final result = await store.age('entry4', clock.now);
      expect(result, equals(const Duration(hours: 2)));
    });
  });
}
