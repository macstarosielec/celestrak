/// Live integration tests — hit the real Space-Track.org API.
///
/// These tests are excluded from the default `dart test` run.
/// Run explicitly with:
///   dart test --tags integration
///
/// They require:
///   - An active internet connection reachable to www.space-track.org.
///   - Valid credentials in the `SPACE_TRACK_USER` and `SPACE_TRACK_PASS`
///     environment variables.
///
/// When either environment variable is absent the entire suite is skipped.
/// Credentials are **never** hard-coded or committed; they are read at runtime
/// from the process environment only.
@Tags(['integration'])
library;

import 'dart:io' show Platform;

import 'package:celestrak/celestrak.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Timeout generous enough for login + one GP query with network latency.
const _timeout = Duration(seconds: 60);

/// ISS NORAD catalog number.
const _issNoradId = 25544;

/// A NORAD ID that is not in the Space-Track catalog.
const _absentNoradId = 99999999;

/// Reads credentials from the environment and returns a live
/// [SpaceTrackClient].
///
/// Returns `null` when either environment variable is absent or empty, which
/// causes the test suite to be skipped rather than fail.
///
/// Each call allocates a new [http.Client] owned by the returned
/// [SpaceTrackClient]. Callers must call [SpaceTrackClient.dispose] to release
/// it, which closes the underlying client.
SpaceTrackClient? _liveClient() {
  final identity = Platform.environment['SPACE_TRACK_USER'];
  final password = Platform.environment['SPACE_TRACK_PASS'];

  if (identity == null ||
      identity.isEmpty ||
      password == null ||
      password.isEmpty) {
    return null;
  }

  return SpaceTrackClient(
    identity: identity,
    password: password,
  );
}

/// Asserts the core invariants that every Space-Track [SatelliteTle] must
/// satisfy.
void _assertValidRecord(SatelliteTle s) {
  expect(s.noradId, greaterThan(0), reason: 'noradId must be positive');
  expect(s.line1, hasLength(69), reason: 'TLE line 1 must be 69 chars');
  expect(s.line2, hasLength(69), reason: 'TLE line 2 must be 69 chars');
  expect(
    s.source,
    equals(TleSource.spacetrack),
    reason: 'source must be TleSource.spacetrack',
  );
  expect(
    s.name,
    isNotEmpty,
    reason: 'name must be non-empty for a known object',
  );

  // Epoch should be within the last 30 days — older data suggests stale feed.
  final age = DateTime.now().toUtc().difference(s.epoch);
  expect(
    age.inDays,
    lessThan(30),
    reason: 'epoch should be recent (got age ${age.inDays} days)',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final hasCredentials = _liveClient() != null;

  group(
    'SpaceTrackClient live API',
    skip: hasCredentials
        ? null
        : 'SPACE_TRACK_USER / SPACE_TRACK_PASS not set — skipping',
    () {

      // ── credential gating ─────────────────────────────────────────────────

      test(
        'isEnabled returns true when SPACE_TRACK_USER/PASS are set',
        () {
          final client = _liveClient()!;
          try {
            expect(client.isEnabled, isTrue);
          } finally {
            client.dispose();
          }
        },
        tags: 'integration',
      );

      // ── fetchByQuery — happy path ─────────────────────────────────────────

      test(
        'fetchByQuery returns ISS (NORAD 25544) with valid TLE lines',
        () async {
          final client = _liveClient()!;
          try {
            final iss = await client.fetchByQuery(
              SpaceTrackQuery.byNoradId(_issNoradId),
            );
            _assertValidRecord(iss);
            expect(
              iss.noradId,
              equals(_issNoradId),
              reason: 'noradId must match the queried catalog number',
            );
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByQuery stamps source as TleSource.spacetrack',
        () async {
          final client = _liveClient()!;
          try {
            final iss = await client.fetchByQuery(
              SpaceTrackQuery.byNoradId(_issNoradId),
            );
            expect(iss.source, equals(TleSource.spacetrack));
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByQuery result includes a populated Omm with correct noradId',
        () async {
          final client = _liveClient()!;
          try {
            final iss = await client.fetchByQuery(
              SpaceTrackQuery.byNoradId(_issNoradId),
            );
            final omm = iss.omm;
            expect(
              omm,
              isNotNull,
              reason: 'OMM must be populated for Space-Track responses',
            );
            expect(omm!.noradCatId, equals(_issNoradId));
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByQuery ISS epoch is a recent UTC timestamp',
        () async {
          final client = _liveClient()!;
          try {
            final iss = await client.fetchByQuery(
              SpaceTrackQuery.byNoradId(_issNoradId),
            );
            // epoch is UTC and within the past 30 days.
            expect(iss.epoch.isUtc, isTrue);
            final ageInDays =
                DateTime.now().toUtc().difference(iss.epoch).inDays;
            expect(
              ageInDays,
              lessThan(30),
              reason: 'epoch should be recent (age: $ageInDays days)',
            );
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      // ── fetchByQuery — not found ───────────────────────────────────────────

      test(
        'fetchByQuery throws SatelliteNotFoundException for unknown NORAD ID',
        () async {
          final client = _liveClient()!;
          try {
            await expectLater(
              () => client.fetchByQuery(
                SpaceTrackQuery.byNoradId(_absentNoradId),
              ),
              throwsA(isA<SatelliteNotFoundException>()),
            );
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      // ── fetchByQuery — disabled client ─────────────────────────────────────

      test(
        'fetchByQuery throws StateError when credentials are absent',
        () async {
          final disabled = SpaceTrackClient.withClient(
            client: http.Client(),
            identity: null,
            password: null,
          );
          try {
            expect(disabled.isEnabled, isFalse);
            await expectLater(
              () => disabled.fetchByQuery(
                SpaceTrackQuery.byNoradId(_issNoradId),
              ),
              throwsStateError,
            );
          } finally {
            disabled.dispose();
          }
        },
        tags: 'integration',
      );
    },
    // Space-Track may occasionally be slow; allow one automatic retry per test
    // to reduce false negatives from transient network errors.
    retry: 1,
  );
}
