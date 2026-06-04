/// Tests for SpaceTrackClient credential-gating behaviour (FR-22).
///
/// Absent or empty credentials must disable the client cleanly — no throw at
/// construction. Calling fetchByQuery on a disabled client throws StateError.
/// The existing 401/403 → AuthenticationException and 429 → RateLimitException
/// mappings are covered in spacetrack_client_test.dart; only the disabled
/// source path is exercised here.
library;

import 'package:celestrak/celestrak.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a no-op [MockClient] that should never be called.
MockClient _neverCalled() => MockClient(
      (_) async => fail('HTTP client must not be called on a disabled source'),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── isEnabled / disabled construction ─────────────────────────────────────

  group('SpaceTrackClient — absent credentials (disabled source)', () {
    test('null identity and null password — construction succeeds', () {
      final client = SpaceTrackClient(identity: null, password: null);
      addTearDown(client.dispose);
      expect(client, isNotNull);
    });

    test('empty identity — construction succeeds', () {
      final client = SpaceTrackClient(identity: '', password: 'secret');
      addTearDown(client.dispose);
      expect(client, isNotNull);
    });

    test('empty password — construction succeeds', () {
      final client =
          SpaceTrackClient(identity: 'user@example.com', password: '');
      addTearDown(client.dispose);
      expect(client, isNotNull);
    });

    test('both empty — construction succeeds', () {
      final client = SpaceTrackClient(identity: '', password: '');
      addTearDown(client.dispose);
      expect(client, isNotNull);
    });

    test('no credentials supplied (default null) — isEnabled is false', () {
      final client = SpaceTrackClient();
      addTearDown(client.dispose);

      expect(client.isEnabled, isFalse);
    });

    test('null identity — isEnabled is false', () {
      final client = SpaceTrackClient(identity: null, password: 'secret');
      addTearDown(client.dispose);

      expect(client.isEnabled, isFalse);
    });

    test('null password — isEnabled is false', () {
      final client = SpaceTrackClient(
        identity: 'user@example.com',
        password: null,
      );
      addTearDown(client.dispose);

      expect(client.isEnabled, isFalse);
    });

    test('empty identity — isEnabled is false', () {
      final client = SpaceTrackClient(identity: '', password: 'secret');
      addTearDown(client.dispose);

      expect(client.isEnabled, isFalse);
    });

    test('empty password — isEnabled is false', () {
      final client = SpaceTrackClient(
        identity: 'user@example.com',
        password: '',
      );
      addTearDown(client.dispose);

      expect(client.isEnabled, isFalse);
    });

    test('valid credentials (default constructor) — isEnabled is true', () {
      final client = SpaceTrackClient(
        identity: 'user@example.com',
        password: 'secret',
      );
      addTearDown(client.dispose);

      expect(client.isEnabled, isTrue);
    });

    test('valid credentials (withClient) — isEnabled is true', () {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      );

      expect(client.isEnabled, isTrue);
    });

    test('disabled — isLoggedIn is always false', () {
      final client = SpaceTrackClient(identity: null, password: null);
      addTearDown(client.dispose);

      expect(client.isLoggedIn, isFalse);
    });
  });

  // ── fetchByQuery on a disabled client ─────────────────────────────────────

  group('SpaceTrackClient.fetchByQuery() — disabled source', () {
    test('throws StateError when identity is null', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: null,
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when password is null', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: null,
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when both credentials are null', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: null,
        password: null,
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when identity is empty', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: '',
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when password is empty', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: '',
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });

    test('StateError message mentions "disabled" and "isEnabled"', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: null,
        password: null,
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('disabled'))
              .having((e) => e.message, 'message', contains('isEnabled')),
        ),
      );
    });

    test('no HTTP requests are made when client is disabled', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: null,
        password: null,
        baseUrl: 'https://spacetrack.test',
      );

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── dispose on a disabled client ──────────────────────────────────────────

  group('SpaceTrackClient — dispose on disabled client', () {
    test('dispose on disabled owned-client instance does not throw', () {
      final client = SpaceTrackClient(identity: null, password: null);

      expect(client.dispose, returnsNormally);
    });

    test('dispose twice on disabled client does not throw', () {
      final client = SpaceTrackClient(identity: null, password: null);

      expect(client..dispose(), isA<void>());

      expect(client.dispose, returnsNormally);
    });

    test(
        'fetchByQuery after dispose throws StateError (disposed, not '
        'disabled)', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      );
      expect(client..dispose(), isA<void>());

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('disposed')),
        ),
      );
    });
  });
}
