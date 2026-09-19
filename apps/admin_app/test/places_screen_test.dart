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
    List<Zone> customZones = zones,
    List<Landmark> customLandmarks = landmarks,
    List<LandmarkNote> notes = const [],
    Failure? failure,
    Size size = const Size(1080, 2340),
    double devicePixelRatio = 3.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);

    repository = FakeGeographyRepository(
      zones: customZones,
      landmarks: customLandmarks,
      notes: notes,
      failure: failure,
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

    testWidgets('عدّل واقبل opens the landmark form prefilled', (tester) async {
      await pump(tester, notes: notes);
      await openSuggestions(tester);

      await tester.tap(find.byKey(const Key('places.editAccept.صيدلية النور')));
      await tester.pumpAndSettle();

      expect(find.text('علامة جديدة'), findsOneWidget);
      expect(find.text('صيدلية النور'), findsWidgets);
    });
  });

  group('QA review findings', () {
    testWidgets('blocking landmark creation until a zone exists', (tester) async {
      await pump(tester, customZones: const [], customLandmarks: const []);

      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();
      expect(find.text('ضيف منطقة الأول'), findsOneWidget);

      await tester.tap(find.byKey(PlacesScreen.addLandmarkKey));
      await tester.pumpAndSettle();

      expect(find.text('ضيف منطقة الأول'), findsWidgets);
      expect(find.text('إضافة منطقة'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'إضافة منطقة').last);
      await tester.pumpAndSettle();

      expect(find.text('منطقة جديدة'), findsOneWidget);
    });

    testWidgets('deleting landmark requires confirmation naming it and consequences', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('مسجد الفتح'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('احذف'));
      await tester.pumpAndSettle();

      expect(find.text('حذف مسجد الفتح'), findsOneWidget);
      expect(
        find.textContaining('العناوين اللي استخدمتها هتحتفظ بالنص لكن هتفقد ربط العلامة'),
        findsOneWidget,
      );

      // Cancelling keeps the landmark. The form under the question has its own «إلغاء»,
      // so the one meant is the question's — the last one built.
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();
      expect(find.text('تعديل العلامة'), findsOneWidget);

      // Confirming deletes it
      await tester.tap(find.text('احذف'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'حذف'));
      await tester.pumpAndSettle();

      final saved = (await repository.landmarks(cityId: 'edku')).valueOrNull!;
      expect(saved.map((l) => l.name), isNot(contains('مسجد الفتح')));
    });

    testWidgets('zone card is collapsible when having more than 8 landmarks', (tester) async {
      final manyLandmarks = List.generate(
        10,
        (i) => Landmark(id: 'l$i', cityId: 'edku', zoneId: 'z1', name: 'علامة $i'),
      );
      await pump(tester, customLandmarks: manyLandmarks);

      expect(find.text('10 علامة'), findsOneWidget);
      expect(find.text('📍 علامة 0'), findsNothing);

      await tester.tap(find.text('10 علامة'));
      await tester.pumpAndSettle();

      expect(find.text('📍 علامة 0'), findsOneWidget);
      expect(find.text('إخفاء (10)'), findsOneWidget);
    });

    testWidgets('search field filters landmarks in landmarks tab', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      expect(find.text('مسجد الفتح'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'مستشفى');
      await tester.pumpAndSettle();

      expect(find.text('مسجد الفتح'), findsNothing);
    });

    testWidgets('saving zone keeps form open on failure', (tester) async {
      await pump(tester);
      // The screen loads; only the write that follows fails.
      repository.failure = const OfflineFailure();

      await tester.tap(find.byKey(PlacesScreen.addZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(PlacesScreen.nameFieldKey), 'منطقة تجريبية');
      await tester.enterText(find.byKey(PlacesScreen.feeFieldKey), '15');
      await tester.tap(find.byKey(PlacesScreen.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('منطقة جديدة'), findsOneWidget);
      expect(find.text('فشل الحفظ، حاول مرة أخرى'), findsOneWidget);
    });

    testWidgets('saving landmark keeps form open on failure', (tester) async {
      await pump(tester);
      // The screen loads; only the write that follows fails.
      repository.failure = const OfflineFailure();

      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PlacesScreen.addLandmarkKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(PlacesScreen.nameFieldKey), 'علامة فاشلة');
      await tester.tap(find.byKey(PlacesScreen.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('علامة جديدة'), findsOneWidget);
      expect(find.text('فشل الحفظ، حاول مرة أخرى'), findsOneWidget);
    });

    testWidgets('deleting landmark failure keeps form open and shows error', (tester) async {
      await pump(tester);
      // The screen loads; only the write that follows fails.
      repository.failure = const OfflineFailure();

      await tester.tap(find.byKey(PlacesScreen.landmarksTabKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('مسجد الفتح'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('احذف'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'حذف'));
      await tester.pumpAndSettle();

      expect(find.text('تعديل العلامة'), findsOneWidget);
      expect(find.text('فشل الحذف'), findsOneWidget);
    });

    testWidgets('zone card with <= 8 landmarks can be collapsed and expanded', (tester) async {
      await pump(tester);

      // Initially expanded
      expect(find.text('📍 مسجد الفتح'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('1 علامة'));
      await tester.pumpAndSettle();

      expect(find.text('📍 مسجد الفتح'), findsNothing);

      // Tap to expand again
      await tester.tap(find.text('1 علامة'));
      await tester.pumpAndSettle();

      expect(find.text('📍 مسجد الفتح'), findsOneWidget);
    });
  });
}

