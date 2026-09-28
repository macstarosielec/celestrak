/// Live integration tests — hit the real CelesTrak API.
///
/// These tests are skipped in the default `dart test` run (see
/// `dart_test.yaml`). Run explicitly with:
///   dart test --tags integration --run-skipped
///
/// They require an active internet connection and a reachable celestrak.org.
/// Each test uses a fresh [MemoryCacheStore] so there are no cross-test
/// cache side-effects and no on-disk files are written.
@Tags(['integration'])
library;

import 'package:celestrak/celestrak.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Timeout generous enough for a cold network request with one retry.
const _timeout = Duration(seconds: 30);

/// Creates a live [CelestrakClient] backed by [MemoryCacheStore].
CelestrakClient _liveClient() => CelestrakClient.withStore(
      httpClient: http.Client(),
      cacheStore: MemoryCacheStore(),
      maxAttempts: 2,
    );

/// Asserts the core invariants that every [SatelliteTle] must satisfy.
///
/// CelesTrak serves no `FORMAT=TLE` record for NORAD IDs >= 100 000 (the
/// classic TLE catalog field is five digits), so OMM-format fetches of such
/// objects legitimately carry empty lines and rely on [SatelliteTle.omm].
/// Every other record must carry two verbatim 69-char lines.
void _assertValidRecord(SatelliteTle s) {
  expect(s.noradId, greaterThan(0), reason: 'noradId must be positive');
  if (s.noradId >= 100000 && s.omm != null) {
    expect(
      s.line1.isEmpty || s.line1.length == 69,
      isTrue,
      reason: 'TLE line 1 must be empty or 69 chars for 6-digit IDs',
    );
    expect(
      s.line2.length,
      equals(s.line1.length),
      reason: 'TLE lines must be both present or both absent',
    );
  } else {
    expect(s.line1, hasLength(69), reason: 'TLE line 1 must be 69 chars');
    expect(s.line2, hasLength(69), reason: 'TLE line 2 must be 69 chars');
  }
  // Epoch should be within the last 30 days — older data indicates stale feed.
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
  group(
    'CelesTrak live API',
    () {
      // ── fetchByNoradId ─────────────────────────────────────────────────

      test(
        'fetchByNoradId returns ISS (25544)',
        () async {
          final client = _liveClient();
          try {
            final iss = await client.fetchByNoradId(25544);
            _assertValidRecord(iss);
            expect(iss.noradId, equals(25544));
            expect(iss.name, isNotEmpty);
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByNoradId returns Hubble (20580) in TLE format',
        () async {
          final client = _liveClient();
          try {
            final hubble = await client.fetchByNoradId(
              20580,
              format: CelestrakFormat.tle,
            );
            _assertValidRecord(hubble);
            expect(hubble.noradId, equals(20580));
            expect(
              hubble.omm,
              isNull,
              reason: 'OMM absent for TLE-format fetch',
            );
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      // ── fetchCategory ──────────────────────────────────────────────────

      test(
        'fetchCategory(stations) returns multiple records',
        () async {
          final client = _liveClient();
          try {
            final records =
                await client.fetchCategory(SatelliteCategory.stations);
            expect(records, isNotEmpty);
            records.forEach(_assertValidRecord);
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      // ── fetchCategoryByGroup ───────────────────────────────────────────

      test(
        "fetchCategoryByGroup('stations') returns multiple records",
        () async {
          final client = _liveClient();
          try {
            final records = await client.fetchCategoryByGroup('stations');
            expect(records, isNotEmpty);
            records.forEach(_assertValidRecord);
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchCategoryByGroup throws ArgumentError for empty group',
        () async {
          final client = _liveClient();
          try {
            await expectLater(
              () => client.fetchCategoryByGroup(''),
              throwsArgumentError,
            );
          } finally {
            client.dispose();
          }
        },
        tags: 'integration',
      );

      // ── fetchByName ────────────────────────────────────────────────────

      test(
        "fetchByName('ISS') returns non-empty list",
        () async {
          final client = _liveClient();
          try {
            final records = await client.fetchByName('ISS');
            expect(records, isNotEmpty);
            records.forEach(_assertValidRecord);
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByName returns empty list for unknown name',
        () async {
          final client = _liveClient();
          try {
            final records = await client.fetchByName(
              'XYZZY_NO_SUCH_SATELLITE_42',
            );
            expect(records, isEmpty);
          } finally {
            client.dispose();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );
    },
    // CelesTrak may reset connections under rapid successive requests;
    // one retry avoids false negatives from transient network errors.
    retry: 1,
  );
}
