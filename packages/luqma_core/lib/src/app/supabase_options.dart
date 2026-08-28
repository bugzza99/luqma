import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the backend lives, compiled into the binary.
///
/// The defaults point at the local stack, which sits a thousand above the Supabase port
/// defaults on this machine because Windows reserves 54084-54683 for Hyper-V — see
/// `supabase/config.toml`. Production values arrive as dart-defines at build time:
///
/// ```
/// flutter build apk --dart-define=LUQMA_SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
abstract final class LuqmaSupabase {
  static const url = String.fromEnvironment(
    'LUQMA_SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:55321',
  );

  /// Public by design: this is what every phone in the city carries. What a caller may
  /// *do* is decided by the policies, not by this string.
  ///
  /// A `sb_publishable_…` key, not the legacy `anon` JWT — the parameter it is handed to
  /// has been called `publishableKey` all along, and now it holds one.
  ///
  /// The difference is not cosmetic. The legacy `anon` and `service_role` keys are both
  /// signed by the project's single JWT secret, so revoking either one means rotating
  /// that secret and killing both — which takes every installed app down with it. The
  /// new keys are revoked one at a time. This project had to learn that the hard way:
  /// a release build shipped the production `service_role` key inside three APKs, and
  /// the only way to kill it under the old scheme was to break every install.
  ///
  /// The local default is still the demo *anon* JWT, because the local stack issues no
  /// publishable key. That is safe — it is the well-known demo value, worthless anywhere
  /// but a container on this machine.
  static const publishableKey = String.fromEnvironment(
    'LUQMA_SUPABASE_PUBLISHABLE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9s'
        'ZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMb'
        'lYTn_I0',
  );

  /// Whether this binary was built to talk to a real project but never given a key for
  /// it — the shape of a build that reaches the right address and is refused at every
  /// request, which is exactly how the first release of this app behaved.
  ///
  /// Read by `main()` so a misbuild announces itself instead of looking like an outage.
  static bool get isMisbuilt =>
      !url.contains('127.0.0.1') && publishableKey.contains('supabase-demo');

  static Future<SupabaseClient> initialize() async {
    // Refused here rather than discovered screen by screen.
    //
    // A binary pointed at a real project while carrying the local demo key reaches the
    // right address and is refused at every single request. That is not a subtle state:
    // it is three apps that install, launch, draw their shell, and then fail at the home
    // screen, at sign-in and at sign-up alike — which reads as "the servers are down"
    // and cost this project a long evening.
    //
    // The build script already refuses to ship such an APK. This is the same check on
    // the other side of the wall, because the build script is not the only way anybody
    // will ever run `flutter build`.
    if (isMisbuilt) {
      throw StateError(
        'Built for $url with the local demo key. Pass '
        '--dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY, or use tool/build-apks.ps1, '
        'which reads it from the linked project.',
      );
    }

    final options = SupabaseInitOptions(url: url, publishableKey: publishableKey);
    await Supabase.initialize(
      url: options.url,
      publishableKey: options.publishableKey,
    );
    return Supabase.instance.client;
  }
}

/// A named carrier for the two values [LuqmaSupabase.initialize] needs, so the class
/// above stays const-friendly.
class SupabaseInitOptions {
  const SupabaseInitOptions({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;
}
