import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'push.dart';

/// Says, on the screen that depends on them, when notifications are off.
///
/// The permission used to be asked for in `LuqmaPush._wire()` — in the first seconds of
/// the first launch, before anybody had been told what the alerts were for — and the
/// answer was thrown away. Android shows that dialog once and remembers a refusal for
/// good, so a merchant who tapped "Don't allow" while the splash was still up had a
/// phone that never rang and an app that never mentioned it. A quiet evening and a
/// broken alarm looked exactly the same.
///
/// Three states, three different things to say, and the third is the one that matters:
/// once refused, **asking again does nothing**, so offering a button that asks is
/// offering a dead end. That state gets the route through Settings instead.
///
/// [read] and [request] are injected so this is testable without Firebase, which a
/// `flutter test` process does not have. Both default to [LuqmaPush].
class LuqmaNotificationBanner extends StatefulWidget {
  const LuqmaNotificationBanner({
    super.key,
    required this.reason,
    this.margin = const EdgeInsets.only(bottom: Space.md),
    this.read = LuqmaPush.permission,
    this.request = LuqmaPush.requestPermission,
  });

  /// One sentence saying what this app's alerts are for, in this app's own words. A
  /// merchant is told about orders arriving; a customer, about their food.
  final String reason;

  /// Applied only when there is something to say. A screen that puts this above a list
  /// rather than inside a padded one supplies its own gutter here, and pays nothing for
  /// it on the ordinary day when notifications are simply on.
  final EdgeInsetsGeometry margin;

  final Future<LuqmaPushPermission> Function() read;
  final Future<LuqmaPushPermission> Function() request;

  static const bannerKey = Key('push.banner');
  static const enableKey = Key('push.enable');
  static const settingsPathKey = Key('push.settingsPath');

  @override
  State<LuqmaNotificationBanner> createState() => _LuqmaNotificationBannerState();
}

class _LuqmaNotificationBannerState extends State<LuqmaNotificationBanner>
    with WidgetsBindingObserver {
  LuqmaPushPermission? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Turning notifications on happens in Settings, which means leaving the app and
  /// coming back. Without re-reading on resume the banner would still be there,
  /// insisting alerts are off, after somebody had just switched them on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final permission = await widget.read();
    if (mounted) setState(() => _permission = permission);
  }

  Future<void> _enable() async {
    final permission = await widget.request();
    if (mounted) setState(() => _permission = permission);
  }

  @override
  Widget build(BuildContext context) {
    final permission = _permission;
    // Nothing to say while it is being read, when alerts work, or when this build has no
    // push at all — that last one is a developer's machine and CI, where a warning about
    // notifications would be a warning about nothing.
    if (permission == null ||
        permission == LuqmaPushPermission.granted ||
        permission == LuqmaPushPermission.unavailable) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).luqma;
    final refused = permission == LuqmaPushPermission.denied;

    return Card(
      key: LuqmaNotificationBanner.bannerKey,
      margin: widget.margin,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_off_outlined, color: colors.danger),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'التنبيهات مقفولة',
                    style: LuqmaType.cardTitle.copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(widget.reason, style: LuqmaType.body),
            const SizedBox(height: Space.md),
            if (refused)
              Text(
                key: LuqmaNotificationBanner.settingsPathKey,
                // A sentence, not a button. Android will not show its dialog a second
                // time, so the only thing that can change this is the phone's own
                // settings — and saying where they are beats a control that looks like
                // it does something and does not.
                'افتح إعدادات التليفون ← التطبيقات ← لقمة ← الإشعارات، وشغّلها.',
                style: LuqmaType.bodyStrong.copyWith(color: colors.textSecondary),
              )
            else
              FilledButton(
                key: LuqmaNotificationBanner.enableKey,
                onPressed: _enable,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
                child: const Text('شغّل التنبيهات'),
              ),
          ],
        ),
      ),
    );
  }
}
