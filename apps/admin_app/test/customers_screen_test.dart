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
          addressRepositoryProvider.overrideWithValue(addresses),
          geographyRepositoryProvider.overrideWithValue(geography),
          externalLinksProvider.overrideWithValue(externalLinks),
          clockProvider.overrideWithValue(() => fixedClock),
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

      // Generate button is present
      expect(find.byKey(CustomerDetailScreen.generatePasswordKey), findsOneWidget);
      expect(customers.resetCalls, isEmpty, reason: 'password must not be generated yet');
    });

    testWidgets('customer with no orders and no addresses shows plain notice and allows reset', (tester) async {
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

      // Still allows password generation (owner's call on fresh accounts)
      expect(find.byKey(CustomerDetailScreen.generatePasswordKey), findsOneWidget);
      await tester.tap(find.byKey(CustomerDetailScreen.generatePasswordKey));
      await tester.pumpAndSettle();

      expect(customers.resetCalls, ['u2']);
      expect(find.text('demo-pass-42'), findsOneWidget);
    });
  });

  group('password generation', () {
    testWidgets('shows new password once as selectable text in LTR', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CustomerDetailScreen.generatePasswordKey));
      await tester.pumpAndSettle();

      expect(customers.resetCalls, ['u1']);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, 'demo-pass-42');
      expect(selectable.textDirection, TextDirection.ltr);

      // Dismiss dialog
      await tester.tap(find.text('تمام'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('refusal for staff account shows specific message', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      customers.failure = const ConflictFailure();
      await tester.tap(find.byKey(CustomerDetailScreen.generatePasswordKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('شاشة الموظفين'), findsOneWidget);
      expect(find.text('demo-pass-42'), findsNothing);
    });

    testWidgets('refusal for generic error shows حاول تاني', (tester) async {
      await pump(tester);
      await search(tester, 'أحمد');
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpAndSettle();

      customers.failure = const PermissionFailure();
      await tester.tap(find.byKey(CustomerDetailScreen.generatePasswordKey));
      await tester.pumpAndSettle();

      expect(find.text('مقدرناش'), findsOneWidget);
      expect(find.text('حاول تاني.'), findsOneWidget);
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

      expect(customers.blockCalls, [('u1', true)]);
      expect(find.text('فك الحظر'), findsOneWidget);
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
          addressRepositoryProvider.overrideWithValue(addresses),
          geographyRepositoryProvider.overrideWithValue(geography),
          externalLinksProvider.overrideWithValue(externalLinks),
          clockProvider.overrideWithValue(() => fixedClock),
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
            ahmedOrder.copyWith(id: 'o$i', orderNumber: 2000 + i),
        ];

    Future<void> open(WidgetTester tester, List<Order> history) async {
      await pump(tester);
      customers = FakeCustomerRepository(seed: [ahmed, salma], histories: {'u1': history});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerRepositoryProvider.overrideWithValue(customers),
            addressRepositoryProvider.overrideWithValue(addresses),
            geographyRepositoryProvider.overrideWithValue(geography),
            externalLinksProvider.overrideWithValue(externalLinks),
            clockProvider.overrideWithValue(() => fixedClock),
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

      final showAll = find.byKey(CustomerDetailScreen.showAllOrdersKey);
      await tester.scrollUntilVisible(showAll, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(showAll);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('#2005'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.textContaining('#2005'), findsWidgets);
    });

    // The history is the newest fifty. Totals over it are totals over a window, and a
    // number that silently stops growing at fifty reads as the account.
    testWidgets('says when its totals are the newest fifty, not the account', (tester) async {
      await open(tester, manyOrders(50));
      expect(find.textContaining('آخر 50'), findsWidgets);
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
  Future<Result<List<Order>>> history(String uid) =>
      (_pending[uid] = Completer<Result<List<Order>>>()).future;

  @override
  Future<Result<void>> setBlocked(String uid, {required bool blocked}) async =>
      const Result.ok(null);

  @override
  Future<Result<String>> resetPassword(String uid) async => Result.ok('pw-$uid');
}
