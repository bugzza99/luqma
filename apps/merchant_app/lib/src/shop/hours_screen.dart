import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// مواعيد الشغل — when this shop takes orders.
///
/// `merchants.opening_hours` has existed since the first schema and **nothing in any of
/// the three apps could write it**. Whether a shop can take an order is derived from
/// those hours — `Merchant.acceptsOrdersAt` — so a merchant whose hours were wrong, or
/// empty, was shut with no way to open. The busy toggle correctly offered nothing,
/// because a pause is a decision made two minutes ago and a schedule is not something a
/// pause may override.
///
/// It reached the owner as a shop stuck on "مقفول دلوقتي" and no control anywhere that
/// changed it.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key, required this.merchantId});

  final String merchantId;

  static const saveKey = Key('hours.save');

  /// Keyed by `DateTime.weekday` — Monday 1 … Sunday 7, the numbers
  /// `OpeningWindow.contains` actually compares against.
  static Key dayKey(int weekday) => Key('hours.day.$weekday');
  static Key openKey(int weekday) => Key('hours.open.$weekday');
  static Key closeKey(int weekday) => Key('hours.close.$weekday');

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  /// Open and close minutes per weekday, or absent for a day the shop is shut.
  ///
  /// Keyed 1..7 throughout. Nothing here ever produces a 0: `DateTime.weekday` has no
  /// such value, so a window written as one is matched by nothing at all — which is
  /// exactly what the seeded `0..6` data did, shutting every shop on Sundays and
  /// carrying one entry that could never fire.
  final Map<int, (int open, int close)> _days = {};

  bool _loaded = false;
  bool _saving = false;

  static const _dayNames = {
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
  };

  /// The week as it is read here, starting on Saturday.
  static const _weekOrder = [
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  /// What a day the merchant has just switched on defaults to.
  static const _defaultOpen = 10 * 60;
  static const _defaultClose = 23 * 60 + 59;

  void _loadOnce(Merchant merchant) {
    if (_loaded) return;
    _loaded = true;
    for (final window in merchant.openingHours) {
      _days[window.weekday] = (window.openMinute, window.closeMinute);
    }
  }

  Future<void> _save(Merchant merchant) async {
    setState(() => _saving = true);

    final hours = [
      for (final entry in _days.entries)
        OpeningWindow(
          weekday: entry.key,
          openMinute: entry.value.$1,
          closeMinute: entry.value.$2,
        ),
    ]..sort((a, b) => a.weekday.compareTo(b.weekday));

    final saved = await ref
        .read(merchantRepositoryProvider)
        .saveMerchant(merchant.copyWith(openingHours: hours));
    if (!mounted) return;
    setState(() => _saving = false);

    // The result is read rather than discarded. A merchant who taps save and sees nothing
    // has no idea whether their shop takes orders tonight.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(switch (saved) {
          Ok() => 'اتحفظت المواعيد.',
          Err() => 'المواعيد مااتحفظتش. جرّب تاني.',
        }),
      ),
    );
    if (saved case Ok()) {
      ref.invalidate(merchantProvider(widget.merchantId));
    }
  }

  Future<void> _pickTime(int weekday, {required bool opening}) async {
    final current = _days[weekday]!;
    final minutes = opening ? current.$1 : current.$2;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;

    setState(() {
      final chosen = picked.hour * 60 + picked.minute;
      _days[weekday] =
          opening ? (chosen, current.$2) : (current.$1, chosen);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final merchant = ref.watch(merchantProvider(widget.merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('مواعيد الشغل')),
      body: LuqmaAsyncView(
        value: merchant,
        onRetry: () => ref.invalidate(merchantProvider(widget.merchantId)),
        builder: (context, shop) {
          _loadOnce(shop);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(Space.gutter),
                  children: [
                    Text(
                      'المطعم بيستقبل طلبات في المواعيد دي بس.',
                      style: LuqmaType.bodySmall
                          .copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: Space.lg),
                    for (final weekday in _weekOrder) ...[
                      _Day(
                        weekday: weekday,
                        name: _dayNames[weekday]!,
                        hours: _days[weekday],
                        onToggle: (on) => setState(() {
                          if (on) {
                            _days[weekday] = (_defaultOpen, _defaultClose);
                          } else {
                            _days.remove(weekday);
                          }
                        }),
                        onOpen: () => _pickTime(weekday, opening: true),
                        onClose: () => _pickTime(weekday, opening: false),
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Space.gutter),
                  child: FilledButton(
                    key: HoursScreen.saveKey,
                    onPressed: _saving ? null : () => _save(shop),
                    child: const Text('احفظ'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.weekday,
    required this.name,
    required this.hours,
    required this.onToggle,
    required this.onOpen,
    required this.onClose,
  });

  final int weekday;
  final String name;

  /// Null when the shop is shut that day.
  final (int open, int close)? hours;

  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final open = hours != null;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
              Text(
                open ? 'فاتح' : 'مقفول',
                style: LuqmaType.bodySmall.copyWith(
                  color: open ? colors.success : colors.textSecondary,
                ),
              ),
              const SizedBox(width: Space.sm),
              Switch(
                key: HoursScreen.dayKey(weekday),
                value: open,
                onChanged: onToggle,
              ),
            ],
          ),
          if (hours case final h?) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: HoursScreen.openKey(weekday),
                    onPressed: onOpen,
                    child: Text('من ${_clock(h.$1)}'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton(
                    key: HoursScreen.closeKey(weekday),
                    onPressed: onClose,
                    child: Text('لـ ${_clock(h.$2)}'),
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
