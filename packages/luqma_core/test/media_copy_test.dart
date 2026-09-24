import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The small copy beside every picture, named after it (20261101340000).
///
/// The server finds a copy by this same rule — `_s` before the extension — to keep it
/// with its photograph and to sweep it with an orphan. Written once here so the phone that
/// uploads it and the phone that draws it cannot disagree about where it is.
void main() {
  const photo =
      'https://x.supabase.co/storage/v1/object/public/media/u1/menuItem/abc.jpg';

  test('is the photograph with _s before the extension', () {
    expect(MediaCopy.small(photo),
        'https://x.supabase.co/storage/v1/object/public/media/u1/menuItem/abc_s.jpg');
  });

  test('has a path of the same shape', () {
    expect(MediaCopy.smallPath('u1/menuItem/abc.jpg'), 'u1/menuItem/abc_s.jpg');
  });

  test('a name with no extension gets the suffix at the end', () {
    expect(MediaCopy.small('https://x.test/media/abc'), 'https://x.test/media/abc_s');
  });

  test('a query string is left where it is', () {
    expect(MediaCopy.small('https://x.test/media/abc.jpg?v=2'),
        'https://x.test/media/abc_s.jpg?v=2');
  });
}
