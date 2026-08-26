import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/app/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Crash reporting: silent without a DSN dart-define, so dev builds send nothing.
  await LuqmaTelemetry.init();
  final supabase = await LuqmaSupabase.initialize();
  // The version this install runs as, against minSupportedVersion.
  final info = await PackageInfo.fromPlatform();

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(SupabaseAuthService(supabase)),
      ],
      child: AdminApp(currentVersion: info.version),
    ),
  );
}

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
        currentVersion: currentVersion,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.luqma.admin',
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
