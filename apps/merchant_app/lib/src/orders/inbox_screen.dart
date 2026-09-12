import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../alarm/order_alarm.dart';
import 'order_note.dart';

/// Orders waiting for an answer.
///
/// The one screen this app exists for. Restyled to M01: the order that needs an answer
/// is the whole screen, not a card in a list — a full-bleed treatment on burgundy, the
/// total in orange on a cream panel, a ring counting down to `acceptDeadlineAt`, and two
/// large, well-separated actions. The countdown is instant orders only: a pre-order has
/// no deadline.
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
  static Key ringKey(String id) => Key('inbox.ring.$id');
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

    return LuqmaAsyncView<List<Order>>(
      value: incoming,
      errorKey: InboxScreen.errorKey,
      onRetry: () => ref.invalidate(incomingOrdersProvider(merchantId)),
      empty: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('الطلبات الجديدة')),
        body: Column(
          children: [
            const LuqmaNotificationBanner(
              reason: 'من غيرها مش هتعرف إن فيه أوردر جديد إلا لما تفتح التطبيق '
                  'بنفسك — والعميل مستني رد في تسعين ثانية.',
              margin: EdgeInsets.all(Space.gutter),
            ),
            Expanded(
              child: LuqmaEmptyView(
                key: InboxScreen.emptyKey,
                icon: Icons.check_circle_outline_rounded,
                title: 'مفيش طلبات مستنية',
                message: 'أول ما يجي طلب هتسمع صوت.',
              ),
            ),
          ],
        ),
      ),
      isEmpty: (value) => value.isEmpty,
      builder: (context, value) {
        return Scaffold(
          backgroundColor: colors.brand,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (ringing)
                  _SilenceBar(
                    onSilence: () =>
                        ref.read(orderAlarmProvider.notifier).acknowledge(),
                  ),
                Expanded(
                  child: value.length == 1
                      ? _OrderView(
                          order: value.first,
                          index: 0,
                          totalCount: 1,
                        )
                      : PageView.builder(
                          itemCount: value.length,
                          itemBuilder: (context, i) => _OrderView(
                            order: value[i],
                            index: i,
                            totalCount: value.length,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
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
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
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

/// The full-screen M01 order view.
class _OrderView extends ConsumerWidget {
  const _OrderView({
    required this.order,
    required this.index,
    required this.totalCount,
  });

  final Order order;
  final int index;
  final int totalCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: InboxScreen.cardKey(order.id),
      color: colors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Burgundy Header: Urgent badge and order number.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xs),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.onBrand.withValues(alpha: 0.14),
                    borderRadius: Radii.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Space.xs + 2),
                      Text(
                        totalCount > 1
                            ? 'طلب جديد (${index + 1} من $totalCount) • عاجل'
                            : 'طلب جديد • عاجل',
                        style: LuqmaType.bodySmall.copyWith(
                          color: colors.onBrand,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'طلب رقم ${order.orderNumber}',
                  style: LuqmaType.screenTitle.copyWith(
                    color: colors.onBrand,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.type == OrderType.preorder
                      ? 'طلب مسبق'
                      : 'وصل للتو — بانتظار الرد',
                  style: LuqmaType.bodySmall.copyWith(
                    color: colors.onBrand.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),

          // Ring countdown: instant orders only — pre-orders carry no deadline.
          if (order.type == OrderType.instant && order.acceptDeadlineAt != null) ...[
            const SizedBox(height: Space.xs),
            _CountdownRing(order: order),
            const SizedBox(height: Space.xs),
          ] else ...[
            const SizedBox(height: Space.sm),
          ],

          // Cream Panel with rounded top corners.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: Radii.sheetTop,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Space.gutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Total order price in orange on cream.
                          _TotalHeader(total: order.pricing.total),
                          const SizedBox(height: Space.sm),

                          // First-time customer risk flag.
                          if (order.isNewCustomer) ...[
                            _NewCustomerBadge(
                              orderId: order.id,
                              strings: strings,
                            ),
                            const SizedBox(height: Space.sm),
                          ],

                          // Order lines with quantities and selected options.
                          for (final item in order.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity}×',
                                    style: LuqmaType.bodyStrong
                                        .copyWith(color: colors.brand),
                                  ),
                                  const SizedBox(width: Space.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name,
                                            style: theme.textTheme.bodyMedium),
                                        if (item.options.isNotEmpty)
                                          Text(
                                            item.options
                                                .map((o) => o.name)
                                                .join('، '),
                                            style: LuqmaType.bodySmall.copyWith(
                                                color: colors.textSecondary),
                                          ),
                                        if (item.note != null &&
                                            item.note!.isNotEmpty)
                                          Text(
                                            item.note!,
                                            style: LuqmaType.bodySmall.copyWith(
                                                color: colors.danger),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Customer note for the whole order.
                          OrderNote(note: order.note),

                          const SizedBox(height: Space.sm),

                          // Customer info card on white surface.
                          _CustomerCard(order: order),
                        ],
                      ),
                    ),
                  ),

                  // Two large well-separated bottom actions.
                  Container(
                    padding: const EdgeInsets.all(Space.gutter),
                    decoration: BoxDecoration(
                      color: colors.background,
                      border: Border(top: BorderSide(color: colors.hairline)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              key: InboxScreen.rejectKey(order.id),
                              onPressed: () => _reject(context, ref),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.danger,
                                side: BorderSide(color: colors.danger, width: 2),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: Radii.cardAll,
                                ),
                                minimumSize: const Size.fromHeight(56),
                              ),
                              child: Text(
                                strings.rejectOrder,
                                style: LuqmaType.button
                                    .copyWith(color: colors.danger),
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              key: InboxScreen.acceptKey(order.id),
                              onPressed: () => _accept(context, ref),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.success,
                                foregroundColor: colors.onBrand,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: Radii.cardAll,
                                ),
                                minimumSize: const Size.fromHeight(56),
                              ),
                              child: Text(
                                strings.acceptOrder,
                                style: LuqmaType.button
                                    .copyWith(color: colors.onBrand),
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
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
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
    final result = await ref
        .read(merchantOrderRepositoryProvider)
        .reject(order.id, reason: reason);
    if (context.mounted) _reportIfFailed(context, result);
  }

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

/// The circular countdown ring to `acceptDeadlineAt`.
class _CountdownRing extends ConsumerStatefulWidget {
  const _CountdownRing({required this.order});

  final Order order;

  @override
  ConsumerState<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends ConsumerState<_CountdownRing> {
  DateTime get _now => ref.read(clockProvider)();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

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
    final isLate = left.isNegative;

    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;

    // Normalizing countdown progress against the standard window.
    final totalSeconds = widget.order.placedAt != null
        ? deadline.difference(widget.order.placedAt!).inSeconds
        : 90;
    final validTotal = totalSeconds > 0 ? totalSeconds : 90;
    final progress = isLate ? 1.0 : (left.inSeconds / validTotal).clamp(0.0, 1.0);
    final activeColor = isLate
        ? colors.danger
        : (minutes < 1 ? colors.danger : colors.accent);

    return Center(
      child: SizedBox(
        key: InboxScreen.ringKey(widget.order.id),
        width: 116,
        height: 116,
        child: CustomPaint(
          painter: _RingPainter(
            progress: progress,
            trackColor: colors.onBrand.withValues(alpha: 0.18),
            progressColor: activeColor,
            strokeWidth: 7,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLate) ...[
                  Text(
                    'متأخر',
                    key: InboxScreen.lateKey(widget.order.id),
                    style: LuqmaType.sectionTitle.copyWith(
                      color: colors.onBrand,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'فات وقت القبول',
                    style: LuqmaType.caption.copyWith(
                      color: colors.onBrand.withValues(alpha: 0.8),
                    ),
                  ),
                ] else ...[
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    key: InboxScreen.countdownKey(widget.order.id),
                    style: LuqmaType.display.copyWith(
                      color: colors.onBrand,
                      fontSize: 28,
                    ),
                  ),
                  Text(
                    'باقي للقبول',
                    style: LuqmaType.caption.copyWith(
                      color: colors.onBrand.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 7.0,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.trackColor != trackColor;
}

/// The total in orange on the cream panel.
class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      padding: const EdgeInsets.only(bottom: Space.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        children: [
          Text(
            strings.collectFromCustomer,
            style: LuqmaType.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            strings.price(total),
            style: LuqmaType.display.copyWith(color: colors.price),
          ),
        ],
      ),
    );
  }
}

/// Customer details card on white surface.
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'العميل: ',
                style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              Expanded(
                child: Text(
                  order.customerName,
                  style: LuqmaType.body.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          if (order.address?.street != null && order.address!.street!.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Text(
                  'الشارع: ',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                Expanded(
                  child: Text(
                    order.address!.street!,
                    style: LuqmaType.body.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if ((order.address?.landmarkName ?? order.address?.landmarkNote) case final landmark?
              when landmark.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Text(
                  'معلم: ',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                Expanded(
                  child: Text(
                    landmark,
                    style: LuqmaType.body.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
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
