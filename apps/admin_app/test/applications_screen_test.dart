import 'package:admin_app/src/applications/applications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  late FakeStaffApplicationRepository applications;

  const appOld = StaffApplication(
    id: 'app-old',
    kind: StaffApplicationKind.courier,
    name: 'عمرو',
    phone: '01000000001',
    note: 'معايا موتوسيكل وبغطي إدكو كلها',
    status: StaffApplicationStatus.pending,
  );

  const appNew = StaffApplication(
    id: 'app-new',
    kind: StaffApplicationKind.restaurant,
    name: 'بيتزا روما',
    phone: '01000000002',
    note: 'المحطة ش البحر 11ص-2ص',
    status: StaffApplicationStatus.pending,
  );

  Future<void> pump(
    WidgetTester tester, {
    List<StaffApplication> seed = const [appOld, appNew],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    applications = FakeStaffApplicationRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffApplicationRepositoryProvider.overrideWithValue(applications),
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

    testWidgets('plainly says that approving does not create the account', (tester) async {
      await pump(tester);

      // Plain explanation that approval is a decision record, account created through staff screen
      expect(
        find.textContaining('إنشاء حساب المستخدم الفعلي وصلاحياته يتم من شاشة الفريق'),
        findsOneWidget,
      );
    });

    testWidgets('approving writes the note and marks the application approved', (tester) async {
      await pump(tester);

      final approveButton = find.byKey(ApplicationsScreen.approveKey('app-new'));
      expect(approveButton, findsOneWidget);

      await tester.tap(approveButton);
      await tester.pumpAndSettle();

      // Dialog opens asking for call notes and reiterating that account is made in staff
      expect(find.byKey(ApplicationsScreen.reviewNoteKey), findsOneWidget);
      await tester.enterText(
        find.byKey(ApplicationsScreen.reviewNoteKey),
        'اتكلمنا واتفقنا على المنيو، هيتعمل له حساب صاحب مطعم',
      );

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
}
