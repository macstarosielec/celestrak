import 'dart:io' show File, SocketException;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// ISS OMM JSON fixture, loaded once before the suite runs.
late String _issOmmFixture;

/// ISS TLE fixture, loaded once before the suite runs.
late String _issTleFixture;

/// Creates a [CelestrakDataSource] backed by a [MockClient] using [handler].
///
/// [baseUrl] overrides the production endpoint so no real network calls occur.
CelestrakDataSource _source(
  MockClientHandler handler, {
  String baseUrl = 'https://celestrak.test/gp.php',
  int maxAttempts = 1,
}) =>
    CelestrakDataSource(
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _issOmmFixture =
        await File('test/fixtures/iss_25544_omm.json').readAsString();
    _issTleFixture = await File('test/fixtures/iss_25544.tle').readAsString();
  });

  group('CelestrakDataSource — URI construction', () {
    test('builds CATNR query with uppercase keys for OMM format', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issOmmFixture, 200);
      });

      await source.fetchByNoradId(25544);

      expect(captured, isNotNull);
      expect(captured!.queryParameters['CATNR'], equals('25544'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
    });

    test('builds FORMAT=TLE for CelestrakFormat.tle', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issTleFixture, 200);
      });

      await source.fetchByNoradId(25544, format: CelestrakFormat.tle);

      expect(captured!.queryParameters['FORMAT'], equals('TLE'));
    });

    test('URI uses the configured baseUrl', () async {
      Uri? captured;
      const customBase = 'https://mirror.example.org/gp.php';
      final source = _source(
        (request) async {
          captured = request.url;
          return http.Response(_issOmmFixture, 200);
        },
        baseUrl: customBase,
      );

      await source.fetchByNoradId(25544);

      expect(captured!.toString(), startsWith(customBase));
    });

    test('URI uses the https scheme of the configured baseUrl', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issOmmFixture, 200);
      });

      await source.fetchByNoradId(25544);

      expect(captured!.scheme, equals('https'));
    });

    test('pre-existing query parameters in baseUrl are preserved and merged',
        () async {
      Uri? captured;
      // baseUrl already has an apikey= parameter —
      // the data source must keep it.
      const baseWithKey = 'https://celestrak.test/gp.php?apikey=abc123';
      final source = _source(
        (request) async {
          captured = request.url;
          return http.Response(_issOmmFixture, 200);
        },
        baseUrl: baseWithKey,
      );

      await source.fetchByNoradId(25544);

      expect(captured, isNotNull);
      expect(captured!.queryParameters['apikey'], equals('abc123'));
      expect(captured!.queryParameters['CATNR'], equals('25544'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
    });

    test('http:// baseUrl propagates ArgumentError from transport', () async {
      // HttpTransport enforces HTTPS (NFR-7); a non-HTTPS URI raises
      // ArgumentError before any network call is made.
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
        baseUrl: 'http://celestrak.test/gp.php',
      );

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CelestrakDataSource — happy path', () {
    test('returns response body verbatim on 200 for OMM format', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      final result = await source.fetchByNoradId(25544);

      expect(result, equals(_issOmmFixture));
    });

    test('returns response body verbatim on 200 for TLE format', () async {
      final source = _source(
        (_) async => http.Response(_issTleFixture, 200),
      );

      final result = await source.fetchByNoradId(
        25544,
        format: CelestrakFormat.tle,
      );

      expect(result, equals(_issTleFixture));
    });

    test('works with large NORAD IDs (>5 digits)', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      // Should not throw — large catalog numbers are valid (FR-1, RK-1).
      final result = await source.fetchByNoradId(999999);
      expect(result, equals(_issOmmFixture));
    });

    test('CATNR value matches the requested noradId exactly', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issOmmFixture, 200);
      });

      await source.fetchByNoradId(12345);

      expect(captured!.queryParameters['CATNR'], equals('12345'));
    });
  });

  group('CelestrakDataSource — not-found sentinel (FR-23)', () {
    test('throws SatelliteNotFoundException when body is "No GP data found"',
        () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final ex = await _catchNotFound(
        () => source.fetchByNoradId(99999),
      );

      expect(ex.noradId, equals(99999));
    });

    test('SatelliteNotFoundException.uri is set to the request URI', () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final ex = await _catchNotFound(
        () => source.fetchByNoradId(99999),
      );

      expect(ex.uri, isNotNull);
      expect(ex.uri!.queryParameters['CATNR'], equals('99999'));
    });

    test('SatelliteNotFoundException.message mentions the noradId', () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final ex = await _catchNotFound(
        () => source.fetchByNoradId(99999),
      );

      expect(ex.message, contains('99999'));
    });

    test('sentinel match is exact — extra whitespace is trimmed', () async {
      // CelesTrak may include a trailing newline; tolerate it.
      final source = _source(
        (_) async => http.Response('No GP data found\n', 200),
      );

      await expectLater(
        source.fetchByNoradId(99999),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('sentinel match tolerates CRLF line endings', () async {
      // Some HTTP servers append a trailing CRLF to response bodies.
      final source = _source(
        (_) async => http.Response('No GP data found\r\n', 200),
      );

      await expectLater(
        source.fetchByNoradId(99999),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('partial sentinel string is not a not-found response', () async {
      const partialBody = 'No GP data';
      final source = _source(
        (_) async => http.Response(partialBody, 200),
      );

      // Should NOT throw SatelliteNotFoundException — just return the body.
      final result = await source.fetchByNoradId(99999);
      expect(result, equals(partialBody));
    });

    test('SatelliteNotFoundException.toString includes noradId', () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final ex = await _catchNotFound(
        () => source.fetchByNoradId(11111),
      );

      expect(ex.toString(), contains('11111'));
      expect(ex.toString(), contains('SatelliteNotFoundException'));
    });

    test('SatelliteNotFoundException.toString includes uri when set', () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final ex = await _catchNotFound(
        () => source.fetchByNoradId(11111),
      );

      expect(ex.uri, isNotNull);
      expect(ex.toString(), contains('uri='));
    });
  });

  group('CelestrakDataSource — network error mapping (FR-23)', () {
    test('propagates NetworkException on 404', () async {
      final source = _source(
        (_) async => http.Response('not found', 404),
      );

      final ex = await _catchNetwork(
        () => source.fetchByNoradId(25544),
      );

      expect(ex.statusCode, equals(404));
    });

    test('propagates NetworkException after 5xx retries exhausted', () async {
      final source = _source(
        (_) async => http.Response('server error', 503),
        maxAttempts: 2,
      );

      final ex = await _catchNetwork(
        () => source.fetchByNoradId(25544),
      );

      expect(ex.statusCode, equals(503));
    });

    test('propagates NetworkException on SocketException', () async {
      final source = _source(
        (_) async => throw const SocketException('network unreachable'),
        maxAttempts: 1,
      );

      final ex = await _catchNetwork(
        () => source.fetchByNoradId(25544),
      );

      expect(ex.cause, isA<SocketException>());
    });

    test('4xx is not retried — only one transport call', () async {
      var callCount = 0;
      final source = _source((_) async {
        callCount++;
        return http.Response('bad request', 400);
      });

      await expectLater(
        source.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );

      expect(callCount, equals(1));
    });
  });

  group('CelestrakDataSource — argument validation', () {
    test('throws ArgumentError for noradId < 1', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      await expectLater(
        source.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for negative noradId', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      await expectLater(
        source.fetchByNoradId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('no network call is made when noradId is invalid', () async {
      var callCount = 0;
      final source = _source((_) async {
        callCount++;
        return http.Response(_issOmmFixture, 200);
      });

      await expectLater(
        source.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );

      expect(callCount, equals(0));
    });

    test('noradId=1 is valid and issues a network call', () async {
      var callCount = 0;
      final source = _source((_) async {
        callCount++;
        return http.Response(_issOmmFixture, 200);
      });

      await source.fetchByNoradId(1);

      expect(callCount, equals(1));
    });
  });

  group('CelestrakDataSource — fetchByName', () {
    test('builds NAME= and FORMAT= with uppercase keys for OMM format',
        () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issOmmFixture, 200);
      });

      await source.fetchByName('ISS');

      expect(captured, isNotNull);
      expect(captured!.queryParameters['NAME'], equals('ISS'));
      expect(captured!.queryParameters['FORMAT'], equals('JSON'));
    });

    test('builds FORMAT=TLE for CelestrakFormat.tle', () async {
      Uri? captured;
      final source = _source((request) async {
        captured = request.url;
        return http.Response(_issTleFixture, 200);
      });

      await source.fetchByName('ISS', format: CelestrakFormat.tle);

      expect(captured!.queryParameters['FORMAT'], equals('TLE'));
    });

    test('returns empty string when server returns sentinel (FR-3)', () async {
      final source = _source(
        (_) async => http.Response('No GP data found', 200),
      );

      final result = await source.fetchByName('NONEXISTENT');

      expect(result, equals(''));
    });

    test('returns body verbatim on a successful match', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      final result = await source.fetchByName('ISS');

      expect(result, equals(_issOmmFixture));
    });

    test('throws ArgumentError for empty name', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      await expectLater(
        source.fetchByName(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for whitespace-only name', () async {
      final source = _source(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      await expectLater(
        source.fetchByName('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propagates NetworkException on transport error', () async {
      final source = _source(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        source.fetchByName('ISS'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
