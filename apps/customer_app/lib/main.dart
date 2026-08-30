import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/shell/customer_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Crash reporting: silent without a DSN dart-define, so dev builds send nothing.
  await LuqmaTelemetry.init();
  final supabase = await LuqmaSupabase.initialize();
  // The version this install runs as, against minSupportedVersion. Read once here so
  // everything below it stays a plain widget.
  final info = await PackageInfo.fromPlatform();

  // Pull the owner's settings before the first frame, but never wait on them: the app
  // ships with a full set of defaults, so a cold start with no network renders a correct
  // app rather than a blank one.
  final config = RemoteConfigService(SupabaseConfigFetcher(supabase));
  unawaited(config.refresh());

  runApp(
    ProviderScope(
      overrides: [
        remoteConfigServiceProvider.overrideWithValue(config),
        authServiceProvider.overrideWithValue(SupabaseAuthService(supabase)),
        // The one place the build number is read. حسابي shows it for support calls, and
        // it comes from the package rather than a constant somebody has to remember to
        // bump — a second copy is a copy that eventually disagrees with the store.
        appVersionProvider
            .overrideWithValue('${info.version} (${info.buildNumber})'),
      ],
      child: CustomerApp(currentVersion: info.version),
    ),
  );
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, required this.currentVersion});

  /// What [LuqmaForceUpdateGate] compares against the owner's floor.
  final String currentVersion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لقمة',
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
        currentVersion: currentVersion,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.luqma.customer',
        ),
        child: const _Start(),
      ),
    );
  }
}

/// The splash, then the app.
///
/// One continuous screen: the lockup is drawn once and stays put while the session and
/// the first read resolve behind it. A second splash handing over to a third loading
/// screen is what makes a launch feel slow even when it is not.
class _Start extends ConsumerStatefulWidget {
  const _Start();

  @override
  ConsumerState<_Start> createState() => _StartState();
}

class _StartState extends ConsumerState<_Start> {
  // Started once, in initState: rebuilding would restart the wait on every frame.
  late final Future<void> _session = ref.read(authServiceProvider).restore();

  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    if (_ready) return const CustomerShell();

    return LuqmaSplash(
      // Held until the session has resolved one way or the other, so the first frame of
      // the app is never a signed-in customer being shown a signed-out home.
      ready: _session,
      minimumDuration: Duration(
        milliseconds: ref.read(appConfigProvider).splashMinMillis,
      ),
      onFinished: () => setState(() => _ready = true),
    );
  }
}
