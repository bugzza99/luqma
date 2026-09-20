import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/auth/apply_screen.dart';
import 'package:merchant_app/src/auth/sign_in_screen.dart';

void main() {
  late FakeStaffApplicationRepository applications;
  late FakeAuthService auth;
  late FakeStaffDocumentsRepository papers;

  /// Real JPEG bytes. `ImageCompressor` decodes what it is handed, so three arbitrary
  /// bytes would exercise the "could not read that photograph" path rather than the one
  /// under test.
  Uint8List photograph() {
    final image = img.Image(width: 64, height: 40);
    for (var y = 0; y < 40; y += 1) {
      for (var x = 0; x < 64; x += 1) {
        image.setPixelRgb(x, y, (x * 4) % 256, (y * 6) % 256, 128);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Widget child = const ApplyScreen(),
    Failure? repositoryFailure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    applications = FakeStaffApplicationRepository(failure: repositoryFailure);
    auth = FakeAuthService();
    papers = FakeStaffDocumentsRepository(signedInUid: 'applicant');
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffApplicationRepositoryProvider.overrideWithValue(applications),
          authServiceProvider.overrideWithValue(auth),
          staffDocumentsRepositoryProvider.overrideWithValue(papers),
          pickImageProvider.overrideWithValue(() async => photograph()),
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

  /// The form asks for a password now, so every submit that is meant to succeed has to
  /// type one — the account is made before the application is filed.
  Future<void> enterPassword(WidgetTester tester, [String password = 'luqma12345']) async {
    await tester.enterText(find.byKey(ApplyScreen.passwordKey), password);
    await tester.enterText(find.byKey(ApplyScreen.confirmKey), password);
  }

  /// Taps the three document slots. A courier is approved on their papers, so every
  /// courier application in these tests has to hand them in the way a real one does.
  ///
  /// A no-op when the form is not asking — a restaurant has no slots to tap — so
  /// [submit] can call it without every test having to know which kind it chose.
  Future<void> handInPapers(WidgetTester tester) async {
    if (find.byKey(ApplyScreen.papersKey).evaluate().isEmpty) return;
    for (final key in [
      ApplyScreen.idFrontKey,
      ApplyScreen.idBackKey,
      ApplyScreen.selfieKey,
    ]) {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(ApplyScreen.submitKey));
    await tester.tap(find.byKey(ApplyScreen.submitKey));
    await tester.pumpAndSettle();
  }

  /// Fills in whatever the chosen kind requires, then sends it. Tests that are *about*
  /// sending an incomplete form tap the button directly instead.
  Future<void> submit(WidgetTester tester) async {
    await handInPapers(tester);
    await tapSubmit(tester);
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
      await enterPassword(tester);
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
      await enterPassword(tester);
      await submit(tester);

      expect(applications.all, hasLength(1));
      final app = applications.all.first;
      expect(app.kind, StaffApplicationKind.restaurant);
      expect(app.name, 'مطعم الزعيم');
      expect(app.phone, '01123456789');
      expect(app.note, 'شارع البحر من 10ص لـ 12م');
      expect(app.status, StaffApplicationStatus.pending);
      // Filed against the account this form just made: without it approval has nothing
      // to turn into a merchant.
      expect(app.applicantUid, isNotNull);
    });

    testWidgets('success state is honest and leaves no way back into a form', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester);
      await submit(tester);

      // Form is gone
      expect(find.byKey(ApplyScreen.nameKey), findsNothing);
      expect(find.byKey(ApplyScreen.phoneKey), findsNothing);
      expect(find.byKey(ApplyScreen.submitKey), findsNothing);

      // Honest explanation: the account exists and carries nothing until an admin approves
      expect(find.byKey(ApplyScreen.successKey), findsOneWidget);
      expect(find.textContaining('إدارة لقمة هتتصل بيك'), findsOneWidget);
      expect(find.textContaining('من غير صلاحيات'), findsOneWidget);

      // Only control is back to sign in
      expect(find.byKey(ApplyScreen.backButtonKey), findsOneWidget);
    });

    testWidgets('offline failure surfaces as its own sentence', (tester) async {
      await pumpScreen(tester, repositoryFailure: const OfflineFailure());

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester);
      await submit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.textContaining('مفيش اتصال بالإنترنت'), findsOneWidget);
      expect(applications.all, isEmpty);
    });

    testWidgets('already applied failure surfaces as its own sentence', (tester) async {
      await pumpScreen(tester, repositoryFailure: const AlreadyAppliedFailure());

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester);
      await submit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.text('في طلب متقدم بالرقم ده بالفعل — حد من الإدارة هيكلمك'), findsOneWidget);
      expect(applications.all, isEmpty);
    });
  });

  // 2026-09-18: the first real merchant applied, was approved, and had nothing to sign in
  // with — the form had never asked for a password and the application pointed at no account.
  group('ApplyScreen makes the account', () {
    testWidgets('the two passwords have to match, and nothing is written until they do',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await tester.enterText(find.byKey(ApplyScreen.passwordKey), 'luqma12345');
      await tester.enterText(find.byKey(ApplyScreen.confirmKey), 'luqma54321');
      await submit(tester);

      expect(find.text('كلمتي السر مش متطابقتين'), findsOneWidget);
      expect(applications.all, isEmpty);
    });

    testWidgets('a short password is refused', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester, 'luqma');
      await submit(tester);

      expect(find.text('كلمة السر 8 حروف على الأقل'), findsOneWidget);
      expect(applications.all, isEmpty);
    });

    testWidgets('somebody who already orders as a customer applies with their own password',
        (tester) async {
      await pumpScreen(tester);
      // The same number already has a customer account.
      await auth.signUpWithPhone(
        phone: '01000000000',
        password: 'luqma12345',
        name: 'محمود',
      );

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'محمود');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester);
      await submit(tester);

      expect(find.byKey(ApplyScreen.successKey), findsOneWidget);
      expect(applications.all.single.applicantUid, isNotNull);
    });

    testWidgets('the wrong password on a number that is taken files nothing', (tester) async {
      await pumpScreen(tester);
      await auth.signUpWithPhone(
        phone: '01000000000',
        password: 'luqma12345',
        name: 'صاحب الرقم',
      );

      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'حد تاني');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester, 'luqma99999');
      await submit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.textContaining('الرقم ده عنده حساب بالفعل'), findsOneWidget);
      expect(applications.all, isEmpty);
    });
  });

  group('a courier shows their papers', () {
    Future<void> fillIn(WidgetTester tester) async {
      await tester.enterText(find.byKey(ApplyScreen.nameKey), 'سعيد');
      await tester.enterText(find.byKey(ApplyScreen.phoneKey), '01000000000');
      await enterPassword(tester);
    }

    testWidgets('asks a courier for three photographs and says why', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(ApplyScreen.papersKey), findsOneWidget);
      expect(find.byKey(ApplyScreen.idFrontKey), findsOneWidget);
      expect(find.byKey(ApplyScreen.idBackKey), findsOneWidget);
      expect(find.byKey(ApplyScreen.selfieKey), findsOneWidget);
      // Somebody handing over a photograph of their national ID is owed the reason and
      // the rule about how long it is kept, on the screen that asks for it.
      expect(find.textContaining('بيحصّل فلوسهم'), findsOneWidget);
      expect(find.textContaining('بتتمسح'), findsOneWidget);
    });

    testWidgets('asks a restaurant for none of it', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('apply.kind.restaurant')));
      await tester.pumpAndSettle();

      expect(find.byKey(ApplyScreen.papersKey), findsNothing);
    });

    testWidgets('refuses to file a courier application with no papers', (tester) async {
      // The database refuses to *approve* one, which would strand somebody in the queue
      // with an application nobody can act on and no way to tell why. Said here instead.
      await pumpScreen(tester);
      await fillIn(tester);

      await tapSubmit(tester);

      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.textContaining('صور البطاقة التلاتة'), findsOneWidget);
      expect(applications.all, isEmpty);
      expect(papers.handIns, 0);
    });

    testWidgets('hands the papers in before the application', (tester) async {
      await pumpScreen(tester);
      await fillIn(tester);

      await submit(tester);

      expect(papers.handIns, 1);
      expect(applications.all.single.kind, StaffApplicationKind.courier);
      expect(find.byKey(ApplyScreen.successKey), findsOneWidget);
    });

    testWidgets('files nothing when the papers will not upload', (tester) async {
      // The other order would leave a row in the owner's queue that cannot be approved,
      // and the owner would find that out on the telephone.
      await pumpScreen(tester);
      papers.failWith = const OfflineFailure();
      await fillIn(tester);

      await submit(tester);

      expect(applications.all, isEmpty);
      expect(find.byKey(ApplyScreen.errorKey), findsOneWidget);
      expect(find.textContaining('مفيش اتصال بالإنترنت'), findsOneWidget);
    });

    testWidgets('a chosen photograph is shown back, not just ticked off', (tester) async {
      // The bucket is private and this screen is the last time the applicant sees what
      // they sent, so a tick alone would ask them to trust that the right photograph
      // went in — the one thing they cannot check afterwards.
      await pumpScreen(tester);

      await tester.ensureVisible(find.byKey(ApplyScreen.idFrontKey));
      await tester.tap(find.byKey(ApplyScreen.idFrontKey));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(ApplyScreen.idFrontKey),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });
  });
}
