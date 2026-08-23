import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../auth/sign_in_screen.dart';
import '../courier/courier_screen.dart';
import '../menu/menu_screen.dart';
import '../orders/inbox_screen.dart';
import '../orders/live_board_screen.dart';
import '../shop/shop_screen.dart';

/// MerchantApp.
///
/// The gate is not a router: this app has four tabs and one question — is the signed-in
/// account a merchant. A route table would be machinery for decisions it does not make.
///
/// One app, two modes, chosen by the role on the token. A courier gets the delivery
/// screen and nothing else — no menu, no busy toggle, no inbox. There is no driver app
/// to install and no second APK to keep in step.
///
/// The three answers to "who is this" are kept apart on purpose. *Not resolved yet* is
/// not *signed out*, or every launch flashes a login screen at somebody already signed
/// in. And a signed-in account that belongs to no merchant and is not a platform courier
/// is *turned away*, not asked to sign in — they have a real account, just not one this
/// app is for.
class MerchantApp extends ConsumerWidget {
  const MerchantApp({super.key});

  static const inboxTabKey = Key('app.tab.inbox');
  static const liveTabKey = Key('app.tab.live');
  static const menuTabKey = Key('app.tab.menu');
  static const shopTabKey = Key('app.tab.shop');
  static const noAccessKey = Key('app.noAccess');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'لقمة — التاجر',
      debugShowCheckedModeBanner: false,
      theme: LuqmaTheme.light,
      darkTheme: LuqmaTheme.dark,
      // Arabic only, right-to-left everywhere. There is no English build to fall back
      // to, so the locale is fixed rather than following the device.
      locale: const Locale('ar'),
      supportedLocales: LuqmaStrings.supportedLocales,
      localizationsDelegates: const [
        ...LuqmaStrings.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Gate(),
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentIdentityProvider);

    return switch (session) {
      AsyncValue(hasValue: true, value: null) => const SignInScreen(),
      AsyncValue(hasValue: true, :final value?) => switch (StaffIdentity.from(value)) {
          // A platform courier belongs to no merchant, so `ownsAMerchant` is false for
          // them and the role is what decides.
          StaffIdentity(role: StaffRole.courier) => const CourierScreen(),
          StaffIdentity(ownsAMerchant: true) => const _Shell(),
          _ => const _NoAccess(),
        },
      // Being unable to read the session means nobody is signed in, never that
      // somebody is.
      AsyncValue(hasError: true) => const SignInScreen(),
      _ => const _Starting(),
    };
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Scaffold(
      backgroundColor: colors.background,
      // One stack, so switching to the menu and back does not throw away the inbox's
      // live subscription and re-load it.
      body: IndexedStack(
        index: _tab,
        children: const [
          InboxScreen(),
          LiveBoardScreen(),
          MenuScreen(),
          ShopScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          // First, always. Whatever else a merchant is doing, getting back to an
          // unanswered order has to be one tap.
          NavigationDestination(
            key: MerchantApp.inboxTabKey,
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active),
            label: 'الجديد',
          ),
          NavigationDestination(
            key: MerchantApp.liveTabKey,
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department),
            label: 'الجاري',
          ),
          NavigationDestination(
            key: MerchantApp.menuTabKey,
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'المنيو',
          ),
          NavigationDestination(
            key: MerchantApp.shopTabKey,
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'المطعم',
          ),
        ],
      ),
    );
  }
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).luqma.brand,
      body: const Center(child: LuqmaLockup(logo: LuqmaLogo.mark, height: 96)),
    );
  }
}

class _NoAccess extends ConsumerWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      key: MerchantApp.noAccessKey,
      backgroundColor: theme.luqma.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LuqmaLockup(logo: LuqmaLogo.mark, height: 64),
              const SizedBox(height: Space.xl),
              Text(
                'الحساب ده مش مربوط بمطعم',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'التطبيق ده للتجّار. لو ده حسابك الصح، كلّم إدارة لقمة عشان يربطوه.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.luqma.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              OutlinedButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
