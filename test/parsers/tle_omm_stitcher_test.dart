import 'dart:convert';
import 'dart:io';

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/parsers/tle_omm_stitcher.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Loads the ISS OMM JSON array and returns the first entry as an [Omm].
Future<Omm> _loadIssOmm() async {
  final content = await File('test/fixtures/iss_25544_omm.json').readAsString();
  final json =
      (jsonDecode(content) as List<dynamic>).first as Map<String, dynamic>;
  return Omm(
    objectName: json['OBJECT_NAME'] as String?,
    objectId: json['OBJECT_ID'] as String?,
    epoch: DateTime.parse(json['EPOCH'] as String),
    centerName: json['CENTER_NAME'] as String,
    refFrame: json['REF_FRAME'] as String,
    timeSystem: json['TIME_SYSTEM'] as String,
    meanElementTheory: json['MEAN_ELEMENT_THEORY'] as String,
    meanMotion: (json['MEAN_MOTION'] as num).toDouble(),
    eccentricity: (json['ECCENTRICITY'] as num).toDouble(),
    inclination: (json['INCLINATION'] as num).toDouble(),
    raOfAscNode: (json['RA_OF_ASC_NODE'] as num).toDouble(),
    argOfPericenter: (json['ARG_OF_PERICENTER'] as num).toDouble(),
    meanAnomaly: (json['MEAN_ANOMALY'] as num).toDouble(),
    ephemerisType: json['EPHEMERIS_TYPE'] as int,
    classificationType: json['CLASSIFICATION_TYPE'] as String,
    noradCatId: json['NORAD_CAT_ID'] as int,
    elementSetNo: json['ELEMENT_SET_NO'] as int,
    revAtEpoch: json['REV_AT_EPOCH'] as int,
    bstar: (json['BSTAR'] as num).toDouble(),
    meanMotionDot: (json['MEAN_MOTION_DOT'] as num).toDouble(),
    meanMotionDdot: (json['MEAN_MOTION_DDOT'] as num).toDouble(),
  );
}

/// Minimal [Omm] for a satellite with [noradCatId] and [objectName].
Omm _minimalOmm({required int noradCatId, String? objectName}) {
  return Omm(
    objectName: objectName,
    objectId: null,
    epoch: DateTime.utc(2026, 6, 1),
    centerName: 'EARTH',
    refFrame: 'TEME',
    timeSystem: 'UTC',
    meanElementTheory: 'SGP4',
    meanMotion: 15,
    eccentricity: 0.001,
    inclination: 51.6,
    raOfAscNode: 0,
    argOfPericenter: 0,
    meanAnomaly: 0,
    ephemerisType: 0,
    classificationType: 'U',
    noradCatId: noradCatId,
    elementSetNo: 1,
    revAtEpoch: 1,
    bstar: 0,
    meanMotionDot: 0,
    meanMotionDdot: 0,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  const stitcher = TleOmmStitcher();
  final fixedFetchedAt = DateTime.utc(2026, 6, 2, 12);

  late String stationsTle;
  late Omm issOmm;

  setUpAll(() async {
    stationsTle = await File('test/fixtures/stations_group.txt').readAsString();
    issOmm = await _loadIssOmm();
  });

  // -------------------------------------------------------------------------
  // Happy path
  // -------------------------------------------------------------------------

  group('TleOmmStitcher — happy path', () {
    test('returns SatelliteTle with correct noradId', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.noradId, equals(25544));
    });

    test('returned SatelliteTle has omm populated', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.omm, isNotNull);
      expect(result.omm!.noradCatId, equals(25544));
    });

    test('verbatim line1 and line2 are extracted from TLE body', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.line1, startsWith('1 25544'));
      expect(result.line2, startsWith('2 25544'));
    });

    test('non-empty TLE lines are not empty strings', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.line1, isNotEmpty);
      expect(result.line2, isNotEmpty);
    });

    test('OMM name takes precedence over TLE name', () {
      // OMM objectName = "ISS (ZARYA)"; TLE name = "ISS (ZARYA)" too here,
      // but OMM is the one used.
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.name, equals('ISS (ZARYA)'));
    });

    test('fetchedAt is stamped correctly', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.fetchedAt, equals(fixedFetchedAt));
    });

    test('source is TleSource.celestrak', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.source, equals(TleSource.celestrak));
    });

    test('epoch from TLE body is preserved in stitched record', () {
      // The TLE parser derives epoch from line1; the OMM epoch comes from the
      // JSON EPOCH field. After stitching the TLE-parsed epoch is kept.
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      // Epoch should be in 2026 (both fixtures are June 2026).
      expect(result.epoch.year, equals(2026));
      expect(result.epoch.isUtc, isTrue);
    });

    test('stitches second record from multi-record TLE body (Hubble)', () {
      final hubbleOmm = _minimalOmm(
        noradCatId: 20580,
        objectName: 'HUBBLE',
      );

      final result = stitcher.stitch(
        hubbleOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.noradId, equals(20580));
      expect(result.line1, startsWith('1 20580'));
      expect(result.line2, startsWith('2 20580'));
      expect(result.omm, isNotNull);
    });

    test('stitches third record from multi-record TLE body (Tiangong)', () {
      final tiangongOmm = _minimalOmm(
        noradCatId: 48274,
        objectName: 'TIANGONG',
      );

      final result = stitcher.stitch(
        tiangongOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.noradId, equals(48274));
      expect(result.line1, startsWith('1 48274'));
      expect(result.line2, startsWith('2 48274'));
    });

    test('null fetchedAt falls back to DateTime.now (is UTC)', () {
      final result = stitcher.stitch(issOmm, stationsTle);

      expect(result.fetchedAt.isUtc, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // OMM name / TLE name resolution
  // -------------------------------------------------------------------------

  group('TleOmmStitcher — name resolution', () {
    test('TLE name used when OMM objectName is null', () {
      final omm = _minimalOmm(noradCatId: 25544, objectName: null);

      final result = stitcher.stitch(
        omm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      // Name falls back to TLE record's name.
      expect(result.name, equals('ISS (ZARYA)'));
    });

    test('OMM name used when both OMM and TLE name are present', () {
      final omm = _minimalOmm(
        noradCatId: 25544,
        objectName: 'CUSTOM NAME',
      );

      final result = stitcher.stitch(
        omm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.name, equals('CUSTOM NAME'));
    });
  });

  // -------------------------------------------------------------------------
  // 6+ digit NORAD IDs (RK-1) — empty-lines fallback
  // -------------------------------------------------------------------------

  group('TleOmmStitcher — 6+ digit NORAD ID / missing record (RK-1)', () {
    test('empty TLE body returns SatelliteTle with empty lines', () {
      final omm = _minimalOmm(noradCatId: 120000, objectName: 'DEBRIS');

      final result = stitcher.stitch(
        omm,
        '',
        fetchedAt: fixedFetchedAt,
      );

      expect(result.line1, isEmpty);
      expect(result.line2, isEmpty);
    });

    test('whitespace-only TLE body returns SatelliteTle with empty lines', () {
      final omm = _minimalOmm(noradCatId: 120000);

      final result = stitcher.stitch(
        omm,
        '   \n  \n',
        fetchedAt: fixedFetchedAt,
      );

      expect(result.line1, isEmpty);
      expect(result.line2, isEmpty);
    });

    test('empty-lines result still has omm populated', () {
      final omm = _minimalOmm(noradCatId: 120000, objectName: 'DEBRIS');

      final result = stitcher.stitch(
        omm,
        '',
        fetchedAt: fixedFetchedAt,
      );

      expect(result.omm, isNotNull);
      expect(result.omm!.noradCatId, equals(120000));
    });

    test('epoch from OMM used when TLE body is empty', () {
      final epoch = DateTime.utc(2026, 3, 15, 10);
      final omm = Omm(
        objectName: null,
        objectId: null,
        epoch: epoch,
        centerName: 'EARTH',
        refFrame: 'TEME',
        timeSystem: 'UTC',
        meanElementTheory: 'SGP4',
        meanMotion: 14,
        eccentricity: 0,
        inclination: 0,
        raOfAscNode: 0,
        argOfPericenter: 0,
        meanAnomaly: 0,
        ephemerisType: 0,
        classificationType: 'U',
        noradCatId: 120000,
        elementSetNo: 1,
        revAtEpoch: 0,
        bstar: 0,
        meanMotionDot: 0,
        meanMotionDdot: 0,
      );

      final result = stitcher.stitch(
        omm,
        '',
        fetchedAt: fixedFetchedAt,
      );

      expect(result.epoch, equals(epoch));
    });

    test('NORAD ID not in TLE body returns empty lines (no throw)', () {
      final omm = _minimalOmm(noradCatId: 99998, objectName: 'UNKNOWN');

      // 99998 is not in stations_group.txt — should not throw.
      final result = stitcher.stitch(
        omm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.line1, isEmpty);
      expect(result.line2, isEmpty);
      expect(result.noradId, equals(99998));
      expect(result.omm, isNotNull);
    });

    test('name from OMM used when record absent', () {
      final omm = _minimalOmm(noradCatId: 99998, objectName: 'PHANTOM');

      final result = stitcher.stitch(
        omm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.name, equals('PHANTOM'));
    });

    test('name is empty string when OMM objectName is null and record absent',
        () {
      final omm = _minimalOmm(noradCatId: 99998, objectName: null);

      final result = stitcher.stitch(
        omm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result.name, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Malformed TLE body
  // -------------------------------------------------------------------------

  group('TleOmmStitcher — malformed TLE body', () {
    test('throws TleParseException on non-multiple-of-3 line count', () {
      // Two non-empty lines — not a valid TLE body.
      const badBody = 'ISS (ZARYA)\n'
          '1 25544U 98067A   26152.54166667'
          '  .00010768  00000-0  17455-4 0  9995';

      expect(
        () => stitcher.stitch(
          issOmm,
          badBody,
          fetchedAt: fixedFetchedAt,
        ),
        throwsA(isA<TleParseException>()),
      );
    });

    test('TleParseException.message is non-empty on malformed body', () {
      const badBody = 'one line only';

      try {
        stitcher.stitch(issOmm, badBody, fetchedAt: fixedFetchedAt);
        fail('Expected TleParseException');
      } on TleParseException catch (e) {
        expect(e.message, isNotEmpty);
      }
    });

    test(
        'bad checksum with verifyChecksum:true throws TleParseException '
        'for the bad line', () {
      final badTle = File('test/fixtures/bad_checksum.tle').readAsStringSync();
      final omm = _minimalOmm(noradCatId: 25544);

      expect(
        () => stitcher.stitch(
          omm,
          badTle,
          fetchedAt: fixedFetchedAt,
        ),
        throwsA(
          isA<TleParseException>().having(
            (e) => e.field,
            'field',
            anyOf('line1', 'line2'),
          ),
        ),
      );
    });

    test('bad checksum with verifyChecksum:false does not throw', () {
      final badTle = File('test/fixtures/bad_checksum.tle').readAsStringSync();
      final omm = _minimalOmm(noradCatId: 25544);

      // Should not throw when checksum verification is disabled.
      expect(
        () => stitcher.stitch(
          omm,
          badTle,
          fetchedAt: fixedFetchedAt,
          verifyChecksum: false,
        ),
        returnsNormally,
      );
    });
  });

  // -------------------------------------------------------------------------
  // SatelliteTle type contract
  // -------------------------------------------------------------------------

  group('TleOmmStitcher — SatelliteTle contract', () {
    test('returned value is a SatelliteTle', () {
      final result = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(result, isA<SatelliteTle>());
    });

    test('two stitch calls with same inputs return equal SatelliteTle', () {
      final a = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );
      final b = stitcher.stitch(
        issOmm,
        stationsTle,
        fetchedAt: fixedFetchedAt,
      );

      expect(a, equals(b));
    });
  });
}
