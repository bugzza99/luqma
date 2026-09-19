import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  testWidgets('swatches have Arabic semantic labels and announce selection', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => BannerColorPicker(
                selected: picked,
                onPicked: (color) => setState(() => picked = color),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check gradient swatch label
    expect(find.byKey(BannerColorPicker.gradientKey), findsOneWidget);
    final gradientSemantics = tester.getSemantics(find.byKey(BannerColorPicker.gradientKey));
    expect(gradientSemantics.label, equals('تدرّج'));

    // Check Arabic names for all swatches
    final expectedNames = {
      '#761812': 'عنابي',
      '#451410': 'بني غامق',
      '#D67F2B': 'برتقالي',
      '#F5EBE2': 'كريمي',
      '#1B4332': 'أخضر',
      '#0E3A5C': 'أزرق',
      '#130B07': 'أسود',
      '#8C1C4A': 'توتي',
    };

    for (final entry in expectedNames.entries) {
      final key = BannerColorPicker.swatchKey(entry.key);
      expect(find.byKey(key), findsOneWidget);
      final semantics = tester.getSemantics(find.byKey(key));
      expect(semantics.label, equals(entry.value));
    }

    // Tap a swatch and verify onPicked
    await tester.tap(find.byKey(BannerColorPicker.swatchKey('#761812')));
    await tester.pumpAndSettle();

    expect(picked, equals('#761812'));
  });
}
