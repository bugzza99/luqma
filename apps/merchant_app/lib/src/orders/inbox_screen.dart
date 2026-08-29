import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../alarm/order_alarm.dart';

/// Orders waiting for an answer.
///
/// The one screen this app exists for. A merchant who does not answer does not cook, and
/// somebody waits for food nobody started — so the card carries everything needed to
/// decide, and the decision is two taps from a hand that is holding something hot.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  static const emptyKey = Key('inbox.empty');
  static const silenceKey = Key('inbox.silence');
  static const errorKey = Key('inbox.error');
  static const prepSheetKey = Key('inbox.prepSheet');
  static const reasonSheetKey = Key('inbox.reasonSheet');

  static Key cardKey(String id) => Key('inbox.card.$id');
  static Key acceptKey(String id) => Key('inbox.accept.$id');
  static Key rejectKey(String id) => Key('inbox.reject.$id');
  static Key countdownKey(String id) => Key('inbox.countdown.$id');
  static Key lateKey(String id) => Key('inbox.late.$id');
  static Key newCustomerKey(String id) => Key('inbox.new.$id');
  static Key prepChoiceKey(int minutes) => Key('inbox.prep.$minutes');
  static Key reasonChoiceKey(int index) => Key('inbox.reason.$index');

  /// What a kitchen actually says when it accepts. Round numbers, because a merchant
  /// picking between 22 and 27 minutes is a merchant being asked a question they cannot
  /// answer that precisely.
  static const prepChoices = [15, 20, 30, 45, 60];

  /// The reasons an order actually gets refused here. Typing one with one hand while
  /// holding a pan is not going to happen, so the common ones are a single tap.
  static const rejectReasons = [
    'الصنف خلص',
    'المطعم زحمة دلوقتي',
    'العنوان بعيد',
    'قفلنا بدري النهارده',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final colors = Theme.of(context).luqma;

    if (merchantId == null) return const _NoMerchant();

    final incoming = ref.watch(incomingOrdersProvider(merchantId));
    final ringing = ref.watch(orderAlarmProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('الطلبات الجديدة'),
        // Across the whole bar, not a button in a corner. The sound has done its job the
        // moment somebody is looking, and making them hunt for accept first is exactly
        // what gets an app muted for good.
        bottom: ringing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(Sizes.minTarget + Space.md),
                child: _SilenceBar(
                  onSilence: () => ref.read(orderAlarmProvider.notifier).acknowledge(),
                ),
              )
            : null,
      ),
      // Matched on `hasError` rather than on the `AsyncError` type, and matched first.
      // A stream that fails before it ever emits stays `AsyncLoading` with the error
      // hanging off it, so an `AsyncError()` arm never fires and the screen spins for
      // ever on a dropped connection — which on this screen reads as a quiet evening.
      body: switch (incoming) {
        AsyncValue(hasError: true, :final error?) => LuqmaErrorView(key: InboxScreen.errorKey, failure: error, onRetry: () => ref.invalidate(incomingOrdersProvider(merchantId))),
        AsyncValue(hasValue: true, :final value?) when value.isEmpty => LuqmaEmptyView(
            key: InboxScreen.emptyKey,
            icon: Icons.check_circle_outline_rounded,
            title: 'مفيش طلبات مستنية',
            message: 'أول ما يجي طلب هتسمع صوت.',
          ),
        AsyncValue(hasValue: true, :final value?) => ListView.separated(
            padding: const EdgeInsets.all(Space.gutter),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _OrderCard(order: value[i]),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// The one thing on screen while the sound is going.
class _SilenceBar extends StatelessWidget {
  const _SilenceBar({required this.onSilence});

  final VoidCallback onSilence;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: FilledButton.icon(
        key: InboxScreen.silenceKey,
        onPressed: onSilence,
        icon: const Icon(Icons.notifications_off_outlined, size: Sizes.iconSm),
        label: const Text('استلمت — وقّف الصوت'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          // Dark text on the orange, never white: white on it is 3.03:1.
          foregroundColor: colors.onAccent,
          minimumSize: const Size.fromHeight(Sizes.minTarget),
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: InboxScreen.cardKey(order.id),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'طلب رقم ${order.orderNumber}',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        order.customerName,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                _Deadline(order: order),
              ],
            ),
          ),
          if (order.isNewCustomer)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
              child: _NewCustomerBadge(orderId: order.id, strings: strings),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The count first and loud. Cooking one of something when two
                        // were ordered is the mistake this layout exists to prevent.
                        Text(
                          '${item.quantity}×',
                          style: LuqmaType.bodyStrong.copyWith(color: colors.brand),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: theme.textTheme.bodyMedium),
                              if (item.note != null && item.note!.isNotEmpty)
                                Text(
                                  item.note!,
                                  style: LuqmaType.bodySmall
                                      .copyWith(color: colors.danger),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.sm),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      strings.collectFromCustomer,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    Text(
                      strings.price(order.pricing.total),
                      style: LuqmaType.price.copyWith(color: colors.price),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: InboxScreen.rejectKey(order.id),
                    onPressed: () => _reject(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.danger,
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: Text(strings.rejectOrder),
                  ),
                ),
                const SizedBox(width: Sizes.targetGap),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: InboxScreen.acceptKey(order.id),
                    onPressed: () => _accept(context, ref),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: Text(strings.acceptOrder),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      // Five targets at 56dp do not fit in the default sheet on a small phone, and the
      // last of them is the one a busy kitchen reaches for.
      isScrollControlled: true,
      builder: (sheetContext) => _ChoiceSheet(
        sheetKey: InboxScreen.prepSheetKey,
        title: 'هياخد قد إيه؟',
        children: [
          for (final choice in InboxScreen.prepChoices)
            _Choice(
              key: InboxScreen.prepChoiceKey(choice),
              label: LuqmaStrings.of(sheetContext).minutes(choice),
              onTap: () => Navigator.of(sheetContext).pop(choice),
            ),
        ],
      ),
    );

    if (minutes == null || !context.mounted) return;

    ref.read(orderAlarmProvider.notifier).acknowledge();
    final result = await ref
        .read(merchantOrderRepositoryProvider)
        .accept(order.id, prepMinutes: minutes);
    if (context.mounted) _reportIfFailed(context, result);
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ChoiceSheet(
        sheetKey: InboxScreen.reasonSheetKey,
        title: 'ليه الرفض؟',
        children: [
          for (var i = 0; i < InboxScreen.rejectReasons.length; i++)
            _Choice(
              key: InboxScreen.reasonChoiceKey(i),
              label: InboxScreen.rejectReasons[i],
              onTap: () =>
                  Navigator.of(sheetContext).pop(InboxScreen.rejectReasons[i]),
            ),
        ],
      ),
    );

    if (reason == null || !context.mounted) return;

    ref.read(orderAlarmProvider.notifier).acknowledge();
    final result =
        await ref.read(merchantOrderRepositoryProvider).reject(order.id, reason: reason);
    if (context.mounted) _reportIfFailed(context, result);
  }

  /// A refusal here means somebody else moved the order first — the customer cancelled,
  /// or the deadline task took it. Silence would leave the merchant tapping a button
  /// that appears to do nothing.
  void _reportIfFailed(BuildContext context, Result<void> result) {
    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            OfflineFailure() => 'مفيش نت — الطلب زي ما هو، جرّب تاني.',
            ConflictFailure() => 'الطلب ده اتغير. حدّث الشاشة وشوفه تاني.',
            _ => 'مقدرناش نحفظ ده. جرّب تاني.',
          }),
        ),
      );
    }
  }
}

/// The countdown to `acceptDeadlineAt`.
///
/// Computed on the device from a timestamp the server wrote, so nothing has to tick
/// server-side for this to be right. Instant orders only: a pre-order was accepted the
/// moment the seller published the meal, so a timer on it counts down to a deadline that
/// does not exist.
class _Deadline extends ConsumerStatefulWidget {
  const _Deadline({required this.order});

  final Order order;

  @override
  ConsumerState<_Deadline> createState() => _DeadlineState();
}

class _DeadlineState extends ConsumerState<_Deadline> {
  /// The shared clock. The countdown a merchant watches is the whole point of this
  /// widget, so a test that cannot move time can only check it by waiting in real
  /// seconds — which is how a suite starts taking minutes.
  DateTime get _now => ref.read(clockProvider)();

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Ticks only while there is something left to count.
  ///
  /// Past the deadline the pill says "late" and never changes again, so a timer running
  /// on it would redraw a fixed string once a second for as long as the order sits
  /// there — and would keep the screen from ever going idle.
  void _start() {
    final deadline = widget.order.acceptDeadlineAt;
    if (deadline == null || !deadline.isAfter(_now)) return;

    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (!deadline.isAfter(_now)) timer.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.order.acceptDeadlineAt;
    if (deadline == null) return const SizedBox.shrink();

    final colors = Theme.of(context).luqma;
    final left = deadline.difference(_now);

    if (left.isNegative) {
      // Not a negative timer. The order is still here and still wanted; what changed is
      // that it is now late, which is a different thing to say.
      return _Pill(
        pillKey: InboxScreen.lateKey(widget.order.id),
        text: 'متأخر',
        background: colors.danger,
        foreground: colors.onBrand,
      );
    }

    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;

    return _Pill(
      pillKey: InboxScreen.countdownKey(widget.order.id),
      text: '$minutes:${seconds.toString().padLeft(2, '0')}',
      // Under a minute the colour changes as well as the number: a merchant glancing
      // across a kitchen reads colour before digits.
      background: minutes < 1 ? colors.danger : colors.surface,
      foreground: minutes < 1 ? colors.onBrand : colors.textPrimary,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.pillKey,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final Key pillKey;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pillKey,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(color: background, borderRadius: Radii.pillAll),
      child: Text(
        text,
        style: LuqmaType.bodyStrong.copyWith(color: foreground),
      ),
    );
  }
}

/// A customer with no delivered order behind them.
///
/// The fake-order risk the whole cash model carries: nobody has paid anything, and a
/// courier can be sent to an address that does not want food. One phone call settles it.
class _NewCustomerBadge extends StatelessWidget {
  const _NewCustomerBadge({required this.orderId, required this.strings});

  final String orderId;
  final LuqmaStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      key: InboxScreen.newCustomerKey(orderId),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          Icon(Icons.phone_outlined, size: Sizes.iconSm, color: colors.onAccent),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              '${strings.newCustomer} — اتأكد بمكالمة قبل ما تطبخ',
              // Dark text on the orange, never white: white on this orange is 3.03:1.
              style: LuqmaType.bodySmall.copyWith(color: colors.onAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.sheetKey,
    required this.title,
    required this.children,
  });

  final Key sheetKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: sheetKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            // Scrolls rather than overflows: a short screen, a large system font, or one
            // more choice added later must not put an option out of reach.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sizes.targetGap),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          // Bigger than the 48dp floor: this is tapped with a thumb, in a hurry, by
          // somebody whose other hand is busy.
          minimumSize: const Size.fromHeight(56),
        ),
        child: Text(label, style: LuqmaType.button),
      ),
    );
  }
}


/// A staff account whose claim names no merchant.
///
/// It signs in fine and then reads nothing, so saying so beats an empty inbox that looks
/// like a quiet evening.
class _NoMerchant extends StatelessWidget {
  const _NoMerchant();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.luqma.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الحساب ده مش مربوط بمطعم',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'كلّم الإدارة عشان يربطوه.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.luqma.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
