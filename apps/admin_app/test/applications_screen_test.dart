import 'package:admin_app/src/applications/applications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  late FakeStaffApplicationRepository applications;
  late FakeStaffDocumentsRepository papers;

  const appOld = StaffApplication(
    id: 'app-old',
    kind: StaffApplicationKind.courier,
    name: 'عمرو',
    phone: '01000000001',
    note: 'معايا موتوسيكل وبغطي إدكو كلها',
    applicantUid: 'u-courier',
    status: StaffApplicationStatus.pending,
  );

  const appNew = StaffApplication(
    id: 'app-new',
    kind: StaffApplicationKind.restaurant,
    name: 'بيتزا روما',
    phone: '01000000002',
    note: 'المحطة ش البحر 11ص-2ص',
    applicantUid: 'u-shop',
    status: StaffApplicationStatus.pending,
  );

  Future<void> pump(
    WidgetTester tester, {
    List<StaffApplication> seed = const [appOld, appNew],
    bool courierHasPapers = true,
    Failure? papersFailure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    applications = FakeStaffApplicationRepository(seed: seed);
    papers = FakeStaffDocumentsRepository(
      signedInUid: 'u-admin',
      seed: courierHasPapers
          ? {
              'u-courier': StaffDocuments(
                uid: 'u-courier',
                idFrontPath: 'u-courier/id-front.jpg',
                idBackPath: 'u-courier/id-back.jpg',
                selfiePath: 'u-courier/selfie.jpg',
                uploadedAt: DateTime(2026, 9, 19),
              ),
            }
          : const {},
    )..readable.add('u-courier');
    papers.failWith = papersFailure;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffApplicationRepositoryProvider.overrideWithValue(applications),
          staffDocumentsRepositoryProvider.overrideWithValue(papers),
          // Approval builds the account now, so it needs the zone a shop sits in and the
          // shop a courier starts at.
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(
              zones: const [Zone(id: 'z1', cityId: 'edku', name: 'منشية الأمل')],
            ),
          ),
          merchantRepositoryProvider.overrideWithValue(
            FakeMerchantRepository(
              seed: const [
                Merchant(
                  id: 'm1',
                  cityId: 'edku',
                  type: MerchantType.restaurant,
                  name: 'مطعم البحر',
                  zoneId: 'z1',
                  phone: '01000000000',
                  status: MerchantStatus.approved,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: ApplicationsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ApplicationsScreen queue', () {
    testWidgets('lists pending applications with applicant details and what was typed', (tester) async {
      await pump(tester);

      // Both applications are rendered
      expect(find.text('عمرو'), findsOneWidget);
      expect(find.text('01000000001'), findsOneWidget);
      expect(find.text('مندوب توصيل'), findsOneWidget);
      expect(find.text('معايا موتوسيكل وبغطي إدكو كلها'), findsOneWidget);

      expect(find.text('بيتزا روما'), findsOneWidget);
      expect(find.text('01000000002'), findsOneWidget);
      expect(find.text('مطعم'), findsOneWidget);
      expect(find.text('المحطة ش البحر 11ص-2ص'), findsOneWidget);
    });

    testWidgets('says that approving makes the account', (tester) async {
      await pump(tester);

      // 2026-09-18: it used to say the opposite — approval was a decision record and the
      // account was made by hand afterwards, which nobody did.
      expect(
        find.textContaining('القبول هيعمل الحساب وصلاحياته على طول'),
        findsOneWidget,
      );
    });

    testWidgets('approving writes the note and marks the application approved', (tester) async {
      await pump(tester);

      final approveButton = find.byKey(ApplicationsScreen.approveKey('app-new'));
      expect(approveButton, findsOneWidget);

      // The card carries the applicant's whole note now; the buttons sit below the fold.
      await tester.ensureVisible(approveButton);
      await tester.pumpAndSettle();
      await tester.tap(approveButton);
      await tester.pumpAndSettle();

      // Dialog opens asking for call notes and the zone the shop sits in.
      expect(find.byKey(ApplicationsScreen.reviewNoteKey), findsOneWidget);
      await tester.enterText(
        find.byKey(ApplicationsScreen.reviewNoteKey),
        'اتكلمنا واتفقنا على المنيو، هيتعمل له حساب صاحب مطعم',
      );
      await tester.tap(find.byKey(ApplicationsScreen.zonePickerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('منشية الأمل').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ApplicationsScreen.confirmKey));
      await tester.pumpAndSettle();

      // Application is approved and removed from pending queue
      final updated = applications.all.firstWhere((a) => a.id == 'app-new');
      expect(updated.status, StaffApplicationStatus.approved);
      expect(updated.reviewNote, 'اتكلمنا واتفقنا على المنيو، هيتعمل له حساب صاحب مطعم');
      expect(updated.reviewedAt, isNotNull);

      expect(find.text('بيتزا روما'), findsNothing);
      expect(find.text('عمرو'), findsOneWidget);
    });

    testWidgets('rejecting writes the note and marks the application rejected', (tester) async {
      await pump(tester);

      final rejectButton = find.byKey(ApplicationsScreen.rejectKey('app-old'));
      expect(rejectButton, findsOneWidget);

      await tester.tap(rejectButton);
      await tester.pumpAndSettle();

      expect(find.byKey(ApplicationsScreen.reviewNoteKey), findsOneWidget);
      await tester.enterText(
        find.byKey(ApplicationsScreen.reviewNoteKey),
        'اعتذر عن العمل حالياً',
      );

      await tester.tap(find.byKey(ApplicationsScreen.confirmKey));
      await tester.pumpAndSettle();

      final updated = applications.all.firstWhere((a) => a.id == 'app-old');
      expect(updated.status, StaffApplicationStatus.rejected);
      expect(updated.reviewNote, 'اعتذر عن العمل حالياً');

      expect(find.text('عمرو'), findsNothing);
    });

    testWidgets('shows empty state when no applications are pending', (tester) async {
      await pump(tester, seed: const []);

      expect(find.text('مفيش طلبات في الانتظار'), findsOneWidget);
    });
  });

  // 2026-09-18: approving used to stamp the row and nothing else, so the first real merchant
  // left the queue and existed nowhere.
  group('approval builds the account', () {
    testWidgets('a shop is approved into its zone', (tester) async {
      await pump(tester, seed: [appNew]);

      await tester.tap(find.byKey(ApplicationsScreen.approveKey('app-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ApplicationsScreen.zonePickerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('منشية الأمل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ApplicationsScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(applications.approvals.single, ('app-new', 'z1', null));
    });

    testWidgets('a courier is approved onto the shop they start with', (tester) async {
      await pump(tester, seed: [appOld]);

      await tester.tap(find.byKey(ApplicationsScreen.approveKey('app-old')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ApplicationsScreen.shopPickerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مطعم البحر').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ApplicationsScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(applications.approvals.single, ('app-old', null, 'm1'));
    });

    testWidgets('an application from before there were accounts says so and cannot be approved',
        (tester) async {
      await pump(tester, seed: [
        const StaffApplication(
          id: 'app-old-style',
          kind: StaffApplicationKind.restaurant,
          name: 'ابو حاتم',
          phone: '01277077556',
          status: StaffApplicationStatus.pending,
        ),
      ]);

      await tester.tap(find.byKey(ApplicationsScreen.approveKey('app-old-style')));
      await tester.pumpAndSettle();

      expect(find.textContaining('معندوش حساب'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.byKey(ApplicationsScreen.confirmKey));
      expect(confirm.onPressed, isNull);
    });
  });

  // A call from last month had nowhere to be looked up (QA review 2026-09-19).
  testWidgets('decided applications can be found again, with the reason written then',
      (tester) async {
    final refused = StaffApplication(
      id: 'app-done',
      kind: StaffApplicationKind.homeKitchen,
      name: 'مطبخ أم محمد',
      phone: '01000000009',
      status: StaffApplicationStatus.rejected,
      reviewedAt: DateTime(2026, 8, 30),
      reviewNote: 'مفيش ترخيص لسه',
    );
    await pump(tester, seed: [appOld, appNew, refused]);

    await tester.tap(find.byKey(ApplicationsScreen.historyTabKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ApplicationsScreen.decidedKey('app-done')), findsOneWidget);
    expect(find.text('مفيش ترخيص لسه'), findsOneWidget);
    expect(find.byKey(ApplicationsScreen.decidedKey('app-old')), findsNothing);

    await tester.enterText(find.byKey(ApplicationsScreen.historySearchKey), '٠١٠٠٠٠٠٠٠٠٩');
    await tester.pumpAndSettle();
    expect(find.byKey(ApplicationsScreen.decidedKey('app-done')), findsOneWidget);

    await tester.enterText(find.byKey(ApplicationsScreen.historySearchKey), 'حد تاني');
    await tester.pumpAndSettle();
    expect(find.byKey(ApplicationsScreen.decidedKey('app-done')), findsNothing);
  });

  group('a courier is approved on their papers', () {
    testWidgets('offers the papers on a courier and not on a shop', (tester) async {
      await pump(tester);

      // On the card, beside the decision rather than behind it: putting it inside the
      // approve dialog would mean deciding before seeing the ID.
      expect(find.byKey(ApplicationsScreen.papersKey('app-old')), findsOneWidget);
      expect(find.byKey(ApplicationsScreen.papersKey('app-new')), findsNothing);
    });

    testWidgets('shows the three photographs', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.tap(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.pumpAndSettle();

      expect(find.byKey(ApplicationsScreen.papersSheetKey), findsOneWidget);
      expect(find.text('وش البطاقة'), findsOneWidget);
      expect(find.text('ضهر البطاقة'), findsOneWidget);
      expect(find.text('سيلفي وهو ماسك البطاقة'), findsOneWidget);
    });

    testWidgets('says plainly when an applicant uploaded nothing', (tester) async {
      await pump(tester, courierHasPapers: false);

      await tester.ensureVisible(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.tap(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.pumpAndSettle();

      expect(find.byKey(ApplicationsScreen.papersEmptyKey), findsOneWidget);
      expect(find.textContaining('مرفعش صور البطاقة'), findsOneWidget);
    });

    testWidgets('a dropped connection is not "they uploaded nothing"', (tester) async {
      // The two answers send the owner to two different telephone calls, and saying the
      // first when it means the second rings a courier who did everything right.
      await pump(tester, papersFailure: const OfflineFailure());

      await tester.ensureVisible(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.tap(find.byKey(ApplicationsScreen.papersKey('app-old')));
      await tester.pumpAndSettle();

      expect(find.byKey(ApplicationsScreen.papersEmptyKey), findsNothing);
      expect(find.byType(LuqmaErrorView), findsOneWidget);
    });
  });
}
