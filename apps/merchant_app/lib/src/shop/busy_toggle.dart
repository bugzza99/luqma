import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'hours_screen.dart';

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
  static const editHoursKey = Key('busy.editHours');
  static const blockedKey = Key('busy.blocked');
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

    // Rebuilt every minute, so a pause that has run out, or an opening hour that has
    // arrived, is shown without waiting for something else to change.
    ref.watch(minuteTickProvider);

    // The shared clock: both questions below are about the hour, and a widget that
    // reads the wall clock cannot be tested without waiting for one.
    final now = ref.watch(clockProvider)();
    final paused = merchant.pausedUntil != null && now.isBefore(merchant.pausedUntil!);
    // Asked separately from the pause: a shop can be shut because of the clock, and
    // offering to reopen it then would be offering something that does nothing.
    final withinHours = merchant.openingHours.any((w) => w.contains(now));

    if (!withinHours && !paused) return _Closed(merchantId: merchantId);
    if (paused) return _Paused(merchant: merchant);
    // The last question, and the one this screen used to skip: `acceptsOrdersAt` is
    // where the whole product agrees on whether a shop can take an order, and it says
    // no for two reasons that have nothing to do with the clock — the shop is not
    // approved, or a prepaid wallet has run out.
    //
    // Deriving "open" from hours alone meant a merchant whose credit had gone read a
    // green bar saying مفتوح وبتستقبل طلبات while `place_order` refused every single
    // customer with "merchant not accepting orders". They would have spent the evening
    // certain the app was broken, and been right that something was.
    if (!merchant.acceptsOrdersAt(now)) return const _Blocked();
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
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final minutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (sheetContext) {
        final now = ref.read(clockProvider)();
        final sheetTheme = Theme.of(sheetContext);
        final sheetColors = sheetTheme.luqma;
        final strings = LuqmaStrings.of(sheetContext);

        return SafeArea(
          key: BusyToggle.sheetKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              Space.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top drag handle from M06
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetColors.border,
                      borderRadius: Radii.pillAll,
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                // Header with icon circle and title/subtitle from M06
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sheetColors.price.withValues(alpha: 0.14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.pause_rounded,
                        size: Sizes.iconMd,
                        color: sheetColors.price,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إيقاف الطلبات مؤقتاً',
                            style: sheetTheme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            'هيتوقف ظهور محلك للعملاء. هيرجع تلقائياً بعد المدة اللي تختارها.',
                            style: LuqmaType.bodySmall.copyWith(
                              color: sheetColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // The radio cards from M06
                for (final choice in BusyToggle.choices) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: InkWell(
                      key: BusyToggle.choiceKey(choice),
                      onTap: () => Navigator.of(sheetContext).pop(choice),
                      borderRadius: Radii.cardAll,
                      child: Container(
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: sheetColors.card,
                          borderRadius: Radii.cardAll,
                          border: Border.all(color: sheetColors.hairline),
                          boxShadow: Elevations.card,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sheetColors.border,
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    strings.minutes(choice),
                                    style: LuqmaType.bodyStrong.copyWith(
                                      color: sheetColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'يرجع الساعة ${luqmaClockTime(now.add(Duration(minutes: choice)), strings)}',
                                    style: LuqmaType.bodySmall.copyWith(
                                      color: sheetColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (minutes == null) return;

    final result = await ref.read(merchantRepositoryProvider).setPausedUntil(
          merchantId,
          // The injected clock, so a test can pause the shop at a known moment and read
          // back a known `pausedUntil` — this value is written to the database and is
          // what every other screen derives "is the shop taking orders" from.
          ref.read(clockProvider)().add(Duration(minutes: minutes)),
        );
    ref.invalidate(merchantProvider(merchantId));
    // The result used to be thrown away: offline, the sheet closed, the bar stayed
    // green, and the owner believed the shop had stopped taking orders (C6).
    if (result.failureOrNull != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('مقدرناش نوقف الاستقبال — اتأكد من النت وجرّب تاني.')),
      );
    }
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
          final result =
              await ref.read(merchantRepositoryProvider).setPausedUntil(merchant.id, null);
          ref.invalidate(merchantProvider(merchant.id));
          if (result.failureOrNull != null && context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('مقدرناش نرجّع الاستقبال — اتأكد من النت وجرّب تاني.'),
              ),
            );
          }
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
  const _Closed({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return _Bar(
      barKey: BusyToggle.closedKey,
      background: colors.surface,
      foreground: colors.textPrimary,
      icon: Icons.schedule_rounded,
      title: 'مقفول حسب مواعيد الشغل',
      // Still no "open now" — the shop is outside the hours its owner set, and a button
      // that appeared to override that would either lie or silently rewrite the schedule.
      // What was missing is the way *to* the schedule: there was no editor anywhere, so
      // this bar named a reason the merchant had no means of acting on and the screen
      // was a dead end.
      trailing: TextButton(
        key: BusyToggle.editHoursKey,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HoursScreen(merchantId: merchantId),
          ),
        ),
        child: const Text('المواعيد'),
      ),
    );
  }
}

/// Open by the clock, and refused by the server anyway.
///
/// Deliberately does not say which of the two reasons it is. A merchant cannot fix
/// either from this screen — approval is the admin's and the wallet is a payment — so
/// the useful sentence is the one that sends them to a person rather than one that
/// names a mechanism they cannot reach.
class _Blocked extends StatelessWidget {
  const _Blocked();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return _Bar(
      barKey: BusyToggle.blockedKey,
      background: colors.danger,
      foreground: colors.onBrand,
      icon: Icons.report_problem_rounded,
      title: 'الطلبات موقوفة مؤقتاً — كلّم لقمة',
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
