import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The address flow is the one screen shaped entirely by where this is being used.
/// Streets here are not numbered and the map data is thin, so the picker asks for what
/// people actually say: the zone, then the landmark, then the detail.
void main() {
  const zones = [
    Zone(id: 'maamoura', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
    Zone(id: 'shatt', cityId: 'edku', name: 'الشط', defaultDeliveryFee: 1500),
  ];

  const landmarks = [
    // Pinned, because the map layer draws only landmarks that carry a coordinate —
    // and because a pin that reaches nothing beyond the customer's own screen is the
    // thing these tests exist to prevent.
    Landmark(id: 'l1', cityId: 'edku', zoneId: 'maamoura', name: 'صيدلية النور',
        lat: 31.3084, lng: 30.2939),
    Landmark(id: 'l2', cityId: 'edku', zoneId: 'maamoura', name: 'مسجد الفتح'),
    Landmark(id: 'l3', cityId: 'edku', zoneId: 'shatt', name: 'موقف التوك توك'),
  ];

  Future<void> pumpPicker(WidgetTester tester, {
    Address? initial, ValueChanged<Address>? onSaved,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(zones: zones, landmarks: landmarks),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Scaffold(
            body: AddressPicker(
              initial: initial,
              onSaved: onSaved ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the zones the admin defined', (tester) async {
    await pumpPicker(tester);
    expect(find.text('المعمورة'), findsOneWidget);
    expect(find.text('الشط'), findsOneWidget);
  });

  // A landmark list that ignores the chosen zone is a list of places on the other side of
  // town, which is worse than no list.
  testWidgets('shows only the landmarks in the chosen zone', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();

    expect(find.text('صيدلية النور'), findsOneWidget);
    expect(find.text('مسجد الفتح'), findsOneWidget);
    expect(find.text('موقف التوك توك'), findsNothing);
  });

  testWidgets('changing the zone changes the landmarks', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الشط'));
    await tester.pumpAndSettle();

    expect(find.text('صيدلية النور'), findsNothing);
    expect(find.text('موقف التوك توك'), findsOneWidget);
  });

  // The admin's list will never be complete, and a customer whose landmark is missing
  // must not be stuck.
  testWidgets('lets the customer name a landmark that is not on the list',
      (tester) async {
    Address? saved;
    await pumpPicker(tester, onSaved: (a) => saved = a);
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();

    expect(find.byKey(AddressPicker.landmarkNoteKey), findsNothing);
    expect(find.byKey(AddressPicker.otherLandmarkKey), findsOneWidget);

    await tester.tap(find.byKey(AddressPicker.otherLandmarkKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AddressPicker.landmarkNoteKey), findsOneWidget);
    expect(tester.widget<LuqmaChip>(find.byKey(AddressPicker.otherLandmarkKey)).dashed,
      isTrue);
    await tester.enterText(find.byKey(AddressPicker.landmarkNoteKey), 'جنب المكتبة');
    await tester.tap(find.byKey(AddressPicker.saveKey));
    expect(saved!.landmarkNote, 'جنب المكتبة');
    expect(saved!.landmarkId, isNull);
    expect(saved!.landmarkName, isNull);
  });

  testWidgets('will not save without a zone', (tester) async {
    await pumpPicker(tester);
    expect(find.text('اختر المنطقة'), findsOneWidget);

    await tester.tap(find.byKey(AddressPicker.saveKey));
    await tester.pumpAndSettle();

    expect(find.text('اختر المنطقة'), findsOneWidget);
  });

  testWidgets('saves what was chosen', (tester) async {
    Address? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(zones: zones, landmarks: landmarks),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Scaffold(body: AddressPicker(onSaved: (a) => saved = a)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صيدلية النور'));
    await tester.enterText(find.byKey(AddressPicker.buildingKey), '12');
    await tester.tap(find.byKey(AddressPicker.saveKey));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.zoneId, 'maamoura');
    expect(saved!.landmarkId, 'l1');
    expect(saved!.landmarkName, 'صيدلية النور');
    expect(saved!.building, '12');
  });

  testWidgets('an existing address comes back filled in', (tester) async {
    await pumpPicker(
      tester,
      initial: const Address(
        id: 'a1',
        zoneId: 'shatt',
        landmarkId: 'l3',
        landmarkName: 'موقف التوك توك',
        building: '7',
      ),
    );

    expect(find.text('موقف التوك توك'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(AddressPicker.buildingKey)).initialValue,
      '7',
    );
  });

  testWidgets('the shared form never invents a delivery quote', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('الشط'));
    await tester.pumpAndSettle();
    expect(find.textContaining('التوصيل للمنطقة دي:'), findsNothing);
    expect(find.textContaining('15 ج'), findsNothing);
  });

  testWidgets('zone and landmark chips have full touch targets', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();
    expect(find.byType(LuqmaChip), findsNWidgets(5));
    for (final chip in find.byType(LuqmaChip).evaluate()) {
      final size = tester.getSize(find.byWidget(chip.widget));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
  });

  // Choosing a zone inserts the landmark section between the zone chips and the detail
  // fields. Unkeyed, Flutter matches the old details entrance against the new landmark
  // one and recycles it, so every field is rebuilt from `initialValue` — which is only
  // assigned in `onSaved` and is therefore empty. Somebody who typed their street first
  // watched it disappear the moment they answered the question above it.
  //
  // Breaks if any of the three `ValueKey`s on the section entrances is removed.
  testWidgets('what was typed survives choosing a zone above it', (tester) async {
    await pumpPicker(tester);
    await tester.enterText(find.byKey(AddressPicker.streetKey), 'شارع البحر');
    await tester.pumpAndSettle();
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();
    expect(find.text('شارع البحر'), findsOneWidget);
  });
  // The map is a slot above the form, and it can write to it: pressing a pin is meant to
  // be the same act as pressing a landmark's chip. A slot that could only read would be a
  // second way of saying something the form never hears.
  testWidgets('the top slot chooses a landmark, and the choice reaches the address',
      (tester) async {
    Address? saved;
    AddressPickerSelection? seen;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(zones: zones, landmarks: landmarks),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          supportedLocales: LuqmaStrings.supportedLocales,
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          home: Scaffold(
            body: AddressPicker(
              onSaved: (a) => saved = a,
              top: (zone, selection) {
                seen = selection;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();

    // The slot is handed this zone's landmarks, not every landmark in the city.
    expect(seen!.landmarks.map((l) => l.zoneId).toSet(), {'maamoura'});
    expect(seen!.landmarkId, isNull);

    seen!.choose('l1');
    await tester.pumpAndSettle();

    // The form now agrees: the slot's choice is the chip's choice.
    expect(seen!.landmarkId, 'l1');

    await tester.enterText(find.byKey(AddressPicker.buildingKey), '12');
    await tester.tap(find.byKey(AddressPicker.saveKey));
    await tester.pumpAndSettle();

    expect(saved!.landmarkId, 'l1');
  });

  /// Where a coordinate comes from, and how far it gets.
  ///
  /// The columns exist, the repository writes them, and the form never put a value in
  /// either — so every address in the product had a null pin, and the map, the courier's
  /// maps app and the order snapshot were all reading a coordinate nothing ever set.
  group('the pin on a saved address', () {
    testWidgets("is the chosen landmark's, so it can reach the courier",
        (tester) async {
      Address? saved;
      await pumpPicker(tester, onSaved: (a) => saved = a);
      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('صيدلية النور'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(saved!.lat, 31.3084);
      expect(saved!.lng, 30.2939);
    });

    // Most of the city's landmarks have no coordinate yet, and inventing one would put a
    // marker on a guess. Words are the primary address here; the pin is the supporting
    // layer.
    testWidgets('is nothing when the landmark has none', (tester) async {
      Address? saved;
      await pumpPicker(tester, onSaved: (a) => saved = a);
      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مسجد الفتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(saved!.lat, isNull);
      expect(saved!.lng, isNull);
    });

    // Editing the floor must not silently unpin the address. The form rebuilt the whole
    // model from its own fields, so everything it did not ask about was dropped.
    testWidgets('survives an edit that does not touch the landmark', (tester) async {
      Address? saved;
      await pumpPicker(
        tester,
        initial: const Address(
          id: 'a1',
          zoneId: 'maamoura',
          landmarkNote: 'قدام الفرن',
          lat: 31.31,
          lng: 30.29,
        ),
        onSaved: (a) => saved = a,
      );
      await tester.enterText(find.byKey(AddressPicker.floorKey), '3');
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(saved!.floor, '3');
      expect(saved!.lat, 31.31);
    });

    // And moving to a different landmark moves the pin with it. A coordinate left over
    // from the place somebody used to live next to sends the courier there.
    testWidgets('is cleared when the landmark changes to an unpinned one',
        (tester) async {
      Address? saved;
      await pumpPicker(
        tester,
        initial: const Address(
          id: 'a1',
          zoneId: 'maamoura',
          landmarkId: 'l1',
          landmarkName: 'صيدلية النور',
          lat: 31.3084,
          lng: 30.2939,
        ),
        onSaved: (a) => saved = a,
      );
      await tester.tap(find.text('مسجد الفتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(saved!.landmarkId, 'l2');
      expect(saved!.lat, isNull, reason: 'the old pin is not this landmark');
    });
  });
}
