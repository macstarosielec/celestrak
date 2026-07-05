import 'dart:async';
import 'dart:io';

import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates an [HttpTransport] backed by [handler].
///
/// [maxAttempts] and [timeout] default to values that keep tests fast.
HttpTransport _transport(
  MockClientHandler handler, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 5),
}) =>
    HttpTransport(
      client: MockClient(handler),
      maxAttempts: maxAttempts,
      timeout: timeout,
    );

/// Runs [fn] and returns the [NetworkException] it throws.
///
/// Fails the test if [fn] completes normally or throws a different type.
Future<NetworkException> _catchNetwork(Future<void> Function() fn) async {
  try {
    await fn();
    fail('Expected NetworkException, but completed normally');
  } on NetworkException catch (e) {
    return e;
  }
}

final _httpsUri = Uri.https('example.celestrak.com', '/gp.php');
final _httpUri = Uri.http('example.celestrak.com', '/gp.php');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HttpTransport — happy path', () {
    test('returns body on 200 OK', () async {
      final transport = _transport(
        (_) async => http.Response('body text', 200),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals('body text'));
    });

    test('returns body on 201 Created', () async {
      final transport = _transport(
        (_) async => http.Response('created', 201),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals('created'));
    });

    test('succeeds on first attempt without unnecessary retries', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('ok', 200);
      });

      await transport.get(_httpsUri);
      expect(callCount, equals(1));
    });
  });

  group('HttpTransport — HTTPS enforcement', () {
    test('throws ArgumentError immediately for http:// URI', () async {
      final transport = _transport(
        (_) async => http.Response('should not reach', 200),
      );

      await expectLater(
        transport.get(_httpUri),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.message, 'message', contains('HTTPS'))
              .having((e) => e.name, 'name', equals('uri')),
        ),
      );
    });

    test('throws ArgumentError for ftp:// URI', () async {
      final transport = _transport(
        (_) async => http.Response('nope', 200),
      );
      final ftpUri = Uri.parse('ftp://example.com/file');

      await expectLater(
        transport.get(ftpUri),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('no network call is made for non-HTTPS URI', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('', 200);
      });

      await expectLater(
        transport.get(_httpUri),
        throwsA(isA<ArgumentError>()),
      );
      expect(callCount, equals(0));
    });
  });

  group('HttpTransport — 4xx not retried', () {
    test('throws NetworkException immediately on 404 without retry', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('not found', 404);
      });

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.statusCode, equals(404));
      expect(exception.uri, equals(_httpsUri));
      // Must not retry: only one call despite maxAttempts=3.
      expect(callCount, equals(1));
    });

    test('throws NetworkException immediately on 400', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('bad request', 400);
      });

      await expectLater(
        transport.get(_httpsUri),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', equals(400)),
        ),
      );
      expect(callCount, equals(1));
    });

    test('throws NetworkException immediately on 401', () async {
      final transport = _transport(
        (_) async => http.Response('unauthorized', 401),
      );

      await expectLater(
        transport.get(_httpsUri),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', equals(401)),
        ),
      );
    });
  });

  group('HttpTransport — 5xx retry and exhaust', () {
    test('retries 5xx up to maxAttempts then throws NetworkException',
        () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          return http.Response('server error', 503);
        },
        maxAttempts: 3,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.statusCode, equals(503));
      expect(exception.uri, equals(_httpsUri));
      expect(callCount, equals(3));
    });

    test('succeeds on retry after initial 5xx', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        if (callCount < 2) return http.Response('error', 500);
        return http.Response('success', 200);
      });

      final result = await transport.get(_httpsUri);
      expect(result, equals('success'));
      expect(callCount, equals(2));
    });

    test('NetworkException message mentions attempt count', () async {
      final transport = _transport(
        (_) async => http.Response('error', 500),
        maxAttempts: 2,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.message, contains('2'));
    });
  });

  group('HttpTransport — timeout retry', () {
    test('retries on TimeoutException and exhausts maxAttempts', () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          // Delay longer than the transport timeout.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('late', 200);
        },
        maxAttempts: 2,
        // Shorter than the 200 ms delay above.
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        transport.get(_httpsUri),
        throwsA(isA<NetworkException>()),
      );
      expect(callCount, equals(2));
    });

    test('succeeds if response arrives before timeout', () async {
      final transport = _transport(
        (_) async => http.Response('fast', 200),
        timeout: const Duration(seconds: 5),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals('fast'));
    });
  });

  group('HttpTransport — SocketException retry', () {
    test('retries on SocketException and exhausts maxAttempts', () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          throw const SocketException('network unreachable');
        },
        maxAttempts: 3,
      );

      await expectLater(
        transport.get(_httpsUri),
        throwsA(isA<NetworkException>()),
      );
      expect(callCount, equals(3));
    });

    test('succeeds on retry after SocketException', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        if (callCount == 1) throw const SocketException('temporary');
        return http.Response('recovered', 200);
      });

      final result = await transport.get(_httpsUri);
      expect(result, equals('recovered'));
      expect(callCount, equals(2));
    });
  });

  group('HttpTransport — NetworkException fields', () {
    test('uri field is set on 4xx', () async {
      final transport = _transport(
        (_) async => http.Response('', 404),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.uri, equals(_httpsUri));
    });

    test('statusCode field is set on 5xx exhaust', () async {
      final transport = _transport(
        (_) async => http.Response('', 502),
        maxAttempts: 1,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.statusCode, equals(502));
    });

    test('cause field is set when last error is a SocketException', () async {
      final transport = _transport(
        (_) async => throw const SocketException('unreachable'),
        maxAttempts: 1,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.cause, isA<SocketException>());
    });

    test('cause field is set when last error is a 5xx NetworkException',
        () async {
      final transport = _transport(
        (_) async => http.Response('', 503),
        maxAttempts: 1,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.cause, isA<NetworkException>());
    });

    test('toString includes statusCode and uri', () async {
      final transport = _transport(
        (_) async => http.Response('', 503),
        maxAttempts: 1,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      final s = exception.toString();
      expect(s, contains('503'));
      expect(s, contains('NetworkException'));
    });
  });

  group('HttpTransport — unexpected status codes', () {
    test('throws NetworkException immediately on 3xx without retry', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('', 301);
      });

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.statusCode, equals(301));
      expect(exception.uri, equals(_httpsUri));
      // Must not retry: only one call despite maxAttempts=3.
      expect(callCount, equals(1));
    });

    test('throws NetworkException immediately on 1xx without retry', () async {
      var callCount = 0;
      final transport = _transport((_) async {
        callCount++;
        return http.Response('', 101);
      });

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.statusCode, equals(101));
      expect(callCount, equals(1));
    });
  });

  group('HttpTransport — maxAttempts edge cases', () {
    test('maxAttempts=1 means zero retries on 5xx', () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          return http.Response('error', 500);
        },
        maxAttempts: 1,
      );

      await expectLater(
        transport.get(_httpsUri),
        throwsA(isA<NetworkException>()),
      );
      expect(callCount, equals(1));
    });
  });

  group('HttpTransport — NetworkFailureKind classification', () {
    test('kind is httpRejected on immediate 4xx', () async {
      final transport = _transport(
        (_) async => http.Response('bad request', 400),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('kind is httpRejected on 1xx/3xx unexpected status', () async {
      final transport = _transport(
        (_) async => http.Response('', 301),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('kind is httpRejected after 5xx retries exhausted', () async {
      final transport = _transport(
        (_) async => http.Response('server error', 503),
        maxAttempts: 3,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('kind is timeout after TimeoutException retries exhausted', () async {
      final transport = _transport(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('late', 200);
        },
        maxAttempts: 2,
        timeout: const Duration(milliseconds: 50),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.timeout));
    });

    test('kind is network after ClientException retries exhausted', () async {
      final transport = _transport(
        (_) async => throw http.ClientException('connection refused'),
        maxAttempts: 2,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.network));
    });

    test('kind is network after SocketException retries exhausted', () async {
      final transport = _transport(
        (_) async => throw const SocketException('network unreachable'),
        maxAttempts: 2,
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.network));
    });

    test('mixed-cause retry sequence classifies by the LAST attempt error',
        () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          // First attempt: 503. Second attempt: TimeoutException. Third
          // attempt (last): SocketException — kind must reflect this one.
          if (callCount == 1) return http.Response('error', 503);
          if (callCount == 2) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return http.Response('late', 200);
          }
          throw const SocketException('unreachable');
        },
        maxAttempts: 3,
        timeout: const Duration(milliseconds: 50),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.network));
      expect(exception.cause, isA<SocketException>());
      expect(callCount, equals(3));
    });
  });

  group('HttpTransport — HTML block-page sniff', () {
    test('200 body starting with <!DOCTYPE html> is rejected', () async {
      final transport = _transport(
        (_) async => http.Response('<!DOCTYPE html><html></html>', 200),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
      expect(exception.statusCode, equals(200));
    });

    test('200 body starting with <html> is rejected', () async {
      final transport = _transport(
        (_) async => http.Response('<html><body>blocked</body></html>', 200),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('sniff is case-insensitive', () async {
      final transport = _transport(
        (_) async => http.Response('<!DocType HTML><HTML></HTML>', 200),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('sniff tolerates leading whitespace before <!DOCTYPE', () async {
      final transport = _transport(
        (_) async => http.Response('\n\n  <!DOCTYPE html><html></html>', 200),
      );

      final exception = await _catchNetwork(() => transport.get(_httpsUri));

      expect(exception.kind, equals(NetworkFailureKind.httpRejected));
    });

    test('sniff does not retry — only one transport call', () async {
      var callCount = 0;
      final transport = _transport(
        (_) async {
          callCount++;
          return http.Response('<html>block page</html>', 200);
        },
        maxAttempts: 3,
      );

      await expectLater(
        transport.get(_httpsUri),
        throwsA(isA<NetworkException>()),
      );
      expect(callCount, equals(1));
    });

    test('JSON array body is not sniffed as HTML', () async {
      final transport = _transport(
        (_) async => http.Response('[{"OBJECT_NAME": "ISS"}]', 200),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals('[{"OBJECT_NAME": "ISS"}]'));
    });

    test('CSV header line is not sniffed as HTML', () async {
      const csv = 'OBJECT_NAME,OBJECT_ID,NORAD_CAT_ID\nISS,1998-067A,25544';
      final transport = _transport(
        (_) async => http.Response(csv, 200),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals(csv));
    });

    test('a raw TLE line is not sniffed as HTML', () async {
      const tle = '1 25544U 98067A   24001.00000000  .00000000  '
          '00000-0  00000-0 0  9990';
      final transport = _transport(
        (_) async => http.Response(tle, 200),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals(tle));
    });

    test('an XML body starting with <?xml is not sniffed as HTML', () async {
      const xml = '<?xml version="1.0"?><ndm></ndm>';
      final transport = _transport(
        (_) async => http.Response(xml, 200),
      );

      final result = await transport.get(_httpsUri);
      expect(result, equals(xml));
    });
  });
}
