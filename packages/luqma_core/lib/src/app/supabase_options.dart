import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the backend lives, compiled into the binary.
///
/// The defaults point at the local stack, which sits a thousand above the Supabase port
/// defaults on this machine because Windows reserves 54084-54683 for Hyper-V — see
/// `supabase/config.toml`. Production values arrive as dart-defines at build time:
///
/// ```
/// flutter build apk --dart-define=LUQMA_SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=LUQMA_SUPABASE_ANON_KEY=eyJ...
/// ```
abstract final class LuqmaSupabase {
  static const url = String.fromEnvironment(
    'LUQMA_SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:55321',
  );

  /// Public by design: the anon key is what every visitor's browser would hold. What a
  /// caller may *do* is decided by the policies, not by this string.
  static const publishableKey = String.fromEnvironment(
    'LUQMA_SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9s'
        'ZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMb'
        'lYTn_I0',
  );

  static Future<SupabaseClient> initialize() async {
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
