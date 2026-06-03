import 'package:celestrak/src/data/parsers/parse_benchmark_hook.dart';

/// A [ParseBenchmarkHook] that records every signal it receives.
///
/// Shared across parser test files to avoid verbatim duplication of this
/// helper.
final class RecordingBenchmarkHook implements ParseBenchmarkHook {
  final starts = <String>[];
  final ends = <(String, int, Duration)>[];

  @override
  void onParseStart(String label) => starts.add(label);

  @override
  void onParseEnd(String label, int recordCount, Duration elapsed) =>
      ends.add((label, recordCount, elapsed));
}
