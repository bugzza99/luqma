import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Whether this kitchen is taking orders, and the one control that changes it.
///
/// Pausing writes a **timestamp**, never a flag. A flag produces merchants stuck closed
/// for days because nobody remembered to undo it — and by the time anyone notices, the
/// evidence is a week of orders that never arrived.
///
/// Three states, and two of them are not the same thing: *closed* is the schedule the
/// owner set, *busy* is a decision made two minutes ago. Conflating them would offer to
/// "reopen" a shop at three in the morning.
class BusyToggle extends ConsumerWidget {
  const BusyToggle({super.key});

  static const openKey = Key('busy.open');
  static const pausedKey = Key('busy.paused');
  static const closedKey = Key('busy.closed');
  static const pauseKey = Key('busy.pause');
  static const resumeKey = Key('busy.resume');
  static const sheetKey = Key('busy.sheet');

  static Key choiceKey(int minutes) => Key('busy.choice.$minutes');

  /// How long a rush lasts, as somebody in one would answer.
  static const choices = [30, 60, 120];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    if (merchantId == null) return const SizedBox.shrink();

    final merchant = ref.watch(merchantProvider(merchantId)).value;
    if (merchant == null) return const SizedBox.shrink();

    // The shared clock: both questions below are about the hour, and a widget that
    // reads the wall clock cannot be tested without waiting for one.
    final now = ref.watch(clockProvider)();
    final paused = merchant.pausedUntil != null && now.isBefore(merchant.pausedUntil!);
    // Asked separately from the pause: a shop can be shut because of the clock, and
    // offering to reopen it then would be offering something that does nothing.
    final withinHours = merchant.openingHours.any((w) => w.contains(now));

    if (!withinHours && !paused) return const _Closed();
    if (paused) return _Paused(merchant: merchant);
    return _Open(merchantId: merchantId);
  }
}

class _Open extends ConsumerWidget {
  const _Open({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return _Bar(
      barKey: BusyToggle.openKey,
      background: colors.success,
      icon: Icons.storefront_rounded,
      title: 'مفتوح وبتستقبل طلبات',
      trailing: OutlinedButton(
        key: BusyToggle.pauseKey,
        onPressed: () => _pause(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onBrand,
          side: BorderSide(color: colors.onBrand.withValues(alpha: 0.6)),
          minimumSize: const Size(0, Sizes.minTarget),
        ),
        child: Text(strings.busyToggle),
      ),
    );
  }

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        key: BusyToggle.sheetKey,
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'توقف قد إيه؟',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'هترجع تستقبل طلبات لوحدها بعد المدة دي.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetContext).luqma.textSecondary,
                    ),
              ),
              const SizedBox(height: Space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final choice in BusyToggle.choices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Sizes.targetGap),
                          child: OutlinedButton(
                            key: BusyToggle.choiceKey(choice),
                            onPressed: () => Navigator.of(sheetContext).pop(choice),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            child: Text(
                              LuqmaStrings.of(sheetContext).minutes(choice),
                              style: LuqmaType.button,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (minutes == null) return;

    await ref.read(merchantRepositoryProvider).setPausedUntil(
          merchantId,
          // The injected clock, so a test can pause the shop at a known moment and read
          // back a known `pausedUntil` — this value is written to the database and is
          // what every other screen derives "is the shop taking orders" from.
          ref.read(clockProvider)().add(Duration(minutes: minutes)),
        );
    ref.invalidate(merchantProvider(merchantId));
  }
}

class _Paused extends ConsumerWidget {
  const _Paused({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    // How long the merchant is told the pause has left. Read from `clockProvider` so a
    // test can stand at the boundary — the minute before it lapses and the minute after
    // — rather than only wherever the machine's wall clock happens to be.
    final left =
        merchant.pausedUntil!.difference(ref.watch(clockProvider)()).inMinutes + 1;
    final strings = LuqmaStrings.of(context);

    return _Bar(
      barKey: BusyToggle.pausedKey,
      background: colors.accent,
      foreground: colors.onAccent,
      icon: Icons.pause_circle_outline_rounded,
      // Says until when. "Paused" on its own leaves somebody wondering whether they
      // have to remember to come back.
      title: 'متوقف — هترجع بعد ${strings.minutes(left)}',
      trailing: OutlinedButton(
        key: BusyToggle.resumeKey,
        onPressed: () async {
          // Somebody who cleared the rush should not have to wait out a timer they set.
          await ref.read(merchantRepositoryProvider).setPausedUntil(merchant.id, null);
          ref.invalidate(merchantProvider(merchant.id));
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onAccent,
          side: BorderSide(color: colors.onAccent.withValues(alpha: 0.5)),
          minimumSize: const Size(0, Sizes.minTarget),
        ),
        child: const Text('ارجع اشتغل'),
      ),
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return _Bar(
      barKey: BusyToggle.closedKey,
      background: colors.surface,
      foreground: colors.textPrimary,
      icon: Icons.schedule_rounded,
      // No "reopen" here. The shop is outside the hours its owner set, and a button
      // that appears to override that would either lie or overwrite the schedule.
      title: 'مقفول حسب مواعيد الشغل',
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.barKey,
    required this.background,
    required this.icon,
    required this.title,
    this.foreground,
    this.trailing,
  });

  final Key barKey;
  final Color background;
  final Color? foreground;
  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final onColor = foreground ?? colors.onBrand;

    return Container(
      key: barKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.md,
      ),
      color: background,
      child: Row(
        children: [
          Icon(icon, color: onColor, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              title,
              style: LuqmaType.bodyStrong.copyWith(color: onColor),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Space.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
