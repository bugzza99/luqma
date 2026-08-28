import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every icon-only control in the three apps has to say what it is.
///
/// A screen reader announces a bare `IconButton` as "button" and nothing else, so a
/// customer who cannot see the little bin icon has no way to know which of the two
/// controls beside a basket line removes it. Nine of the thirteen in the product were
/// silent before this test existed.
///
/// Written as a scan over the source rather than a pump of every screen, because the
/// thing being guarded is a habit, not a screen: the next `IconButton` anybody adds is
/// the one this has to catch, and no widget test covers a screen that does not exist yet.
void main() {
  // The suite runs from `packages/luqma_core`.
  final appsDir = Directory('../../apps');

  /// Source files, minus anything a generator wrote.
  ///
  /// Each app's `lib` and nothing else: walking the app directories whole drags in
  /// `build/`, where Gradle leaves paths long enough that listing them throws.
  List<File> dartSources() => appsDir
      .listSync()
      .whereType<Directory>()
      .map((app) => Directory('${app.path}/lib'))
      .where((lib) => lib.existsSync())
      .expand((lib) => lib.listSync(recursive: true))
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .toList();

  test('the apps directory is where this test thinks it is', () {
    expect(appsDir.existsSync(), isTrue,
        reason: 'run from packages/luqma_core, as the workspace scripts do');
    expect(dartSources(), isNotEmpty);
  });

  test('no IconButton ships without a tooltip', () {
    final offenders = <String>[];

    for (final file in dartSources()) {
      final source = file.readAsStringSync();
      var from = 0;

      while (true) {
        final start = source.indexOf('IconButton(', from);
        if (start == -1) break;
        from = start + 1;

        // The argument list, found by matching the bracket rather than by counting
        // lines: these calls are wrapped across five or six of them.
        var depth = 0;
        var i = source.indexOf('(', start);
        final open = i;
        while (i < source.length) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') {
            depth--;
            if (depth == 0) break;
          }
          i++;
        }

        final args = source.substring(open, i + 1);
        if (!args.contains('tooltip:')) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'an icon with no tooltip is announced as "button" and nothing more:\n'
          '${offenders.join('\n')}',
    );
  });
}
