import 'package:customer_app/src/address/address_editor_screen.dart';
import 'package:customer_app/src/address/address_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Choosing and keeping an address.
///
/// A courier reads the zone first and the landmark second, which is why those two are
/// what the list shows — never a street number nobody uses.
void main() {
  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
    Zone(id: 'z2', cityId: 'edku', name: 'الشط', defaultDeliveryFee: 1500),
  ];
  const landmarks = [
    Landmark(id: 'lm1', cityId: 'edku', zoneId: 'z1', name: 'صيدلية النور'),
  ];

  const home = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkId: 'lm1',
    landmarkName: 'صيدلية النور',
    building: '12',
    label: 'البيت',
  );
  const work = Address(id: 'a2', zoneId: 'z2', label: 'الشغل');

  late ProviderContainer container;
  late FakeAddressRepository addresses;

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    LuqmaIdentity? signedInAs = const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
    List<Address> seed = const [home, work],
  }) async {
    addresses = FakeAddressRepository(
      seed: signedInAs == null ? const {} : {signedInAs.uid: seed},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          addressRepositoryProvider.overrideWithValue(addresses),
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(zones: zones, landmarks: landmarks),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Directionality(
                textDirection: TextDirection.rtl,
                child: screen,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('shows every address by the parts a courier reads', (tester) async {
      await pump(tester, const AddressListScreen());

      expect(find.text('البيت'), findsOneWidget);
      // The zone and the landmark, not the building number.
      expect(find.textContaining('المعمورة'), findsWidgets);
      expect(find.textContaining('صيدلية النور'), findsWidgets);
    });

    testWidgets('marks which one an order would go to', (tester) async {
      await pump(tester, const AddressListScreen());

      expect(find.byKey(AddressListScreen.chosenKey('a1')), findsOneWidget);
      expect(find.byKey(AddressListScreen.chosenKey('a2')), findsNothing);
    });

    testWidgets('choosing another one moves the mark', (tester) async {
      await pump(tester, const AddressListScreen());

      await tester.tap(find.byKey(AddressListScreen.rowKey('a2')));
      await tester.pumpAndSettle();

      expect(find.byKey(AddressListScreen.chosenKey('a2')), findsOneWidget);
      expect(
        (await addresses.defaultAddressId('u1')).valueOrNull,
        'a2',
      );
    });

    testWidgets('a customer with no addresses is offered one, not an error',
        (tester) async {
      await pump(tester, const AddressListScreen(), seed: []);

      expect(find.byKey(AddressListScreen.emptyKey), findsOneWidget);
      expect(find.byKey(AddressListScreen.addKey), findsOneWidget);
    });

    // Browsing signed out is normal here; the account is asked for when it is needed.
    testWidgets('signed out, it asks for an account instead of showing nothing',
        (tester) async {
      await pump(tester, const AddressListScreen(), signedInAs: null);

      expect(find.byKey(AddressListScreen.signInKey), findsOneWidget);
      expect(find.byKey(AddressListScreen.addKey), findsNothing);
    });
  });

  group('deleting', () {
    testWidgets('asks first', (tester) async {
      await pump(tester, const AddressListScreen());

      await tester.tap(find.byKey(AddressListScreen.deleteKey('a2')));
      await tester.pumpAndSettle();

      expect(find.byKey(AddressListScreen.confirmDeleteKey), findsOneWidget);
      expect((await addresses.addresses('u1')).valueOrNull, hasLength(2));
    });

    testWidgets('confirming removes it', (tester) async {
      await pump(tester, const AddressListScreen());

      await tester.tap(find.byKey(AddressListScreen.deleteKey('a2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressListScreen.confirmDeleteKey));
      await tester.pumpAndSettle();

      expect(find.text('الشغل'), findsNothing);
      expect((await addresses.addresses('u1')).valueOrNull, hasLength(1));
    });
  });

  group('the editor', () {
    testWidgets('a new address saves and comes back with its label', (tester) async {
      await pump(tester, const AddressEditorScreen(), seed: []);

      await tester.enterText(
        find.byKey(AddressEditorScreen.labelKey),
        'بيت ماما',
      );
      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      final saved = (await addresses.addresses('u1')).valueOrNull!;
      expect(saved.single.label, 'بيت ماما');
      expect(saved.single.zoneId, 'z1');
    });

    // The zone prices the delivery and decides which merchants can even take the order.
    testWidgets('refuses to save without a zone', (tester) async {
      await pump(tester, const AddressEditorScreen(), seed: []);

      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect((await addresses.addresses('u1')).valueOrNull, isEmpty);
    });

    testWidgets('editing an existing address does not create a second one',
        (tester) async {
      await pump(tester, const AddressEditorScreen(initial: home));

      await tester.enterText(
        find.byKey(AddressEditorScreen.labelKey),
        'البيت الجديد',
      );
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      final saved = (await addresses.addresses('u1')).valueOrNull!;
      expect(saved, hasLength(2));
      expect(saved.firstWhere((a) => a.id == 'a1').label, 'البيت الجديد');
    });

    // Leaving it open after a successful save makes the customer wonder whether it
    // saved, and tap again.
    testWidgets('a saved address closes the editor', (tester) async {
      await pump(tester, const AddressListScreen(), seed: []);

      await tester.tap(find.byKey(AddressListScreen.addKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AddressEditorScreen.labelKey), findsOneWidget);

      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AddressEditorScreen.labelKey), findsNothing);
      expect((await addresses.addresses('u1')).valueOrNull, hasLength(1));
    });
  });

  group('when saving fails', () {
    testWidgets('it says so and keeps what was typed', (tester) async {
      await pump(tester, const AddressEditorScreen(), seed: []);
      // Swapped after the screen is up, so the failure happens on the save itself.
      container.updateOverrides([
        authServiceProvider.overrideWithValue(
          FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
        ),
        addressRepositoryProvider.overrideWithValue(
          FakeAddressRepository(failure: const OfflineFailure()),
        ),
        geographyRepositoryProvider.overrideWithValue(
          FakeGeographyRepository(zones: zones, landmarks: landmarks),
        ),
        remoteConfigServiceProvider
            .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
      ]);

      await tester.enterText(
        find.byKey(AddressEditorScreen.labelKey),
        'بيت ماما',
      );
      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddressPicker.saveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AddressEditorScreen.errorKey), findsOneWidget);
      // Sending somebody back to a blank form after a failed save is the app losing
      // their work on its own behalf.
      expect(find.text('بيت ماما'), findsOneWidget);
    });
  });
}
