import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/auth/apply_screen.dart';
import 'package:merchant_app/src/auth/sign_in_screen.dart';

void main() {
  late FakeStaffApplicationRepository applications;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Widget child = const ApplyScreen(),
    Failure? repositoryFailure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    applications = FakeStaffApplicationRepository(failure: repositoryFailure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffApplicationRepositoryProvider.overrideWithValue(applications),
          authServiceProvider.overrideWithValue(FakeAuthService()),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(ApplyScreen.submitKey));
    await tester.tap(find.byKey(ApplyScreen.submitKey));
    await tester.pumpAndSettle();
  }

  group('Way in from sign-in screen', () {
    testWidgets('SignInScreen has a button to navigate to ApplyScreen', (tester) async {
      await pumpScreen(tester, child: const SignInScreen());

      final applyButton = find.byKey(SignInScreen.applyKey);
      expect(applyButton, findsOneWidget);

      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(find.byType(ApplyScreen), findsOneWidget);
    });
  });

  group('ApplyScreen', () {
    testWidgets('first question changes the note field label and hint', (tester) async {
      await pumpScreen(tester);

      // Question is visible
      expect(find.text('إنت مندوب توصيل، ولا مطعم، ولا أكل بيتي؟'), findsOneWidget);

      // Defaults to courier: courier says which areas they cover
      expect(find.text('المناطق اللي بتغطيها'), findsOneWidget);

      // Select restaurant: shop says where it is and when it opens
      await tester.tap(find.byKey(const Key('apply.kind.restaurant')));
      await tester.pumpAndSettle();
      expect(find.text('مكان المطعم ومواعيد العمل'), findsOneWidget);

      // Select home kitchen
      await tester.tap(find.byKey(const Key('apply.kind.homeKitchen')));
      await tester.pumpAndSettle();
      expect(find.text('مكان المطبخ ومواعيد العمل'), findsOneWidget);
    });

    testWidgets('phone field validates with Phone.isValidEgyptianMobile', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'أحمد');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '012345'); // invalid
      await submit(tester);

      expect(find.text('اكتب رقم موبايل مصري صحيح'), findsOneWidget);
      expect(applications.all, isEmpty);

      // Enter valid Egyptian mobile
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01012345678');
      await submit(tester);

      expect(find.text('اكتب رقم موبايل مصري صحيح'), findsNothing);
      expect(applications.all, hasLength(1));
    });

    testWidgets('submitting valid form writes through repository', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('apply.kind.restaurant')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(ApplyScreen.nameKey), ' مطعم الزعيم ');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), ' ٠١١٢٣٤٥٦٧٨٩ ');
      await tester.enterText(find.byKey(ApplyScreen.noteKey), ' شارع البحر من 10ص لـ 12م ');
      await submit(tester);

      expect(applications.all, hasLength(1));
      final app = applications.all.first;
      expect(app.kind, StaffApplicationKind.restaurant);
      expect(app.name, 'مطعم الزعيم');
      expect(app.phone, '01123456789');
      expect(app.note, 'شارع البحر من 10ص لـ 12م');
      expect(app.status, StaffApplicationStatus.pending);
    });

    testWidgets('success state is honest and leaves no way back into a form', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await submit(tester);

      // Form is gone
      expect(find.byKey(ApplyScreen.nameKey), findsNothing);
      expect(find.byKey(ApplyScreen.phoneKey), findsNothing);
      expect(find.byKey(ApplyScreen.submitKey), findsNothing);

      // Honest explanation: someone will phone, no account is granted automatically
      expect(find.byKey(ApplyScreen.successKey), findsOneWidget);
      expect(find.textContaining('إدارة لقمة هتتصل بيك'), findsOneWidget);
      expect(find.textContaining('مش بيعمل حساب'), findsOneWidget);

      // Only control is back to sign in
      expect(find.byKey(ApplyScreen.backButtonKey), findsOneWidget);
    });

    testWidgets('offline failure surfaces as its own sentence', (tester) async {
      await pumpScreen(tester, repositoryFailure: const OfflineFailure());

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await submit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.textContaining('مفيش اتصال بالإنترنت'), findsOneWidget);
      expect(applications.all, isEmpty);
    });

    testWidgets('already applied failure surfaces as its own sentence', (tester) async {
      await pumpScreen(tester, repositoryFailure: const AlreadyAppliedFailure());

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await submit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.text('في طلب متقدم بالرقم ده بالفعل — حد من الإدارة هيكلمك'), findsOneWidget);
      expect(applications.all, isEmpty);
    });
  });
}
