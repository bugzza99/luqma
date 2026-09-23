import 'dart:async';

import 'package:admin_app/src/customers/customer_detail_screen.dart';
import 'package:admin_app/src/customers/customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// العملاء — searching, blocking, customer detail, and a password reset that asks first.
///
/// A customer who forgets their password calls support. Before generating a new password,
/// the admin sees the customer's last order and saved address to verify their identity.
void main() {
  late FakeCustomerRepository customers;
  late FakeAddressRepository addresses;
  late FakeGeographyRepository geography;
  late FakeExternalLinks externalLinks;
  late FakeAdminRepository adminRepo;

  final fixedClock = DateTime(2026, 8, 27, 12);

  final ahmed = CustomerSummary(
    id: 'u1',
    name: 'أحمد محمود',
    phone: '01012345678',
    isBlocked: false,
    rejectedOrdersCount: 0,
    createdAt: DateTime(2026, 8, 1),
  );

  final salma = CustomerSummary(
    id: 'u2',
    name: 'سلمى علي',
    phone: '01098765432',
    isBlocked: false,
    rejectedOrdersCount: 0,
    createdAt: DateTime(2026, 8, 20),
  );

  final ahmedOrder = Order(
    id: 'o1',
    cityId: 'edku',
    orderNumber: 1247,
    customerUid: 'u1',
    customerName: 'أحمد محمود',
    customerPhone: '01012345678',
    merchantId: 'm1',
    merchantName: 'كوشري التحرير',
    zoneId: 'z1',
    type: OrderType.instant,
    status: OrderStatus.delivered,
    placedAt: DateTime(2026, 8, 27, 10),
    items: const [],
    pricing: const OrderPricing(
      subtotal: 10000,
      deliveryFee: 2000,
      total: 12000,
    ),
  );

  final ahmedAddress = const Address(
    id: 'a1',
    zoneId: 'z1',
    street: 'ش. الجيش',
    building: '15',
    floor: '3',
    apartment: '6',
  );

  const phoneSize = Size(412, 892);
  const wideSize = Size(1200, 800);

  Future<void> pump(
    WidgetTester tester, {
    Failure? failure,
    Size size = phoneSize,
    bool linkAnswer = true,
    List<CustomerSummary>? seed,
    StaffIdentity? who,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    customers = FakeCustomerRepository(
      seed: seed ?? [ahmed, salma],
      histories: {'u1': [ahmedOrder], 'u2': []},
      failure: failure,
    );
    addresses = FakeAddressRepository(
      seed: {
        'u1': [ahmedAddress],
        'u2': [],
      },
    );
    adminRepo = FakeAdminRepository(customers: customers);
    geography = FakeGeographyRepository(
      zones: [
        const Zone(
          id: 'z1',
          cityId: 'edku',
          name: 'الشلالات',
          defaultDeliveryFee: 1500,
        ),
      ],
    );
    externalLinks = FakeExternalLinks(answer: linkAnswer);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider.overrideWithValue(customers),
          adminRepositoryProvider.overrideWithValue(adminRepo),
          if (who != null) staffIdentityProvider.overrideWithValue(who),
          addressRepositoryProvider.overrideWithValue(addresses),
          geographyRepositoryProvider.overrideWithValue(geography),
          externalLinksProvider.overrideWithValue(externalLinks),
          clockProvider.overrideWithValue(() => fixedClock),
          // Salma also runs a shop: her staff row says so.
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository(seed: const [
            StaffMember(
                uid: 'u2', scope: 'merchant', role: 'owner', isActive: true, merchantId: 'm1'),
          ])),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CustomersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(CustomersScreen.searchKey), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('a search finds a customer by name and tapping opens customer detail', (tester) async {
    await pump(tester);
    await search(tester, 'أحمد');

    expect(find.text('أحمد محمود'), findsOneWidget);

    // Tapping the customer in the list navigates to the customer detail
    await tester.tap(find.text('أحمد محمود'));
    await tester.pumpAndSettle();

    // Customer detail shows header info
    expect(find.byKey(CustomerDetailScreen.detailKey), findsOneWidget);
    expect(find.text('أحمد محمود'), findsWidgets);
    expect(find.text('01012345678'), findsOneWidget);
    expect(find.text('عضو منذ أغسطس 2026'), findsOneWidget);

    // Mini stats: 1 order, 120 ج total, 0 rejects
    expect(find.text('طلبات'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('إجمالي'), findsOneWidget);
    expect(find.text('120 ج'), findsWidgets);
    expect(find.text('رفض'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  // A shop owner who also orders turned up among customers with nothing to say so
  // (QA review 2026-09-19).
  testWidgets('an account that is also staff says so on its row', (tester) async {
    await pump(tester);
    await search(tester, 'سلمى');

    expect(find.byKey(CustomersScreen.staffNoteKey('u2')), findsOneWidget);
    expect(find.textContaining('صاحب محل'), findsOneWidget);
  });

  testWidgets('renders avatar with initial letter and blocked badge when customer is blocked', (tester) async {
    final blockedCustomer = CustomerSummary(
      id: 'u3',
      name: 'محمود حامد',
      phone: '01011112222',
      isBlocked: true,
      rejectedOrdersCount: 2,
      createdAt: DateTime(2026, 8, 1),
    );
    await pump(tester, seed: [blockedCustomer]);
    await search(tester, 'محمود');

    expect(find.text('محمود حامد'), findsOneWidget);
    expect(find.text('م'), findsOneWidget);
    expect(find.text('محظور'), findsOneWidget);
    expect(find.textContaining('2 رفض'), findsOneWidget);
  });

  group('reset block verification facts', () {
    testWidgets('shows last order and address before password can be generated', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      // Reset block is present
      expect(find.byKey(CustomerDetailScreen.resetBlockKey), findsOneWidget);
      expect(find.byKey(CustomerDetailScreen.verificationFactsKey), findsOneWidget);

      // Facts are shown clearly inside the verification block before the generate button:
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('1247'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('النهارده'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('120 ج'),
        ),
        findsOneWidget,
      );

      // Address: formatted courier-style via Address.format: الشلالات · ش. الجيش · عمارة 15 · الدور 3 · شقة 6
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('الشلالات'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('ش. الجيش'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CustomerDetailScreen.verificationFactsKey),
          matching: find.textContaining('عمارة 15'),
        ),
        findsOneWidget,
      );

      // Typed password fields are present
      expect(find.byKey(CustomerDetailScreen.newPasswordFieldKey), findsOneWidget);
      expect(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), findsOneWidget);
      expect(find.byKey(CustomerDetailScreen.changePasswordKey), findsOneWidget);
      expect(customers.passwordCalls, isEmpty, reason: 'password must not be set yet');
    });

    testWidgets('customer with no orders and no addresses shows plain notice and allows password change', (tester) async {
      await pump(tester);
      await search(tester, 'سلمى');
      await tester.tap(find.text('سلمى علي'));
      await tester.pumpAndSettle();

      // Explains plainly that customer has no prior history or addresses
      expect(find.byKey(CustomerDetailScreen.noVerificationFactsKey), findsOneWidget);
      expect(
        find.text('العميل معندوش طلبات سابقة ولا عناوين محفوظة للتحقق منها.'),
        findsOneWidget,
      );

      expect(find.byKey(CustomerDetailScreen.changePasswordKey), findsOneWidget);
    });
  });

  group('typed password block', () {
    testWidgets('change password button is disabled until both fields match and are 8-72 chars with inline errors', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(CustomerDetailScreen.changePasswordKey);
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

      // Short password (< 8 chars)
      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), '12345');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), '12345');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
      expect(find.textContaining('8 حروف'), findsWidgets);

      // Passwords do not match
      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), 'password123');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'password456');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
      expect(find.textContaining('مش متطابقتين'), findsOneWidget);

      // Matching and >= 8 chars
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'password123');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
      expect(find.textContaining('مش متطابقتين'), findsNothing);
    });

    testWidgets('success calls setPassword with typed value, clears fields, and shows snackbar', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), 'newSecurePass123');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'newSecurePass123');
      await tester.pump();

      await tester.tap(find.byKey(CustomerDetailScreen.changePasswordKey));
      await tester.pumpAndSettle();

      expect(customers.passwordCalls, [('u1', 'newSecurePass123')]);
      expect(find.text('اتغيرت كلمة السر — قولها للعميل'), findsOneWidget);

      // Fields are cleared
      expect(find.text('newSecurePass123'), findsNothing);
    });

    testWidgets('refusal for staff account shows specific message', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      customers.failure = const ConflictFailure();
      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), 'newSecurePass123');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'newSecurePass123');
      await tester.pump();

      await tester.tap(find.byKey(CustomerDetailScreen.changePasswordKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('شاشة الموظفين'), findsOneWidget);
    });

    testWidgets('refusal for permission shows specific message', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      customers.failure = const PermissionFailure();
      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), 'newSecurePass123');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'newSecurePass123');
      await tester.pump();

      await tester.tap(find.byKey(CustomerDetailScreen.changePasswordKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مش مسموح'), findsOneWidget);
    });

    testWidgets('refusal for offline shows specific message', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      customers.failure = const OfflineFailure();
      await tester.enterText(find.byKey(CustomerDetailScreen.newPasswordFieldKey), 'newSecurePass123');
      await tester.enterText(find.byKey(CustomerDetailScreen.confirmPasswordFieldKey), 'newSecurePass123');
      await tester.pump();

      await tester.tap(find.byKey(CustomerDetailScreen.changePasswordKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مفيش نت'), findsOneWidget);
    });
  });

  group('account deletion', () {
    testWidgets('destructive delete button opens confirmation dialog with 3 points in order and confirm calls deleteAccount', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      // Delete button at bottom
      final deleteBtn = find.byKey(CustomerDetailScreen.deleteAccountKey);
      await tester.drag(find.byKey(CustomerDetailScreen.detailKey), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(deleteBtn, findsOneWidget);
      expect(find.text('احذف الحساب'), findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Dialog is displayed with 3 points in order
      expect(find.text('هيتم حذف الحساب وكل العناوين والتقييمات التابعة له.'), findsOneWidget);
      expect(find.text('الطلبات السابقة هتفضل موجودة لحسابات المحلات تحت "حساب محذوف".'), findsOneWidget);
      expect(find.text('مش هتقدر ترجع في الخطوة دي بعد ما تحذف.'), findsOneWidget);

      // Confirm button
      final confirmBtn = find.byKey(CustomerDetailScreen.confirmDeleteAccountKey);
      expect(confirmBtn, findsOneWidget);
      expect(find.text('احذف نهائياً'), findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(adminRepo.deletedAccountCalls, ['u1']);
      expect(find.text('الحساب اتحذف'), findsOneWidget);
    });
  });

  // A9: the server refuses to delete a customer whose order is still on its way, and
  // the snackbar said «حاول تاني» — or, for a permission refusal, a sentence about
  // passwords on a screen about deleting an account.
  // D5: a moderator is refused the password reset (the Edge Function asks for role
  // admin) and the deletion (the database), so neither is drawn for them.
  testWidgets('a moderator is offered neither the password reset nor the delete',
      (tester) async {
    await pump(tester, who: _moderator);
    await search(tester, 'أحمد');
    await tester.tap(find.text('أحمد محمود'));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(CustomerDetailScreen.detailKey), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byKey(CustomerDetailScreen.resetBlockKey, skipOffstage: false), findsNothing);
    expect(find.byKey(CustomerDetailScreen.deleteAccountKey, skipOffstage: false),
        findsNothing);
    expect(find.byKey(CustomerDetailScreen.blockKey, skipOffstage: false), findsOneWidget,
        reason: 'blocking stays theirs');
  });

  group('a refused deletion says why', () {
    Future<void> deleteU1(WidgetTester tester) async {
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(CustomerDetailScreen.detailKey), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomerDetailScreen.deleteAccountKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomerDetailScreen.confirmDeleteAccountKey));
      await tester.pumpAndSettle();
    }

    testWidgets('an order on its way', (tester) async {
      await pump(tester);
      adminRepo.customersWithAnOrderOnItsWay.add('u1');

      await deleteU1(tester);

      expect(find.textContaining('طلب لسه ماوصلش'), findsOneWidget);
      expect(adminRepo.deletedAccountCalls, isEmpty);
    });

    testWidgets('a permission refusal is not about passwords', (tester) async {
      await pump(tester);
      adminRepo.platformStaffUids.add('u1');

      await deleteU1(tester);

      expect(find.text('مش مسموح لك تغيّر كلمة السر.'), findsNothing);
      expect(find.textContaining('مش مسموح لك تحذف'), findsOneWidget);
    });
  });

  group('customer detail actions and layout', () {
    testWidgets('block action toggles blocked status', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      // Block button is present
      expect(find.byKey(CustomerDetailScreen.blockKey), findsOneWidget);
      expect(find.text('حظر العميل'), findsOneWidget);

      await tester.tap(find.byKey(CustomerDetailScreen.blockKey));
      await tester.pumpAndSettle();

      expect(find.text('أحمد محمود مش هيقدر يطلب لحد ما تفك الحظر.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'حظر'));
      await tester.pumpAndSettle();

      expect(customers.blockCalls, [('u1', true)]);
      expect(find.text('فك الحظر'), findsOneWidget);
    });

    testWidgets('shows notice when 50 results come back', (tester) async {
      final fifty = List.generate(
        50,
        (i) => CustomerSummary(
          id: 'user_$i',
          name: 'عميل $i',
          phone: '010000000$i',
          isBlocked: false,
          rejectedOrdersCount: 0,
          createdAt: DateTime(2026, 8, 1),
        ),
      );
      await pump(tester, seed: fifty);
      await search(tester, 'عميل');

      expect(find.text('بيظهر أول 50 — اكتب رقم أدق'), findsOneWidget);
    });

    testWidgets('call button launches tel: uri or alerts when dialer is unavailable', (tester) async {
      await pump(tester, linkAnswer: true);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CustomerDetailScreen.callKey));
      await tester.pumpAndSettle();

      expect(externalLinks.opened, [Uri.parse('tel:01012345678')]);

      // When dialer refuses or is missing
      externalLinks.answer = false;
      await tester.tap(find.byKey(CustomerDetailScreen.callKey));
      await tester.pumpAndSettle();

      expect(find.text('مفيش تطبيق اتصال على الجهاز.'), findsOneWidget);
    });

    testWidgets('back button returns to the customer search list', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      expect(find.byKey(CustomerDetailScreen.detailKey), findsOneWidget);

      await tester.tap(find.byKey(CustomerDetailScreen.backKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CustomerDetailScreen.detailKey), findsNothing);
      expect(find.byKey(CustomersScreen.searchKey), findsOneWidget);
    });

    testWidgets('wide layout displays list and detail side by side without breaking', (tester) async {
      await pump(tester, size: wideSize);
      await search(tester, 'أحمد');

      // Tapping a customer selects them in wide layout
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      // Both the search list and customer detail are visible simultaneously
      expect(find.byKey(CustomersScreen.searchKey), findsOneWidget);
      expect(find.byKey(CustomerDetailScreen.detailKey), findsOneWidget);
      expect(find.text('01012345678'), findsWidgets);
    });
  });

  /// One customer's facts under another customer's name.
  ///
  /// On a wide screen the detail sits beside the list and is the same widget whichever
  /// row is selected. Its load read `_customer.id` after an `await`, and a load that
  /// finished late wrote its answer into state regardless of who was selected by then.
  /// So: select Ahmed, then Salma before Ahmed's orders arrive — and Ahmed's last order
  /// is on the screen under Salma's name, the generate button is live, and it resets
  /// **Salma**. The admin asks the caller about one account and hands a password to another.
  ///
  /// Found by the review pass, reproduced in its own translation of the state logic, and
  /// reproduced here in the widget itself.
  testWidgets('a slow load for one customer never lands under the next one', (tester) async {
    await pump(tester, size: wideSize);

    final slow = _SlowCustomers({'u1': [ahmedOrder], 'u2': []}, [ahmed, salma]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider.overrideWithValue(slow),
          adminRepositoryProvider.overrideWithValue(adminRepo),
          addressRepositoryProvider.overrideWithValue(addresses),
          geographyRepositoryProvider.overrideWithValue(geography),
          externalLinksProvider.overrideWithValue(externalLinks),
          clockProvider.overrideWithValue(() => fixedClock),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CustomersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The list is empty until somebody searches; an empty query returns everybody.
    await tester.enterText(find.byKey(CustomersScreen.searchKey), 'ا');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Ahmed selected; his history is held.
    await tester.tap(find.text('أحمد محمود').first);
    await tester.pump();
    // Salma selected before it arrives.
    await tester.tap(find.text('سلمى علي').first);
    await tester.pump();
    // Salma's (empty) history arrives first, then Ahmed's late one.
    slow.release('u2');
    await tester.pump();
    slow.release('u1');
    await tester.pumpAndSettle();

    expect(find.textContaining('#1247'), findsNothing,
        reason: "Ahmed's last order must not be shown while Salma is selected");
  });

  /// Two regressions the review pass reproduced in the restyled customer detail.
  group('the customer history', () {
    List<Order> manyOrders(int n) => [
          for (var i = 0; i < n; i++)
            ahmedOrder.copyWith(
              id: 'o$i',
              orderNumber: 2000 + i,
              // Newest first, a minute apart, as the server pages them.
              placedAt: DateTime(2026, 9, 1, 12).subtract(Duration(minutes: i)),
            ),
        ];

    Future<void> open(WidgetTester tester, List<Order> history) async {
      await pump(tester);
      customers = FakeCustomerRepository(seed: [ahmed, salma], histories: {'u1': history});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerRepositoryProvider.overrideWithValue(customers),
            adminRepositoryProvider.overrideWithValue(adminRepo),
            addressRepositoryProvider.overrideWithValue(addresses),
            geographyRepositoryProvider.overrideWithValue(geography),
            externalLinksProvider.overrideWithValue(externalLinks),
            clockProvider.overrideWithValue(() => fixedClock),
            staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
          ],
          child: MaterialApp(
            theme: LuqmaTheme.light,
            locale: const Locale('ar'),
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            supportedLocales: LuqmaStrings.supportedLocales,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: CustomersScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();
    }

    // Cut at five with no way to the rest, and the older orders are what a call about a
    // disputed delivery last month needs.
    testWidgets('reaches past the first five', (tester) async {
      await open(tester, manyOrders(6));

      final scrollable = find
          .descendant(
            of: find.byType(CustomerDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first;

      final showAll = find.byKey(CustomerDetailScreen.showAllOrdersKey);
      await tester.scrollUntilVisible(showAll, 200, scrollable: scrollable);
      await tester.tap(showAll);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('#2005'), 200,
          scrollable: scrollable);
      expect(find.textContaining('#2005'), findsWidgets);
    });

    // The history is the newest fifty. Totals over it are totals over a window, and a
    // number that silently stops growing at fifty reads as the account.
    testWidgets('says when its totals are the newest fifty, not the account', (tester) async {
      await open(tester, manyOrders(50));
      expect(find.textContaining('آخر 50'), findsWidgets);
    });

    // A support call about a months-old order stopped at the newest fifty.
    testWidgets('older orders past the first fifty can be fetched', (tester) async {
      await open(tester, manyOrders(55));
      final scrollable = find
          .descendant(
            of: find.byType(CustomerDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first;

      final showAll = find.byKey(CustomerDetailScreen.showAllOrdersKey);
      await tester.scrollUntilVisible(showAll, 300, scrollable: scrollable);
      await tester.tap(showAll);
      await tester.pumpAndSettle();

      final older = find.byKey(CustomerDetailScreen.olderOrdersKey);
      await tester.scrollUntilVisible(older, 600, scrollable: scrollable);
      await tester.tap(older);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('#2054'), 600,
          scrollable: scrollable);
      expect(find.textContaining('#2054'), findsWidgets);
      expect(find.byKey(CustomerDetailScreen.olderOrdersKey), findsNothing,
          reason: 'a short last page means there is nothing older');
    });
  });
}

/// A customer repository whose history answers only when told to, so a test can make one
/// customer's load finish after another's has started.
class _SlowCustomers implements CustomerRepository {
  _SlowCustomers(this._histories, this._seed);

  final Map<String, List<Order>> _histories;
  final List<CustomerSummary> _seed;
  final Map<String, Completer<Result<List<Order>>>> _pending = {};

  void release(String uid) =>
      _pending[uid]?.complete(Result.ok(_histories[uid] ?? const []));

  @override
  Future<Result<List<CustomerSummary>>> search(String query) async => Result.ok(_seed);

  @override
  Future<Result<List<Order>>> history(String uid, {Order? after}) =>
      (_pending[uid] = Completer<Result<List<Order>>>()).future;

  @override
  Future<Result<void>> setBlocked(String uid, {required bool blocked}) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> setPassword(String uid, String password) async =>
      const Result.ok(null);
}

const _moderator = StaffIdentity(
  uid: 'mod-1',
  role: StaffRole.moderator,
  scope: StaffScope.platform,
  isAdmin: true,
);
