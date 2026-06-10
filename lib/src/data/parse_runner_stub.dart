/// Web/WASM parse runner — no isolate support; runs synchronously.
library;

/// Runs [compute] synchronously and wraps the result in a completed [Future].
///
/// On web and WASM, `dart:isolate` is unavailable, so the `useIsolate` opt-in
/// becomes a no-op; parses run synchronously on the current isolate.
Future<R> runParse<R>(R Function() compute) => Future.value(compute());
