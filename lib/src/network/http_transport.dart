/// HTTP transport with timeout, bounded retry/backoff, and HTTPS enforcement.
///
/// Implements a transport reliability contract: bounded retry with exponential
/// backoff, HTTPS enforcement, and injectable http.Client.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:celestrak/src/domain/failures.dart';
import 'package:http/http.dart' as http;

/// Default maximum number of attempts (1 initial + 4 retries).
const int kDefaultMaxAttempts = 5;

/// Default per-request timeout.
const Duration kDefaultTimeout = Duration(seconds: 30);

/// Base delay for exponential backoff.
const Duration kBackoffBase = Duration(milliseconds: 200);

/// Maximum backoff cap to prevent unbounded waits.
const Duration kBackoffMax = Duration(seconds: 10);

/// Performs HTTP GET requests with timeout, bounded retry/backoff, and
/// HTTPS enforcement.
///
/// Retries are attempted only for transient failures:
/// - HTTP 5xx responses
/// - [TimeoutException] (request exceeded `timeout`)
/// - [SocketException] (network unreachable / DNS failure)
///
/// 4xx responses are **never** retried — they indicate a caller error and
/// retrying would not help.
///
/// HTTPS enforcement: any non-`https` URL throws [ArgumentError] immediately,
/// before any network call is made.
///
/// Inject a custom [http.Client] for testing; the transport does **not** own
/// the client and will never close it.
///
/// See also:
/// - [NetworkException] — thrown when all retry attempts are exhausted.
final class HttpTransport {
  /// Creates an [HttpTransport].
  ///
  /// [client] is the underlying HTTP client. The transport does not close it.
  /// [maxAttempts] is the total number of attempts (initial + retries).
  /// [timeout] is the per-attempt deadline.
  HttpTransport({
    required http.Client client,
    int maxAttempts = kDefaultMaxAttempts,
    Duration timeout = kDefaultTimeout,
  })  : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
        _client = client,
        _maxAttempts = maxAttempts,
        _timeout = timeout;

  final http.Client _client;
  final int _maxAttempts;
  final Duration _timeout;

  /// Issues an HTTP GET to [uri] and returns the response body as a [String].
  ///
  /// Throws [ArgumentError] if [uri] does not use the `https` scheme.
  /// Throws [NetworkException] if all retry attempts are exhausted without a
  /// successful (2xx) response.
  Future<String> get(Uri uri) async {
    if (uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'Only HTTPS URIs are permitted; got scheme "${uri.scheme}"',
      );
    }

    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_backoffFor(attempt));
      }

      try {
        final response = await _client.get(uri).timeout(_timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.body;
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw NetworkException(
            'HTTP ${response.statusCode} from $uri (4xx — not retried)',
            statusCode: response.statusCode,
            uri: uri,
          );
        }

        if (response.statusCode >= 500) {
          // 5xx — retryable
          lastError = NetworkException(
            'HTTP ${response.statusCode} from $uri',
            statusCode: response.statusCode,
            uri: uri,
          );
        } else {
          // 1xx / 3xx — unexpected; treat as non-retryable.
          throw NetworkException(
            'Unexpected HTTP ${response.statusCode} from $uri',
            statusCode: response.statusCode,
            uri: uri,
          );
        }
      } on NetworkException {
        // 4xx — re-throw immediately without consuming retry budget
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      }
    }

    final cause = lastError;
    if (cause is NetworkException) {
      throw NetworkException(
        'All $_maxAttempts attempts failed for $uri: ${cause.message}',
        statusCode: cause.statusCode,
        uri: uri,
        cause: cause,
      );
    }

    throw NetworkException(
      'All $_maxAttempts attempts failed for $uri: $lastError',
      uri: uri,
      cause: lastError,
    );
  }

  /// Computes the backoff delay for [retryNumber] (1-based retry index).
  ///
  /// [retryNumber] must be >= 1. Passing 0 would produce a 0 ms delay due to
  /// integer truncation of `2^(-1) = 0.5`.
  Duration _backoffFor(int retryNumber) {
    assert(retryNumber >= 1, '_backoffFor requires retryNumber >= 1');
    // Exponential: base * 2^(retryNumber-1), capped at [kBackoffMax].
    final ms = kBackoffBase.inMilliseconds * math.pow(2, retryNumber - 1);
    final capped = ms.clamp(0, kBackoffMax.inMilliseconds).toInt();
    return Duration(milliseconds: capped);
  }
}
