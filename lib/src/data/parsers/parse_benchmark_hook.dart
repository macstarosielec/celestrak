/// Benchmark hook for parser timing (ADR-9 stub).
///
/// A future hardening pass will run the worst-case category benchmark
/// (full `starlink` OMM) and decide whether to add an opt-in
/// `Isolate.run` parse path (ADR-9). This hook lets the measurement
/// harness instrument parse calls without changing the production code
/// path.
///
/// See also:
/// - [NullParseBenchmarkHook] — the default no-op implementation.
/// - ADR-9: "Parsing: synchronous default; opt-in `Isolate.run` gated on
///   benchmark".
library;

/// Receives timing signals around a single multi-record parse operation.
///
/// Implement this interface to collect parse duration metrics. The default
/// production hook is [NullParseBenchmarkHook], which does nothing.
///
/// ## Contract
///
/// [onParseStart] is called immediately before the first record is emitted.
/// [onParseEnd] is called after all records have been emitted (or after the
/// first exception, so the pair always brackets the observable work).
/// `recordCount` is the number of successfully parsed records.
///
/// Both methods are synchronous — do not perform I/O inside them.
///
/// ## Label values
///
/// The built-in parsers use the string constants [labelTle] and [labelOmm] as
/// the `label` argument. Implementations that filter or dispatch by label
/// should use these constants rather than hardcoding `'tle'` / `'omm'`.
abstract interface class ParseBenchmarkHook {
  /// The label used by `TleParser` in [onParseStart] and [onParseEnd].
  static const String labelTle = 'tle';

  /// The label used by `OmmParser` in [onParseStart] and [onParseEnd].
  static const String labelOmm = 'omm';

  /// Called before a multi-record parse begins.
  ///
  /// [label] identifies the parse operation — one of [labelTle] or [labelOmm]
  /// when called by the library's own parsers.
  void onParseStart(String label);

  /// Called after a multi-record parse completes.
  ///
  /// [label] is the same value that was passed to [onParseStart].
  /// [recordCount] is the number of records that were successfully yielded.
  /// If the parse terminated early due to an exception, [recordCount] reflects
  /// the number of records successfully yielded before the exception;
  /// [elapsed] covers the same window.
  /// [elapsed] is the wall-clock duration of the parse.
  void onParseEnd(String label, int recordCount, Duration elapsed);
}

/// A no-op [ParseBenchmarkHook] used in production.
///
/// All methods are empty; the compiler eliminates them as dead code when the
/// benchmark hook is not replaced at construction time.
final class NullParseBenchmarkHook implements ParseBenchmarkHook {
  /// Creates a [NullParseBenchmarkHook].
  const NullParseBenchmarkHook();

  @override
  void onParseStart(String label) {}

  @override
  void onParseEnd(String label, int recordCount, Duration elapsed) {}
}
