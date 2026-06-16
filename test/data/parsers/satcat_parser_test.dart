import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/data/parsers/satcat_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:test/test.dart';

Map<String, dynamic> _loadJson(String name) {
  final content = File('test/fixtures/satcat/$name').readAsStringSync();
  return jsonDecode(content) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _loadJsonList(String name) {
  final content = File('test/fixtures/satcat/$name').readAsStringSync();
  return (jsonDecode(content) as List<dynamic>).cast<Map<String, dynamic>>();
}

String _loadCsv(String name) =>
    File('test/fixtures/satcat/$name').readAsStringSync();

void main() {
  const parser = SatcatParser();

  group('SatcatParser.parseJson - single record', () {
    test('parses the ISS fixture into a SatcatEntry', () {
      final entry = parser.parseJson(_loadJson('iss_25544_satcat.json'));

      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
      expect(entry.objectId, equals('1998-067A'));
      expect(entry.ownerCode, equals('ISS'));
      expect(entry.objectType, equals(SatcatObjectType.payload));
      expect(entry.opsStatusCode, equals('+'));
      expect(entry.launchDate, equals(DateTime.utc(1998, 11, 20)));
      expect(entry.launchDate!.isUtc, isTrue);
      expect(entry.launchSite, equals('TYMSC'));
      expect(entry.decayDate, isNull);
      expect(entry.isOnOrbit, isTrue);
      expect(entry.periodMinutes, equals(92.9));
      expect(entry.inclination, equals(51.64));
      expect(entry.apogeeKm, equals(421));
      expect(entry.perigeeKm, equals(416));
      expect(entry.rcs, equals(401.39));
    });

    test('throws SatcatParseException on missing NORAD_CAT_ID', () {
      final json = _loadJson('iss_25544_satcat.json')..remove('NORAD_CAT_ID');
      expect(
        () => parser.parseJson(json),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException on non-integer NORAD_CAT_ID', () {
      final json = _loadJson('iss_25544_satcat.json');
      json['NORAD_CAT_ID'] = 'not-a-number';
      expect(
        () => parser.parseJson(json),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException on an empty object', () {
      expect(
        () => parser.parseJson(<String, dynamic>{}),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('carries null and N/A tolerance through from the model', () {
      final entry = parser.parseJson(_loadJson('satcat_null_fields.json'));

      expect(entry.noradId, equals(11574));
      expect(entry.name, equals(''));
      expect(entry.ownerCode, equals('CIS'));
      expect(entry.objectType, equals(SatcatObjectType.debris));
      expect(entry.launchDate, isNull);
      expect(entry.launchSite, isNull, reason: 'N/A normalises to null');
      expect(entry.decayDate, isNull);
      expect(entry.rcs, isNull, reason: 'N/A normalises to null');
      expect(entry.periodMinutes, isNull);
    });

    test('parses 6+ digit NORAD catalog numbers', () {
      final entry = parser.parseJson(_loadJson('satcat_6digit.json'));
      expect(entry.noradId, greaterThanOrEqualTo(100000));
    });

    test('a decayed object is not on-orbit', () {
      final entry = parser.parseJson(_loadJson('satcat_decayed.json'));
      expect(entry.decayDate, isNotNull);
      expect(entry.isOnOrbit, isFalse);
    });
  });

  group('SatcatParser.parseJsonList - bulk', () {
    test('parses every record in the stations group', () {
      final result =
          parser.parseJsonList(_loadJsonList('satcat_group_stations.json'));

      expect(result.entries, hasLength(3));
      expect(result.skipped, equals(0));
      expect(result.entries.first.noradId, equals(25544));
      expect(result.entries[1].noradId, equals(48274));
      expect(result.entries[2].objectType, equals(SatcatObjectType.debris));
    });

    test('an all-valid bulk parse reports skipped == 0', () {
      final result =
          parser.parseJsonList(_loadJsonList('satcat_group_stations.json'));
      expect(result.skipped, equals(0));
    });

    test('skips malformed rows, keeps valid ones, and surfaces the count', () {
      final result =
          parser.parseJsonList(_loadJsonList('satcat_malformed_row.json'));

      // Two valid rows (ISS, HST); two bad (missing id, non-numeric id).
      expect(result.entries, hasLength(2));
      expect(result.skipped, equals(2));
      expect(
        result.entries.map((e) => e.noradId),
        equals([25544, 20580]),
      );
    });

    test('never throws on a bad row', () {
      expect(
        () => parser.parseJsonList(_loadJsonList('satcat_malformed_row.json')),
        returnsNormally,
      );
    });

    test('an empty list yields an empty result', () {
      final result = parser.parseJsonList(<Map<String, dynamic>>[]);
      expect(result.entries, isEmpty);
      expect(result.skipped, equals(0));
    });
  });

  group('SatcatParser.parseCsv - single record', () {
    const header = 'NORAD_CAT_ID,OBJECT_NAME,OWNER,OBJECT_TYPE,LAUNCH_DATE';

    test('parses a single CSV data row', () {
      const csv = '$header\n25544,ISS (ZARYA),US,PAY,1998-11-20';
      final entry = parser.parseCsv(csv);
      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
      expect(entry.ownerCode, equals('US'));
      expect(entry.objectType, equals(SatcatObjectType.payload));
      expect(entry.launchDate, equals(DateTime.utc(1998, 11, 20)));
    });

    test('handles quoted fields with embedded commas', () {
      const csv = 'NORAD_CAT_ID,OBJECT_NAME,OWNER\n43205,"FALCON 9, R/B",US';
      final entry = parser.parseCsv(csv);
      expect(entry.name, equals('FALCON 9, R/B'));
      expect(entry.noradId, equals(43205));
    });

    test('handles doubled quotes inside a quoted field', () {
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n1,"A ""quoted"" name"';
      final entry = parser.parseCsv(csv);
      expect(entry.name, equals('A "quoted" name'));
    });

    test('accepts CRLF line endings', () {
      const csv = '$header\r\n25544,ISS,US,PAY,1998-11-20\r\n';
      final entry = parser.parseCsv(csv);
      expect(entry.noradId, equals(25544));
    });

    test('throws SatcatParseException on an empty body', () {
      expect(() => parser.parseCsv(''), throwsA(isA<SatcatParseException>()));
    });

    test('throws SatcatParseException on a header-only body', () {
      expect(
        () => parser.parseCsv(header),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException when the row lacks NORAD_CAT_ID', () {
      const csv = 'OBJECT_NAME,OWNER\nDEBRIS,US';
      expect(
        () => parser.parseCsv(csv),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException on an unterminated quoted field', () {
      // The quoted OBJECT_NAME is never closed; the open quote would otherwise
      // swallow every following row, so this is a document-level error.
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n25544,"ISS (ZARYA)';
      expect(
        () => parser.parseCsv(csv),
        throwsA(
          isA<SatcatParseException>().having(
            (e) => e.message,
            'message',
            contains('unterminated quoted field'),
          ),
        ),
      );
    });

    test('treats a mid-field double-quote as a literal character', () {
      // A quote that is not the first character of the field is literal, so no
      // text is silently dropped (lenient, non-RFC input).
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n1,he"llo';
      final entry = parser.parseCsv(csv);
      expect(entry.name, equals('he"llo'));
      expect(entry.noradId, equals(1));
    });

    test('strips a leading UTF-8 BOM before the header', () {
      const csv = '\u{FEFF}NORAD_CAT_ID,OBJECT_NAME\n25544,ISS (ZARYA)';
      final entry = parser.parseCsv(csv);
      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
    });
  });

  group('SatcatParser.parseCsvList - bulk', () {
    test('parses every data row', () {
      final result = parser.parseCsvList(_loadCsv('satcat_csv_sample.csv'));
      expect(result.entries, hasLength(3));
      expect(result.skipped, equals(0));
    });

    test('skips and counts a malformed row', () {
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n'
          '25544,ISS\n'
          'BADID,BROKEN\n'
          '20580,HST';
      final result = parser.parseCsvList(csv);
      expect(result.entries.map((e) => e.noradId), equals([25544, 20580]));
      expect(result.skipped, equals(1));
    });

    test('an empty document yields an empty result', () {
      final result = parser.parseCsvList('');
      expect(result.entries, isEmpty);
      expect(result.skipped, equals(0));
    });

    test('a header-only document yields an empty result', () {
      final result = parser.parseCsvList('NORAD_CAT_ID,OBJECT_NAME');
      expect(result.entries, isEmpty);
      expect(result.skipped, equals(0));
    });

    test('handles an embedded newline inside a quoted field', () {
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n'
          '1,"line one\nline two"\n'
          '2,SECOND';
      final result = parser.parseCsvList(csv);
      expect(result.entries, hasLength(2));
      expect(result.entries.first.name, equals('line one\nline two'));
      expect(result.entries[1].noradId, equals(2));
    });

    test('throws on an unterminated quoted field rather than merging rows', () {
      // The unclosed quote on row 1 would otherwise absorb every later row; the
      // bulk path must surface it as a document-level error, not skip it.
      const csv = 'NORAD_CAT_ID,OBJECT_NAME\n'
          '1,"never closed\n'
          '2,SECOND\n'
          '3,THIRD';
      expect(
        () => parser.parseCsvList(csv),
        throwsA(
          isA<SatcatParseException>().having(
            (e) => e.message,
            'message',
            contains('unterminated quoted field'),
          ),
        ),
      );
    });
  });

  group('CSV / JSON parity', () {
    // satcat_csv_sample.csv and satcat_group_stations.json are deliberately
    // kept in sync (same 3 records, same field values) so this parity check is
    // meaningful. If you edit one fixture, edit the other. See the `_comment`
    // field in the JSON fixture for the full note.
    test('CSV parser yields the same entries as the JSON parser', () {
      final fromJson =
          parser.parseJsonList(_loadJsonList('satcat_group_stations.json'));
      final fromCsv = parser.parseCsvList(_loadCsv('satcat_csv_sample.csv'));

      expect(fromCsv.entries, equals(fromJson.entries));
      expect(fromCsv.skipped, equals(fromJson.skipped));
    });

    test('empty RCS cell and RCS "N/A" both normalise to null (parity)', () {
      // Row 2 (CSS / NORAD 48274) uses an empty RCS cell in the CSV and
      // RCS:"N/A" in the JSON; both must yield rcs: null. This is the
      // intentional empty-vs-N/A equivalence the parity rests on.
      final fromJson =
          parser.parseJsonList(_loadJsonList('satcat_group_stations.json'));
      final fromCsv = parser.parseCsvList(_loadCsv('satcat_csv_sample.csv'));

      final jsonCss = fromJson.entries.firstWhere((e) => e.noradId == 48274);
      final csvCss = fromCsv.entries.firstWhere((e) => e.noradId == 48274);
      expect(jsonCss.rcs, isNull, reason: 'JSON RCS "N/A" normalises to null');
      expect(
        csvCss.rcs,
        isNull,
        reason: 'CSV empty RCS cell normalises to null',
      );
    });
  });

  group('SatcatParseResult', () {
    test('value equality over entries and skip count', () {
      const a = SatcatEntry(
        noradId: 1,
        name: 'A',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      final r1 = SatcatParseResult(entries: const [a], skipped: 2);
      final r2 = SatcatParseResult(entries: const [a], skipped: 2);
      final r3 = SatcatParseResult(entries: const [a], skipped: 3);

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1, isNot(equals(r3)));
      expect(r1.toString(), contains('skipped: 2'));
    });

    test('differs when the entries differ', () {
      const a = SatcatEntry(
        noradId: 1,
        name: 'A',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      const b = SatcatEntry(
        noradId: 2,
        name: 'B',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      expect(
        SatcatParseResult(entries: const [a], skipped: 0),
        isNot(equals(SatcatParseResult(entries: const [b], skipped: 0))),
      );
    });

    test('entries is unmodifiable: mutation throws', () {
      const a = SatcatEntry(
        noradId: 1,
        name: 'A',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      final result = SatcatParseResult(entries: const [a], skipped: 0);
      expect(() => result.entries.add(a), throwsUnsupportedError);
      expect(result.entries.clear, throwsUnsupportedError);
    });
  });
}
