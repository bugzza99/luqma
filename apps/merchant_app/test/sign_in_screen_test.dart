import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/auth/sign_in_screen.dart';

/// Remembers which of the two ways in was used, because that is the whole question here.
class _RecordingAuth extends FakeAuthService {
  final calls = <String>[];

  @override
  Future<Result<LuqmaIdentity>> signInWithPhone({
    required String phone,
    required String password,
  }) {
    calls.add('phone:$phone');
    return super.signInWithPhone(phone: phone, password: password);
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  }) {
    calls.add('email:$email');
    return super.signInWithPassword(email: email, password: password);
  }
}

void main() {
  late _RecordingAuth auth;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    auth = _RecordingAuth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          staffApplicationRepositoryProvider
              .overrideWithValue(FakeStaffApplicationRepository()),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SignInScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, String who) async {
    await tester.enterText(find.byKey(SignInScreen.phoneKey), who);
    await tester.enterText(find.byKey(SignInScreen.passwordKey), 'luqma12345');
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();
  }

  group('SignInScreen', () {
    // 2026-09-18: it asked for an email, and the first real merchant had never had one.
    testWidgets('a phone number signs in the way a partner made their account', (tester) async {
      await pumpScreen(tester);

      await signIn(tester, '01012345678');

      expect(auth.calls, ['phone:01012345678']);
      expect(find.byKey(SignInScreen.errorKey), findsNothing);
    });

    // Every account «الفريق» has ever made has a real address and no phone identity.
    testWidgets('an address still signs in, so nobody made from the staff screen is locked out',
        (tester) async {
      await pumpScreen(tester);

      await signIn(tester, ' Owner@Luqma.app ');

      expect(auth.calls, ['email:Owner@Luqma.app']);
      expect(find.byKey(SignInScreen.errorKey), findsNothing);
    });

    testWidgets('something that is neither is refused before anything is sent', (tester) async {
      await pumpScreen(tester);

      await signIn(tester, '0101234');

      expect(auth.calls, isEmpty);
      expect(find.text('اكتب رقم موبايل صح أو الإيميل'), findsOneWidget);
    });
  });
}
