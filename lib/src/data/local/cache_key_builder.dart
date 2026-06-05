/// Cache-key construction.
///
/// Keys encode `{queryType, queryValue, format, source}` as a
/// URL-safe, alphanumeric-and-separator string that `CacheStore`
/// implementations can use as filenames or map keys without escaping.
///
/// Key format:
/// ```text
/// {queryType}:{queryValue}~fmt:{format}~src:{source}
/// ```
/// All components are lower-cased and sanitised before joining.
/// The resulting string is guaranteed to pass `CacheStore.validateKey`.
///
/// ## Example
/// ```dart
/// final key = CacheKeyBuilder.forNoradId(
///   25544,
///   format: CelestrakFormat.omm,
/// );
/// // → 'norad:25544~fmt:omm~src:celestrak'
/// ```
library;

import 'package:celestrak/src/domain/enums.dart';

// Characters allowed anywhere in a cache key (excluding `~` which is the
// segment separator — added separately in _assertValid).
final _invalidChars = RegExp(r'[^a-z0-9:_\-~]');

// Full validation pattern: alphanumeric plus `:`, `_`, `-`, `~`.
final _validKey = RegExp(r'^[A-Za-z0-9:_\-~]+$');

/// Builds validated cache keys.
///
/// Every public factory normalises its inputs, joins the components, and
/// asserts the result against `CacheStore.validateKey`-compatible rules
/// (alphanumeric plus `:`, `_`, `-`, `~`).  Keys never contain path-traversal
/// characters.
///
/// All constructors are private; use the named factories.
final class CacheKeyBuilder {
  CacheKeyBuilder._();

  // ── Segment separators ────────────────────────────────────────────────────

  static const _sep = '~';
  static const _fmtPrefix = 'fmt:';
  static const _srcPrefix = 'src:';

  // ── Public factories ──────────────────────────────────────────────────────

  /// Builds a key for a NORAD-catalog-ID query.
  ///
  /// [noradId] must be positive (1–999 999 999).
  /// [format] selects the wire format segment.
  /// [source] defaults to [TleSource.celestrak].
  static String forNoradId(
    int noradId, {
    required CelestrakFormat format,
    TleSource source = TleSource.celestrak,
  }) {
    if (noradId <= 0) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'must be positive',
      );
    }
    return _build('norad:$noradId', format, source);
  }

  /// Builds a key for a named satellite query.
  ///
  /// [name] is normalised to lower-case; whitespace is collapsed and replaced
  /// with underscores so the key remains filename-safe. Special characters
  /// outside `[a-z0-9:_\-~]` are stripped.
  ///
  /// **Collision caveat:** names that differ only in stripped characters map to
  /// the same cache key. For example, `"ISS (ZARYA)"` and `"ISS ZARYA"` both
  /// produce `"name:iss_zarya~..."`. CelesTrak performs a substring match, so
  /// these queries may return different results — callers who query both names
  /// within the same TTL window will receive the first call's cached response
  /// for the second call.
  static String forName(
    String name, {
    required CelestrakFormat format,
    TleSource source = TleSource.celestrak,
  }) {
    final normalised = _normalise(name);
    return _build('name:$normalised', format, source);
  }

  /// Builds a key for a [SatelliteCategory] group query.
  static String forCategory(
    SatelliteCategory category, {
    required CelestrakFormat format,
    TleSource source = TleSource.celestrak,
  }) =>
      _build('group:${_normalise(category.group)}', format, source);

  /// Builds a key for an arbitrary group-string query.
  ///
  /// [group] is normalised identically to [forCategory].
  static String forGroup(
    String group, {
    required CelestrakFormat format,
    TleSource source = TleSource.celestrak,
  }) =>
      _build('group:${_normalise(group)}', format, source);

  /// Builds a key for an international-designator query.
  ///
  /// [intlDes] is normalised (lower-cased, hyphens preserved).
  static String forIntlDesignator(
    String intlDes, {
    required CelestrakFormat format,
    TleSource source = TleSource.celestrak,
  }) =>
      _build('intdes:${_normalise(intlDes)}', format, source);

  // ── Internal helpers ──────────────────────────────────────────────────────

  static String _build(
    String querySegment,
    CelestrakFormat format,
    TleSource source,
  ) {
    final key = '$querySegment'
        '$_sep$_fmtPrefix${_normalise(format.name)}'
        '$_sep$_srcPrefix${_normalise(source.name)}';
    _assertValid(key);
    return key;
  }

  /// Normalises a string segment: lower-case, replace spaces with `_`,
  /// strip characters outside `[a-z0-9:_\-~]`.
  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(' ', '_').replaceAll(_invalidChars, '');

  /// Throws [ArgumentError] if [key] contains any character that would be
  /// rejected by `CacheStore.validateKey` plus the `~` separator used here.
  static void _assertValid(String key) {
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Derived cache key contains invalid characters.',
      );
    }
  }
}
