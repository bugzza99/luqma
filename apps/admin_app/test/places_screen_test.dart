import 'package:admin_app/src/places/places_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The screen where Edku's addressing layer is maintained.
///
/// Its third tab is the point: the owner cannot write the landmark list in advance, and
/// neither can anyone. It gets built from what customers type when the list does not have
/// theirs, so every order that had to be described by hand is a place the map is missing.
void main() {
  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
    Zone(id: 'z2', cityId: 'edku', name: 'الشط', defaultDeliveryFee: 1500),
  ];

  const landmarks = [
    Landmark(id: 'l1', cityId: 'edku', zoneId: 'z1', name: 'مسجد الفتح'),
  ];

  late FakeGeographyRepository repository;

  Future<void> pump(
    WidgetTester tester, {
    List<LandmarkNote> notes = const [],
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repository = FakeGeographyRepository(
      zones: zones,
      landmarks: landmarks,
      notes: notes,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [geographyRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: PlacesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('zones', () {
    testWidgets('are listed with their delivery fee', (tester) async {
      await pump(tester);

      expect(find.text('المعمورة'), findsWidgets);
      expect(find.text('15 ج'), findsOneWidget);
    });

    testWidgets('a new one can be added', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(PlacesScreen.addZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(PlacesScreen.nameFieldKey), 'بحري');
      await tester.enterText(find.byKey(PlacesScreen.feeFieldKey), '12');
      await tester.tap(find.byKey(PlacesScreen.saveKey));
      await tester.pumpAndSettle();

      final saved = (await repository.zones(cityId: 'edku')).valueOrNull!;
      expect(saved.map((z) => z.name), contains('بحري'));
      expect(
        saved.firstWhere((z) => z.name == 'بحري').defaultDeliveryFee,
        1200,
        reason: 'typed in pounds, stored in piastres',
      );
    });
  });

  group('landmarks', () {
    testWidgets('are listed under the zone they belong to', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      expect(find.text('مسجد الفتح'), findsOneWidget);
    });

    testWidgets('a new one can be added to a zone', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PlacesScreen.addLandmarkKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(PlacesScreen.nameFieldKey), 'صيدلية النور');
      await tester.tap(find.byKey(PlacesScreen.saveKey));
      await tester.pumpAndSettle();

      final saved = (await repository.landmarks(cityId: 'edku')).valueOrNull!;
      expect(saved.map((l) => l.name), contains('صيدلية النور'));
    });
  });

  group('the places customers named themselves', () {
    const notes = [
      LandmarkNote(zoneId: 'z1', text: 'صيدلية النور'),
      LandmarkNote(zoneId: 'z1', text: 'صيدليه النور'),
      LandmarkNote(zoneId: 'z1', text: 'صيدلية النور'),
      LandmarkNote(zoneId: 'z2', text: 'كافيه الركن'),
      LandmarkNote(zoneId: 'z2', text: 'كافيه الركن'),
    ];

    Future<void> openSuggestions(WidgetTester tester) async {
      await tester.tap(find.byKey(PlacesScreen.suggestionsTabKey));
      await tester.pumpAndSettle();
    }

    testWidgets('are listed with how often they were typed', (tester) async {
      await pump(tester, notes: notes);
      await openSuggestions(tester);

      expect(find.text('صيدلية النور'), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
    });

    // The spellings folded together, so the owner sees one pharmacy rather than two
    // entries that each look too rare to bother with.
    testWidgets('spellings of one place are one row', (tester) async {
      await pump(tester, notes: notes);
      await openSuggestions(tester);

      expect(find.text('صيدليه النور'), findsNothing);
    });

    testWidgets('accepting one adds it as a landmark', (tester) async {
      await pump(tester, notes: notes);
      await openSuggestions(tester);

      await tester.tap(find.byKey(PlacesScreen.acceptSuggestionKey('صيدلية النور')));
      await tester.pumpAndSettle();

      final saved = (await repository.landmarks(cityId: 'edku')).valueOrNull!;
      final added = saved.firstWhere((l) => l.name == 'صيدلية النور');
      expect(added.zoneId, 'z1', reason: 'the zone it was typed in');
    });

    testWidgets('an accepted suggestion stops being suggested', (tester) async {
      await pump(tester, notes: notes);
      await openSuggestions(tester);

      await tester.tap(find.byKey(PlacesScreen.acceptSuggestionKey('صيدلية النور')));
      await tester.pumpAndSettle();

      expect(find.text('صيدلية النور'), findsNothing);
      expect(find.text('كافيه الركن'), findsOneWidget, reason: 'the rest remain');
    });

    testWidgets('says so plainly when there is nothing to review', (tester) async {
      await pump(tester);
      await openSuggestions(tester);

      expect(find.byKey(PlacesScreen.noSuggestionsKey), findsOneWidget);
    });
  });
}
