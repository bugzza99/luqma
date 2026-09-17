import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../auth/sign_in_screen.dart';
import '../courier/courier_screen.dart';
import '../meals/meals_screen.dart';
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
  const MerchantApp({super.key, required this.currentVersion});

  /// What [LuqmaForceUpdateGate] compares against the owner's floor.
  final String currentVersion;

  static const inboxTabKey = Key('app.tab.inbox');
  static const liveTabKey = Key('app.tab.live');
  static const menuTabKey = Key('app.tab.menu');
  static const mealsTabKey = Key('app.tab.meals');
  static const shopTabKey = Key('app.tab.shop');
  static const noAccessKey = Key('app.noAccess');
  static const refreshAccessKey = Key('app.refreshAccess');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      // The name the recents screen shows, and it has to match the icon's: a courier who
      // switches apps and finds «التاجر» on the card is told this app is not for them.
      title: 'لقمة شريك',
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
      home: LuqmaForceUpdateGate(
        app: LuqmaApp.merchant,
        currentVersion: currentVersion,
        child: const _Gate(),
      ),
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentIdentityProvider);

    // Not a `LuqmaAsyncView`, and it is the one gate in the product where that would be
    // wrong. Failing to read the session means nobody is signed in, so the error arm
    // shows the sign-in screen rather than an apology with a retry button — and there is
    // an arm for a *loaded* session that is null, which the shared widget has no notion
    // of because no other screen needs one.
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

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    // A home kitchen has no standing menu — what it sells is today's meal and a count of
    // portions. So the third tab is the one that matches the business, rather than a
    // menu editor a cook would never open.
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final isHomeKitchen = merchantId != null &&
        ref.watch(merchantProvider(merchantId)).value?.type ==
            MerchantType.homeKitchen;

    return LuqmaTappedOrder(
      // There is no per-order screen in MerchantApp — an order lives in a list — so the
      // destination is the list the alert was about. The alarm only ever fires for an
      // order nobody has answered, and that is الجديد.
      onOpen: (_) => setState(() => _tab = 0),
      child: LuqmaTabPopScope(
        currentIndex: _tab,
        // Switching tabs never pushes a route — see the doc comment above — so back on
        // any tab but الجديد used to find nothing on the Navigator's stack and exit the
        // app outright. It returns to الجديد first now, and only exits from there.
        onHome: () => setState(() => _tab = 0),
        child: Scaffold(
          backgroundColor: colors.background,
          // One stack, so switching to the menu and back does not throw away the inbox's
          // live subscription and re-load it.
          body: IndexedStack(
            index: _tab,
            children: [
              const InboxScreen(),
              const LiveBoardScreen(),
              if (isHomeKitchen) const MealsScreen() else const MenuScreen(),
              const ShopScreen(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              // First, always. Whatever else a merchant is doing, getting back to an
              // unanswered order has to be one tap.
              const NavigationDestination(
                key: MerchantApp.inboxTabKey,
                icon: Icon(Icons.notifications_active_outlined),
                selectedIcon: Icon(Icons.notifications_active),
                label: 'الجديد',
              ),
              const NavigationDestination(
                key: MerchantApp.liveTabKey,
                icon: Icon(Icons.local_fire_department_outlined),
                selectedIcon: Icon(Icons.local_fire_department),
                label: 'الجاري',
              ),
              if (isHomeKitchen)
                const NavigationDestination(
                  key: MerchantApp.mealsTabKey,
                  icon: Icon(Icons.soup_kitchen_outlined),
                  selectedIcon: Icon(Icons.soup_kitchen),
                  label: 'أكل النهارده',
                )
              else
                const NavigationDestination(
                  key: MerchantApp.menuTabKey,
                  icon: Icon(Icons.restaurant_menu_outlined),
                  selectedIcon: Icon(Icons.restaurant_menu),
                  label: 'المنيو',
                ),
              const NavigationDestination(
                key: MerchantApp.shopTabKey,
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront),
                label: 'المطعم',
              ),
            ],
          ),
        ),
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

/// Signed in, and carrying nothing yet.
///
/// Since 2026-09-18 this is mostly an applicant waiting for the telephone call, not
/// somebody who installed the wrong app — the account they made when they applied is an
/// ordinary one until an admin approves it.
///
/// It carries a refresh, and that button is the whole reason this became a stateful
/// screen: the claims live on the access token, stamped at sign-in, so an approval that
/// landed a minute ago is invisible here until GoTrue rotates the token on its own — up to
/// an hour of an approved merchant reading that they have no shop, right after a
/// notification told them they had one.
class _NoAccess extends ConsumerStatefulWidget {
  const _NoAccess();

  @override
  ConsumerState<_NoAccess> createState() => _NoAccessState();
}

class _NoAccessState extends ConsumerState<_NoAccess> {
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final result = await ref.read(authServiceProvider).refreshSession();
    if (!mounted) return;
    setState(() => _busy = false);

    // On success the gate rebuilds by itself if anything changed, so the only thing worth
    // saying is that nothing did. A *failure* is a different sentence: telling somebody
    // their account is not activated when what actually happened is that the phone could
    // not reach the server sends them back to the telephone for nothing.
    final message = switch (result) {
      Ok() => () {
        final identity = ref.read(authServiceProvider).identity;
        if (identity != null && StaffIdentity.from(identity).role != null) return null;
        return 'لسه مفيش تفعيل على الحساب. جرّب تاني بعد المكالمة.';
      }(),
      Err(failure: OfflineFailure()) => 'مفيش اتصال بالإنترنت — اتأكد من الشبكة وجرّب تاني',
      Err() => 'مقدرناش نحدّث الحساب دلوقتي. جرّب تاني.',
    };
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
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
                'الحساب لسه مش مفعّل',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'لو قدّمت طلب انضمام، إدارة لقمة هتتصل بيك وتفعّل الحساب. أول ما يوصلك إن '
                'الحساب اتفعّل اضغط «حدّث الحساب».',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.luqma.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              FilledButton(
                key: MerchantApp.refreshAccessKey,
                onPressed: _busy ? null : _refresh,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(_busy ? 'لحظة…' : 'حدّث الحساب'),
              ),
              const SizedBox(height: Space.md),
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
