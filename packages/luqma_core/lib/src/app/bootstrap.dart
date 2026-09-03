import 'package:flutter/material.dart';

import 'telemetry.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/luqma_theme.dart';
import '../theme/typography.dart';

/// Starts an app, and shows something when starting fails.
///
/// Each `main` awaits three or four things before `runApp` — Sentry, Supabase, the
/// package version — and none of it was inside a `try`. An async `main` whose body throws
/// simply never reaches `runApp`: Android shows the launch theme for an instant and the
/// process ends. To whoever is holding the phone that is indistinguishable from tapping
/// the icon and nothing happening, and there is no screen, no message, and nowhere to
/// report it from.
///
/// It is not hypothetical. `SentryFlutter.init` and `Supabase.initialize` are platform
/// channels and secure storage on somebody else's Android build; the first of them runs
/// *before* Sentry is up, so a failure there is invisible to crash reporting as well.
///
/// So the whole start-up runs in here. It either produces a widget or it produces a
/// screen that says so.
Future<void> luqmaBootstrap(Future<Widget> Function() start) async {
  // The binding first and outside the guard: everything below needs it, including the
  // failure screen, and if this throws there is no Flutter left to draw with.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    runApp(await start());
  } catch (error, stackTrace) {
    debugPrint('Luqma failed to start: $error\n$stackTrace');
    // Reported, not merely drawn.
    //
    // Catching this is better for the customer and strictly worse for us: the throw used
    // to reach Sentry as `fatal` through `PlatformDispatcher.onError`, and handling it
    // means that stops arriving. The launch crash this guard exists because of was found
    // within a day precisely because Sentry reported it — so the report has to be made
    // explicitly here, or the next one is found by somebody's phone instead.
    //
    // A no-op without a DSN, and reached after the failure screen is already decided, so
    // a telemetry stack that is itself broken cannot stop the app drawing one.
    LuqmaTelemetry.error(error, stackTrace, context: 'startup');
    runApp(LuqmaStartupFailure(error: error));
  }
}

/// What a failed start looks like.
///
/// Deliberately built from almost nothing: the reason the app is on this screen may be
/// that something it normally depends on did not come up, so this must not need anything
/// beyond Flutter itself and the compiled-in theme.
///
/// There is no retry button. Re-running the start-up in place would mean initialising
/// Sentry and Supabase a second time in a process where they may already be half up, and
/// this codebase's rule is that a control which might do nothing is worse than none.
/// Closing and reopening is a thing anybody can do and that genuinely starts over.
class LuqmaStartupFailure extends StatelessWidget {
  const LuqmaStartupFailure({super.key, required this.error});

  final Object error;

  static const messageKey = Key('startupFailure.message');
  static const detailKey = Key('startupFailure.detail');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: LuqmaTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final colors = theme.luqma;

            return Scaffold(
              backgroundColor: colors.background,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: Sizes.iconLg * 2,
                          color: colors.brand,
                        ),
                        const SizedBox(height: Space.lg),
                        Text(
                          'التطبيق مقدرش يفتح',
                          key: messageKey,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          // What to actually do, rather than an apology. Closing and
                          // reopening fixes the transient causes, and the rest need
                          // somebody told.
                          'اقفل التطبيق وافتحه تاني. لو الرسالة فضلت تظهر، كلّمنا.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: Space.lg),
                        // The exception itself, small and last. Nobody in Edku will read
                        // it, and the one person who needs it is whoever they call — for
                        // whom "التطبيق مش بيفتح" alone is close to unactionable.
                        Text(
                          '$error',
                          key: detailKey,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: LuqmaType.caption
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
