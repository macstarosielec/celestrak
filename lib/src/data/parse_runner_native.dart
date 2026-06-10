/// Native parse runner — offloads to a worker isolate via `Isolate.run`.
library;

import 'dart:isolate' show Isolate;

/// Runs [compute] on a worker isolate.
///
/// [compute] must be a top-level or static function that captures no instance
/// state (isolate message-passing constraint).
Future<R> runParse<R>(R Function() compute) => Isolate.run(compute);
