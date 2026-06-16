import 'dart:io' show File, SocketException;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// ISS SATCAT single-object JSON fixture (bare object), loaded once.
late String _issSatcatObject;

/// Group/stations SATCAT JSON array fixture (3 records), loaded once.
late String _groupStations;

/// Bulk fixture with one malformed row among valid rows, loaded once.
late String _malformedRow;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/satcat/records.php';

/// Creates a [SatcatDataSource] backed by a [MockClient] using [handler].
SatcatDataSource _source(
  MockClientHandler handler, {
  String baseUrl = _testBase,
  int maxAttempts = 1,
}) =>
    SatcatDataSource(
      transport: HttpTransport(
        client: MockClient(handler),
        maxAttempts: maxAttempts,
        timeout: const Duration(seconds: 5),
      ),
      baseUrl: baseUrl,
    );

/// Runs [fn] and asserts it throws [SatelliteNotFoundException], returning it.
Future<SatelliteNotFoundException> _catchNotFound(
  Future<void> Function() fn,
) async {
  try {
    await fn();
    fail('Expected SatelliteNotFoundException, but completed normally');
  } on SatelliteNotFoundException catch (e) {
    return e;
  }
}

/// Runs [fn] and asserts it throws [NetworkException], returning it.
Future<NetworkException> _catchNetwork(Future<void> Function() fn) async {
  try {
    await fn();
    fail('Expected NetworkException, but completed normally');
  } on NetworkException catch (e) {
    return e;
  }
}

void main() {
  setUpAll(() async {
    _issSatcatObject =
        await File('test/fixtures/satcat/iss_25544_satcat.json').readAsString();
    _groupStations = await File(
      'test/fixtures/satcat/satcat_group_stations.json',
    ).readAsString();
    _malformedRow = await File(
      'test/fixtures/satcat/satcat_malformed_row.json',
    ).readAsString();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // URI construction
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - URI construction', () {
    test('builds CATNR query with uppercase keys and FORMAT=JSON', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issSatcatObject, 200);
      });

      await source.fetchByNoradId(25544);

      expect(captured, isNotNull);
      expect(captured!.queryParameters['CATNR'], equals('25544'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
      expect(captured!.queryParameters.containsKey('catnr'), isFalse);
    });

    test('CATNR value matches the requested noradId exactly', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issSatcatObject, 200);
      });

      await source.fetchByNoradId(12345);

      expect(captured!.queryParameters['CATNR'], equals('12345'));
    });

    test('builds GROUP query with uppercase keys and FORMAT=JSON', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_groupStations, 200);
      });

      await source.fetchByGroup('stations');

      expect(captured!.queryParameters['GROUP'], equals('stations'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
      expect(captured!.queryParameters.containsKey('group'), isFalse);
    });

    test('builds INTDES query with uppercase keys and FORMAT=JSON', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_groupStations, 200);
      });

      await source.fetchByIntlDesignator('1998-067A');

      expect(captured!.queryParameters['INTDES'], equals('1998-067A'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
      expect(captured!.queryParameters.containsKey('intdes'), isFalse);
    });

    test('fetchAll builds GROUP=active full-catalog query', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_groupStations, 200);
      });

      await source.fetchAll();

      expect(captured!.queryParameters['GROUP'], equals('active'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
    });

    test('trims the international designator before the query', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_groupStations, 200);
      });

      await source.fetchByIntlDesignator('  1998-067A  ');

      expect(captured!.queryParameters['INTDES'], equals('1998-067A'));
    });

    test('pre-existing query parameters in baseUrl are preserved', () async {
      Uri? captured;
      const baseWithKey =
          'https://celestrak.test/satcat/records.php?apikey=abc123';
      final source = _source(
        (request) async {
          captured = request.url;
          return http.Response(_issSatcatObject, 200);
        },
        baseUrl: baseWithKey,
      );

      await source.fetchByNoradId(25544);

      expect(captured!.queryParameters['apikey'], equals('abc123'));
      expect(captured!.queryParameters['CATNR'], equals('25544'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
    });

    test('http:// baseUrl propagates ArgumentError from transport', () async {
      final source = _source(
        (_) async => http.Response(_issSatcatObject, 200),
        baseUrl: 'http://celestrak.test/satcat/records.php',
      );

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fetchByNoradId - happy path + parse correctness
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - fetchByNoradId', () {
    test('returns the parsed ISS SatcatEntry from a bare object body',
        () async {
      final source = _source(
        (_) async => http.Response(_issSatcatObject, 200),
      );

      final entry = await source.fetchByNoradId(25544);

      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
      expect(entry.objectId, equals('1998-067A'));
      expect(entry.ownerCode, equals('US'));
      expect(entry.objectType, equals(SatcatObjectType.payload));
      expect(entry.isOnOrbit, isTrue);
      expect(entry.inclination, closeTo(51.64, 1e-9));
      expect(entry.periodMinutes, closeTo(92.9, 1e-9));
    });

    test('unwraps a single-element JSON array (CelesTrak wire shape)',
        () async {
      final arrayBody = '[$_issSatcatObject]';
      final source = _source((_) async => http.Response(arrayBody, 200));

      final entry = await source.fetchByNoradId(25544);

      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
    });

    test('works with 6+ digit catalog numbers', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issSatcatObject, 200);
      });

      await source.fetchByNoradId(270000);

      expect(captured!.queryParameters['CATNR'], equals('270000'));
    });

    test('rejects noradId < 1 with ArgumentError and no network call',
        () async {
      var calls = 0;
      final source = _source((_) async {
        calls++;
        return http.Response(_issSatcatObject, 200);
      });

      await expectLater(
        source.fetchByNoradId(0),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'noradId'),
        ),
      );
      expect(calls, equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Single-record miss -> SatelliteNotFoundException
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - single-record miss', () {
    test('empty JSON array body throws SatelliteNotFoundException', () async {
      final source = _source((_) async => http.Response('[]', 200));

      final ex = await _catchNotFound(() => source.fetchByNoradId(99999));

      expect(ex.noradId, equals(99999));
      expect(ex.message, contains('99999'));
    });

    test('empty body throws SatelliteNotFoundException', () async {
      final source = _source((_) async => http.Response('', 200));

      final ex = await _catchNotFound(() => source.fetchByNoradId(99999));

      expect(ex.noradId, equals(99999));
    });

    test('whitespace-only body throws SatelliteNotFoundException', () async {
      final source = _source((_) async => http.Response('   \n', 200));

      await _catchNotFound(() => source.fetchByNoradId(99999));
    });

    test('the failing URI is attached to the exception', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response('[]', 200);
      });

      final ex = await _catchNotFound(() => source.fetchByNoradId(99999));

      expect(ex.uri, equals(captured));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Malformed single body -> SatcatParseException
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - malformed single body', () {
    test('non-JSON body throws SatcatParseException', () async {
      final source = _source(
        (_) async => http.Response('this is not json', 200),
      );

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('JSON object without NORAD_CAT_ID throws SatcatParseException',
        () async {
      final source = _source(
        (_) async => http.Response('{"OBJECT_NAME": "X"}', 200),
      );

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('array of a non-object element throws SatcatParseException', () async {
      final source = _source((_) async => http.Response('[123]', 200));

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('top-level JSON scalar throws SatcatParseException', () async {
      final source = _source((_) async => http.Response('42', 200));

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<SatcatParseException>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Transport failures -> NetworkException
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - transport failures', () {
    test('5xx after retries surfaces as NetworkException', () async {
      final source = _source(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      final ex = await _catchNetwork(() => source.fetchByNoradId(25544));

      expect(ex.statusCode, equals(503));
    });

    test('4xx is not retried and surfaces as NetworkException', () async {
      var calls = 0;
      final source = _source(
        (_) async {
          calls++;
          return http.Response('bad request', 400);
        },
        maxAttempts: 5,
      );

      final ex = await _catchNetwork(() => source.fetchByNoradId(25544));

      expect(ex.statusCode, equals(400));
      expect(calls, equals(1), reason: '4xx must not consume retry budget');
    });

    test('a thrown socket error surfaces as NetworkException', () async {
      final source = _source(
        (_) async => throw const SocketException('network down'),
        maxAttempts: 1,
      );

      await _catchNetwork(() => source.fetchByNoradId(25544));
    });

    test('bulk fetch also surfaces transport failure as NetworkException',
        () async {
      final source = _source(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await _catchNetwork(() => source.fetchByGroup('stations'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Bulk paths - results, empty list, malformed-row skip
  // ─────────────────────────────────────────────────────────────────────────

  group('SatcatDataSource - fetchByGroup', () {
    test('returns the parsed list of entries', () async {
      final source = _source((_) async => http.Response(_groupStations, 200));

      final entries = await source.fetchByGroup('stations');

      expect(entries, hasLength(3));
      expect(entries.first.noradId, equals(25544));
      expect(entries.map((e) => e.noradId), contains(48274));
    });

    test('empty JSON array yields an empty list (no throw)', () async {
      final source = _source((_) async => http.Response('[]', 200));

      final entries = await source.fetchByGroup('nonexistent');

      expect(entries, isEmpty);
    });

    test('empty body yields an empty list (no throw)', () async {
      final source = _source((_) async => http.Response('', 200));

      final entries = await source.fetchByGroup('nonexistent');

      expect(entries, isEmpty);
    });

    test('a malformed row is skipped, valid rows are returned', () async {
      final source = _source((_) async => http.Response(_malformedRow, 200));

      final entries = await source.fetchByGroup('mixed');

      // Fixture: 2 valid (25544, 20580) + 2 malformed (missing/non-numeric id).
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.noradId), containsAll(<int>[25544, 20580]));
    });

    test(
        'a non-object array element is silently dropped, valid objects '
        'are returned', () async {
      final validRow = _issSatcatObject.trim();
      final body = '[$validRow, 42, $validRow]';
      final source = _source((_) async => http.Response(body, 200));

      final entries = await source.fetchByGroup('mixed');

      // The scalar `42` is pre-filtered out; both valid objects survive.
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.noradId == 25544), isTrue);
    });

    test('trims the group before the query', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_groupStations, 200);
      });

      await source.fetchByGroup('  stations  ');

      expect(captured!.queryParameters['GROUP'], equals('stations'));
    });

    test('a top-level JSON object is wrapped into a single-element list',
        () async {
      final source = _source((_) async => http.Response(_issSatcatObject, 200));

      final entries = await source.fetchByGroup('stations');

      expect(entries, hasLength(1));
      expect(entries.single.noradId, equals(25544));
    });

    test('a top-level JSON scalar throws SatcatParseException', () async {
      final source = _source((_) async => http.Response('42', 200));

      await expectLater(
        source.fetchByGroup('stations'),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('rejects empty group with ArgumentError and no network call',
        () async {
      var calls = 0;
      final source = _source((_) async {
        calls++;
        return http.Response(_groupStations, 200);
      });

      await expectLater(
        source.fetchByGroup('   '),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'group')),
      );
      expect(calls, equals(0));
    });
  });

  group('SatcatDataSource - fetchByIntlDesignator', () {
    test('returns the parsed list of entries', () async {
      final source = _source((_) async => http.Response(_groupStations, 200));

      final entries = await source.fetchByIntlDesignator('1998-067');

      expect(entries, hasLength(3));
    });

    test('no match yields an empty list (no throw)', () async {
      final source = _source((_) async => http.Response('[]', 200));

      final entries = await source.fetchByIntlDesignator('1957-001A');

      expect(entries, isEmpty);
    });

    test('rejects empty designator with ArgumentError', () async {
      final source = _source(
        (_) async => http.Response(_groupStations, 200),
      );

      await expectLater(
        source.fetchByIntlDesignator(''),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'intlDesignator'),
        ),
      );
    });
  });

  group('SatcatDataSource - fetchAll', () {
    test('returns the parsed list of entries', () async {
      final source = _source((_) async => http.Response(_groupStations, 200));

      final entries = await source.fetchAll();

      expect(entries, hasLength(3));
    });

    test('empty catalogue yields an empty list (no throw)', () async {
      final source = _source((_) async => http.Response('[]', 200));

      final entries = await source.fetchAll();

      expect(entries, isEmpty);
    });
  });
}
