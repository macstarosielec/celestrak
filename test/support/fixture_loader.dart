/// Utility for loading test fixture files relative to the package root.
///
/// Resolves paths against the package root directory derived from
/// [Platform.script], so tests work regardless of the working directory in
/// which `dart test` is invoked (IDE, CI, melos sub-package, etc.).
library;

import 'dart:io' show File, Platform;

/// Returns the absolute path to [relativePath] resolved from the package root.
///
/// [relativePath] should be a POSIX-style path relative to the package root,
/// e.g. `'test/fixtures/stations_group_omm.json'`.
String fixturePath(String relativePath) {
  // Platform.script points to the test entry file.  Walking up to the package
  // root: test/<subdir>/<file>.dart  → up 2 levels to reach the root.
  final scriptDir = File(Platform.script.toFilePath()).parent;
  // scriptDir is the directory of the *compiled* test script, which lives
  // under .dart_tool/... in some runners.  To be robust, walk up until we
  // find a directory that contains pubspec.yaml.
  var dir = scriptDir;
  for (var i = 0; i < 10; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync()) return '${dir.path}/$relativePath';
    final parent = dir.parent;
    if (parent.path == dir.path) break; // filesystem root
    dir = parent;
  }
  // Fallback: relative path (matches pre-existing convention).
  return relativePath;
}

/// Reads and returns the content of the fixture file at [relativePath].
Future<String> loadFixture(String relativePath) =>
    File(fixturePath(relativePath)).readAsString();
