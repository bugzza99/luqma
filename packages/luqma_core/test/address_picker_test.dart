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
    Landmark(id: 'l1', cityId: 'edku', zoneId: 'maamoura', name: 'صيدلية النور'),
    Landmark(id: 'l2', cityId: 'edku', zoneId: 'maamoura', name: 'مسجد الفتح'),
    Landmark(id: 'l3', cityId: 'edku', zoneId: 'shatt', name: 'موقف التوك توك'),
  ];

  Future<Address?> pumpPicker(WidgetTester tester, {Address? initial}) async {
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
          home: Scaffold(
            body: AddressPicker(
              initial: initial,
              onSaved: (address) => saved = address,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return saved;
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
    await pumpPicker(tester);
    await tester.tap(find.text('المعمورة'));
    await tester.pumpAndSettle();

    expect(find.byKey(AddressPicker.otherLandmarkKey), findsOneWidget);

    await tester.tap(find.byKey(AddressPicker.otherLandmarkKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AddressPicker.landmarkNoteKey), findsOneWidget);
  });

  testWidgets('will not save without a zone', (tester) async {
    await pumpPicker(tester);

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

  // The fee is a property of the destination, so it is shown while the customer is still
  // choosing rather than sprung on them at checkout.
  testWidgets('shows the delivery fee for the chosen zone', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.text('الشط'));
    await tester.pumpAndSettle();

    expect(find.textContaining('15'), findsWidgets);
  });
}
