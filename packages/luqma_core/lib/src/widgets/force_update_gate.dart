import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'luqma_lockup.dart';

/// The one screen that can stand between a person and the app.
///
/// Everything else the owner controls from AdminApp degrades gently — a flag turned off
/// hides a feature, a limit tightened shrinks a list. `minSupportedVersion` is the one
/// setting whose honest outcome is *this build does not get to run*: an old client that
/// talks to a changed API is not degraded, it is wrong, and every workaround for that
/// ends in the same place. So when it fires, the whole shell is replaced by this page —
/// no back door, because the version behind it is exactly the one being refused.
///
/// The check runs on the config as it stands, and again every time the app comes back
/// to the foreground with a fresh fetch behind it. The owner sets the bar from AdminApp;
/// a phone already sitting on the home screen finds out on its next resume rather than
/// at some arbitrary midnight.
class LuqmaForceUpdateGate extends ConsumerStatefulWidget {
  const LuqmaForceUpdateGate({
    super.key,
    required this.currentVersion,
    required this.storeUrl,
    required this.child,
  });

  /// The version this binary was installed as, e.g. `1.4.0`. Read once at start-up via
  /// package_info_plus and passed in — the gate stays a widget, not a plugin boundary.
  final String currentVersion;

  /// Where [LuqmaForceUpdateView] sends people. The Play Store listing for this app.
  final Uri storeUrl;

  final Widget child;

  @override
  ConsumerState<LuqmaForceUpdateGate> createState() =>
      _LuqmaForceUpdateGateState();
}

class _LuqmaForceUpdateGateState extends ConsumerState<LuqmaForceUpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The start-up fetch happens above this widget; refreshing here too means a phone
    // that was opened offline learns about a raised bar the moment it gets signal.
    ref.read(appConfigProvider.notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire and forget: the refresh never throws, and a failure simply leaves the last
      // good values standing — the same contract every other reader of the config has.
      ref.read(appConfigProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return config.requiresUpdate(widget.currentVersion)
        ? LuqmaForceUpdateView(storeUrl: widget.storeUrl)
        : widget.child;
  }
}

/// What the out-of-date build shows instead of itself.
///
/// One sentence saying why, one saying what survives, one button. Nothing else: this is
/// not a place to browse, and every extra affordance would read as "maybe I can get
/// around this".
class LuqmaForceUpdateView extends StatelessWidget {
  const LuqmaForceUpdateView({super.key, required this.storeUrl});

  final Uri storeUrl;

  Future<void> _openStore() async {
    // If the store cannot open — no Play Store on the device, a web build without the
    // handler — there is genuinely nowhere else to send this person, so the error is
    // swallowed rather than crashed on. The screen they are looking at still explains
    // what to do by hand.
    try {
      await launchUrl(storeUrl, mode: LaunchMode.externalApplication);
    } on Exception {
      // Deliberately silent; see above.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LuqmaLockup(),
                SizedBox(height: Space.xxl),
                Text(
                  strings.forceUpdateTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                SizedBox(height: Space.md),
                Text(
                  strings.forceUpdateBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.luqma.textSecondary,
                  ),
                ),
                SizedBox(height: Space.xxl),
                FilledButton.icon(
                  key: const Key('force-update.button'),
                  onPressed: _openStore,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(strings.forceUpdateButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
