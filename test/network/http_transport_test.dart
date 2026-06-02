import 'dart:async';
import 'dart:io';

import 'package:celestrak/celestrak.dart';
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
}
