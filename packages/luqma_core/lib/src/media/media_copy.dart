/// The small copy beside every picture, named after it (20261101340000).
///
/// Every image was one 1600px JPEG, ~200 KB, and a menu thumbnail drawn 78 points wide
/// downloaded all of it. Since then every upload writes a 400px copy next to the
/// photograph, at the same name with `_s` before the extension, and lists and thumbnails
/// draw that instead. The copy has no `media` row of its own: the server finds it by this
/// same rule — to keep it with its photograph and to sweep it with an orphan — so the rule
/// is written once, here, for the phone that uploads it and the phone that draws it.
abstract final class MediaCopy {
  const MediaCopy._();

  static const _suffix = '_s';

  /// The small copy's public address, for a photograph's.
  static String small(String url) {
    final query = url.indexOf('?');
    final base = query < 0 ? url : url.substring(0, query);
    final rest = query < 0 ? '' : url.substring(query);
    return '${smallPath(base)}$rest';
  }

  /// The small copy's object path, for a photograph's.
  static String smallPath(String path) {
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$_suffix';
    return '${path.substring(0, dot)}$_suffix${path.substring(dot)}';
  }
}
