import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/app/gallery.dart';
import 'src/app/push.dart';
import 'src/app/merchant_app.dart';
import 'src/courier/courier_write_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Crash reporting: silent without a DSN dart-define, so dev builds send nothing.
  await LuqmaTelemetry.init();
  final supabase = await LuqmaSupabase.initialize();
  // The version this install runs as, against minSupportedVersion.
  final info = await PackageInfo.fromPlatform();

  // Pull the owner's settings before the first frame, but never wait on them: the app
  // ships with a full set of defaults, so a cold start with no network renders a correct
  // app rather than a blank one.
  final config = RemoteConfigService(SupabaseConfigFetcher(supabase));
  unawaited(config.refresh());

  // The merchant's phone ringing when an order arrives — the one notification this
  // business depends on. Started from the same container the app runs on, so the token
  // it registers belongs to the session every screen is reading.
  //
  // Inert without google-services.json: a build that has never been given one still
  // runs, and says so once in the log rather than dying at launch.
  final container = ProviderContainer(
    overrides: [
      remoteConfigServiceProvider.overrideWithValue(config),
      authServiceProvider.overrideWithValue(SupabaseAuthService(supabase)),
      // The only place this app names the gallery; see src/app/gallery.dart.
      pickImageProvider.overrideWithValue(pickImageFromGallery),
      // The courier's write queue survives an app being killed: shared_preferences,
      // not memory.
      courierWriteStoreProvider.overrideWithValue(
        SharedPreferencesCourierWriteStore(),
      ),
    ],
  );
  unawaited(LuqmaPush.start(container.read(pushTokenRepositoryProvider)));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MerchantApp(currentVersion: info.version),
    ),
  );
}
