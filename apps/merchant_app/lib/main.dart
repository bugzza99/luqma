import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'src/app/merchant_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: LuqmaFirebase.merchant);
  await Emulators.connect();

  // Pull the owner's settings before the first frame, but never wait on them: the app
  // ships with a full set of defaults, so a cold start with no network renders a correct
  // app rather than a blank one.
  final config = RemoteConfigService(
    FirebaseConfigFetcher(FirebaseRemoteConfig.instance),
  );
  unawaited(config.refresh());

  runApp(
    ProviderScope(
      overrides: [
        remoteConfigServiceProvider.overrideWithValue(config),
        // No Google Sign-In here: a merchant account is created for somebody by the
        // owner, so there is no credential source to hand over.
        authServiceProvider.overrideWithValue(
          FirebaseAuthService(
            FirebaseAuth.instance,
            googleCredential: () async => null,
          ),
        ),
      ],
      child: const MerchantApp(),
    ),
  );
}
