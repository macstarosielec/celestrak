import 'package:celestrak/src/domain/failures.dart';
import 'package:test/test.dart';

void main() {
  // ── CelestrakException ────────────────────────────────────────────────────

  // CelestrakException is sealed — every concrete subtype overrides
  // toString(), so the base CelestrakException.toString() is unreachable dead
  // code (sealed class + all subtypes override).  We cannot create a new
  // subtype in tests, so we cannot cover that line.  Each concrete subtype's
  // toString is covered in its own group below.  This group validates the
  // base-class contract (the message field) using an arbitrary subtype.
  group('CelestrakException — base class contract', () {
    test('message field is accessible on CelestrakException base', () {
      const ex = NetworkException('test message');

      expect((ex as CelestrakException).message, 'test message');
    });
  });

  // ── OmmParseException ─────────────────────────────────────────────────────

  group('OmmParseException — toString', () {
    test('without field uses plain prefix', () {
      const ex = OmmParseException('bad epoch format');

      expect(ex.toString(), 'OmmParseException: bad epoch format');
    });

    test('with field includes field name in parens', () {
      const ex = OmmParseException('null value', field: 'EPOCH');

      expect(ex.toString(), 'OmmParseException(EPOCH): null value');
    });

    test('field is null when not supplied', () {
      const ex = OmmParseException('parse error');

      expect(ex.field, isNull);
    });

    test('field is set when supplied', () {
      const ex = OmmParseException('missing', field: 'MEAN_MOTION');

      expect(ex.field, 'MEAN_MOTION');
    });
  });

  // ── NetworkException ──────────────────────────────────────────────────────

  group('NetworkException — toString', () {
    test('minimal toString contains the message', () {
      const ex = NetworkException('connection refused');

      expect(ex.toString(), contains('connection refused'));
    });

    test('toString includes statusCode when set', () {
      const ex = NetworkException('server error', statusCode: 500);

      expect(ex.toString(), contains('statusCode=500'));
    });

    test('toString includes uri when set', () {
      final uri = Uri.parse('https://celestrak.org/gp.php');
      final ex = NetworkException('not found', uri: uri);

      expect(ex.toString(), contains('uri='));
    });

    test('toString includes cause runtimeType when set', () {
      final ex = NetworkException(
        'timed out',
        cause: Exception('timeout'),
      );

      expect(ex.toString(), contains('cause='));
    });
  });

  // ── SatelliteNotFoundException ────────────────────────────────────────────

  group('SatelliteNotFoundException — toString', () {
    test('contains noradId', () {
      const ex = SatelliteNotFoundException(
        'not found',
        noradId: 25544,
      );

      expect(ex.toString(), contains('noradId=25544'));
    });

    test('contains uri when set', () {
      final uri = Uri.parse('https://celestrak.org/gp.php?CATNR=25544');
      final ex = SatelliteNotFoundException(
        'not found',
        noradId: 25544,
        uri: uri,
      );

      expect(ex.toString(), contains('uri='));
    });

    test('noradId 0 is sentinel for group/category queries', () {
      const ex = SatelliteNotFoundException(
        'group empty',
        noradId: 0,
      );

      expect(ex.noradId, 0);
      expect(ex.toString(), contains('noradId=0'));
    });
  });

  // ── AuthenticationException ───────────────────────────────────────────────

  group('AuthenticationException — toString', () {
    test('contains statusCode', () {
      const ex = AuthenticationException(
        'invalid credentials',
        statusCode: 401,
      );

      expect(ex.toString(), contains('statusCode=401'));
    });

    test('contains uri when set', () {
      final uri = Uri.parse('https://www.space-track.org/ajaxauth/login');
      final ex = AuthenticationException(
        'forbidden',
        statusCode: 403,
        uri: uri,
      );

      expect(ex.toString(), contains('uri='));
    });
  });

  // ── RateLimitException ────────────────────────────────────────────────────

  group('RateLimitException — toString', () {
    test('minimal toString contains message', () {
      const ex = RateLimitException('rate limited');

      expect(ex.toString(), contains('rate limited'));
    });

    test('retryAfter appears in toString when set', () {
      const ex = RateLimitException(
        'too many requests',
        retryAfter: Duration(seconds: 30),
      );

      expect(ex.toString(), contains('retryAfter=30s'));
    });

    test('uri appears in toString when set', () {
      final uri = Uri.parse('https://www.space-track.org/basicspacedata');
      final ex = RateLimitException('rate limited', uri: uri);

      expect(ex.toString(), contains('uri='));
    });
  });

  // ── TleParseException ─────────────────────────────────────────────────────

  group('TleParseException — toString', () {
    test('without field uses plain prefix', () {
      const ex = TleParseException('checksum mismatch');

      expect(ex.toString(), 'TleParseException: checksum mismatch');
    });

    test('with field includes field name in parens', () {
      const ex = TleParseException('truncated', field: 'line1');

      expect(ex.toString(), 'TleParseException(line1): truncated');
    });
  });

  // ── CacheMissException ────────────────────────────────────────────────────

  group('CacheMissException — toString', () {
    test('includes key in toString', () {
      const ex = CacheMissException(
        'entry not found',
        key: 'norad:25544~fmt:omm~src:celestrak',
      );

      const expected = 'CacheMissException(norad:25544~fmt:omm~src:celestrak):'
          ' entry not found';
      expect(ex.toString(), expected);
    });

    test('key field is accessible', () {
      const ex = CacheMissException('miss', key: 'some-key');

      expect(ex.key, 'some-key');
    });
  });
}
