import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/app/gallery.dart';
import 'src/app/router.dart';

/// Wrapped, so a start-up that fails says so instead of vanishing.
///
/// Everything below is awaited before the first frame, and an async `main` whose body
/// throws never reaches `runApp` — Android shows the launch theme for an instant and the
/// process ends, which is indistinguishable from tapping the icon and nothing happening.
void main() => luqmaBootstrap(() async {
  // Crash reporting: silent without a DSN dart-define, so dev builds send nothing.
  await LuqmaTelemetry.init();
  final supabase = await LuqmaSupabase.initialize();
  // The version this install runs as, against minSupportedVersion.
  final info = await PackageInfo.fromPlatform();

  final pushTokens = SupabasePushTokenRepository(supabase);
  PushTokenRegistration? pushRegistration;
  final auth = SupabaseAuthService(
    supabase,
    beforeSignOut: () async {
      await pushRegistration?.forgetRegisteredToken();
    },
  );

  final container = ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      // A shop's money is read here, through merchant_money (A6).
      readsShopMoneyProvider.overrideWithValue(true),
      pushTokenRepositoryProvider.overrideWithValue(pushTokens),
      // The only place this app names the gallery; see src/app/gallery.dart.
      pickImageProvider.overrideWithValue(pickImageFromGallery),
      // The same shape the customer app shows on حسابي. Read here by the config screen,
      // which must not let a minimum version be set above the newest one that exists.
      appVersionProvider.overrideWithValue(
        '${info.version} (${info.buildNumber})',
      ),
      // The owner's own photographs are on the product the moment they upload; the
      // database allows it from an admin and from nobody else.
      uploadsArriveApprovedProvider.overrideWithValue(true),
    ],
  );

  // The admin is the second line, and the only one there is. An order reaching
  // `needsAttention` means the merchant's own alarm already fired and was missed, so
  // there is nobody after this — which is why it comes on the critical channel rather
  // than the quiet one the customer gets.
  unawaited(LuqmaPush.start());
  pushRegistration = keepPushTokenRegistered(
    identities: container.read(authServiceProvider).changes,
    repository: container.read(pushTokenRepositoryProvider),
    token: LuqmaPush.token,
    refreshes: LuqmaPush.tokenRefreshes,
  );

  return UncontrolledProviderScope(
    container: container,
    child: AdminApp(currentVersion: info.version),
  );
});

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key, required this.currentVersion});

  /// What [LuqmaForceUpdateGate] compares against the owner's floor.
  final String currentVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'لقمة — الأدمن',
      debugShowCheckedModeBanner: false,
      theme: LuqmaTheme.light,
      darkTheme: LuqmaTheme.dark,
      routerConfig: ref.watch(routerProvider),
      // Arabic only, and right-to-left everywhere. There is no English build to fall
      // back to, so the locale is fixed rather than following the device.
      locale: const Locale('ar'),
      supportedLocales: LuqmaStrings.supportedLocales,
      localizationsDelegates: const [
        ...LuqmaStrings.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The gate sits under the navigator rather than in it: it has no route of its
      // own and must out-rank every screen the router could put up.
      builder: (context, child) => LuqmaForceUpdateGate(
        app: LuqmaApp.admin,
        currentVersion: currentVersion,
        // What the owner changes elsewhere — from another phone, or another tab of the
        // browser — reaches this screen without a restart. See LuqmaLiveRefresh.
        child: LuqmaLiveRefresh(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
