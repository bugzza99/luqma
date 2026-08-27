import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Today's meal, from the cook's side.
///
/// The whole screen is three fields and a button, because it is filled in at nine in the
/// morning by somebody with one hand free. What it is, how many, how much — the
/// collection window has a sensible default and is changed only when it needs changing.
///
/// What is left is never editable. That number belongs to the server, which moves it in
/// a transaction as portions are reserved; a kitchen that could write it could sell the
/// same portion twice.
class MealsScreen extends ConsumerWidget {
  const MealsScreen({super.key});

  static const emptyKey = Key('meals.empty');
  static const errorKey = Key('meals.error');
  static const addKey = Key('meals.add');
  static const nameKey = Key('meals.name');
  static const priceKey = Key('meals.price');
  static const quantityKey = Key('meals.quantity');
  static const descriptionKey = Key('meals.description');
  static const saveKey = Key('meals.save');
  static const confirmCloseKey = Key('meals.confirmClose');

  static Key mealKey(String id) => Key('meals.meal.$id');
  static Key remainingKey(String id) => Key('meals.remaining.$id');
  static Key closeKey(String id) => Key('meals.close.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final colors = Theme.of(context).luqma;

    if (merchantId == null) return const SizedBox.shrink();

    final meals = ref.watch(merchantMealsProvider(merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('أكل النهارده')),
      body: switch (meals) {
        // First, and on `hasError`: a stream that fails before it has ever emitted stays
        // AsyncLoading with the error hanging off it, and a cook reading that as "no
        // meals" thinks nothing published.
        AsyncValue(hasError: true, :final error?) => LuqmaErrorView(key: MealsScreen.errorKey, failure: error, onRetry: () => ref.invalidate(merchantMealsProvider(merchantId))),
        AsyncValue(hasValue: true, :final value?) when value.isEmpty => const _Empty(),
        AsyncValue(hasValue: true, :final value?) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.gutter,
              Space.gutter,
              Space.xxxl * 2,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _MealCard(
              meal: value[i],
              isToday: value[i].date == ref.watch(todayProvider),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => _publish(context, ref, merchantId),
        icon: const Icon(Icons.add_rounded),
        label: const Text('انشر أكلة'),
      ),
    );
  }

  Future<void> _publish(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
  ) async {
    final meal = await showModalBottomSheet<DailyMeal>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealForm(
        merchantId: merchantId,
        cityId: ref.read(currentCityProvider),
        day: ref.read(todayProvider),
      ),
    );

    if (meal == null || !context.mounted) return;

    final result = await ref.read(dailyMealRepositoryProvider).saveMeal(meal);
    if (!context.mounted) return;

    if (result case Err()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مقدرناش ننشر الأكلة. جرّب تاني.')),
      );
    }
  }
}

class _MealCard extends ConsumerWidget {
  const _MealCard({required this.meal, required this.isToday});

  final DailyMeal meal;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final sold = meal.totalQty - meal.remainingOrZero;

    return Opacity(
      // Past days stay, dimmed. They are history, not a mistake to correct.
      opacity: isToday ? 1 : 0.62,
      child: Container(
        key: MealsScreen.mealKey(meal.id),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: isToday ? Elevations.card : Elevations.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(meal.name, style: theme.textTheme.titleMedium),
                ),
                Text(
                  strings.price(meal.price),
                  style: LuqmaType.priceSmall.copyWith(color: colors.price),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${meal.date} · الاستلام ${_window(meal)}',
              style: LuqmaType.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: Space.sm),
            Row(
              key: MealsScreen.remainingKey(meal.id),
              children: [
                Expanded(
                  child: Text(
                    // Sold, not just left: it is the number a cook actually wants at the
                    // end of a day, and it is what decides how much to cook tomorrow.
                    'اتباع $sold من ${meal.totalQty}',
                    style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                Text(
                  strings.portionsLeft(meal.remainingOrZero),
                  style: LuqmaType.bodySmall.copyWith(
                    color: meal.isSoldOut ? colors.danger : colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (meal.status == DailyMealStatus.closed) ...[
              const SizedBox(height: Space.sm),
              Text(
                'اتقفلت',
                style: LuqmaType.bodySmall.copyWith(color: colors.danger),
              ),
            ] else if (isToday) ...[
              const SizedBox(height: Space.md),
              OutlinedButton(
                key: MealsScreen.closeKey(meal.id),
                onPressed: () => _confirmClose(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
                child: const Text('اقفل الأكلة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _window(DailyMeal meal) {
    String clock(int minutes) {
      final hour = minutes ~/ 60;
      final display = hour % 12 == 0 ? 12 : hour % 12;
      return '$display:${(minutes % 60).toString().padLeft(2, '0')}';
    }

    return '${clock(meal.pickupWindowStart)} — ${clock(meal.pickupWindowEnd)}';
  }

  Future<void> _confirmClose(BuildContext context, WidgetRef ref) async {
    // Somebody who has sold ten of twenty and is closing up is throwing away sales.
    // Once is enough to ask, and the numbers are in the question.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تقفل الأكلة؟'),
        content: Text(
          'لسه فاضل ${meal.remainingOrZero} من ${meal.totalQty}. '
          'لو قفلتها مش هتظهر لحد تاني النهارده.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('سيبها'),
          ),
          FilledButton(
            key: MealsScreen.confirmCloseKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اقفلها'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) return;

    await ref
        .read(dailyMealRepositoryProvider)
        .setStatus(meal.id, DailyMealStatus.closed);
  }
}

/// Three fields and a window. Nothing else belongs here.
class _MealForm extends ConsumerStatefulWidget {
  const _MealForm({
    required this.merchantId,
    required this.cityId,
    required this.day,
  });

  final String merchantId;
  final String cityId;
  final String day;

  @override
  ConsumerState<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends ConsumerState<_MealForm> {
  /// The photograph, once one has been taken.
  ///
  /// A meal is published in the morning and gone by the evening, so its picture is the
  /// only thing a customer has to go on — there is no reputation attached to a dish that
  /// exists for one day.
  String? _mediaId;
  String? _mediaUrl;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  final _description = TextEditingController();

  /// One in the afternoon to four. What a home kitchen in Edku actually does, and a
  /// default that is right most days is worth more than a field that is always empty.
  int _start = 13 * 60;
  int _end = 16 * 60;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final price = Money.parse(_price.text);
    final quantity = int.tryParse(ArabicDigits.fold(_quantity.text).trim());
    if (price == null || quantity == null || quantity < 1) return;

    Navigator.of(context).pop(
      DailyMeal(
        id: '',
        merchantId: widget.merchantId,
        cityId: widget.cityId,
        name: _name.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        price: price,
        date: widget.day,
        totalQty: quantity,
        // Already cooked, so both counts start the same. Every reservation after this
        // moves the second one, and only the server may.
        remainingQty: quantity,
        mediaId: _mediaId,
        pickupWindowStart: _start,
        pickupWindowEnd: _end,
        status: DailyMealStatus.published,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('أكلة النهارده', style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.md),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: MealsScreen.nameKey,
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'الأكلة'),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? 'اكتب اسم الأكلة' : null,
                        ),
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: MealsScreen.priceKey,
                                controller: _price,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9٠-٩.,]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'سعر الطبق',
                                  suffixText: 'ج',
                                ),
                                validator: (v) => Money.parse(v ?? '') == null
                                    ? 'سعر مش مظبوط'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: TextFormField(
                                key: MealsScreen.quantityKey,
                                controller: _quantity,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'كام طبق',
                                ),
                                // A meal with no portions is not a meal.
                                validator: (v) {
                                  final n = int.tryParse(
                                    ArabicDigits.fold(v ?? '').trim(),
                                  );
                                  return n == null || n < 1 ? 'اكتب عدد الأطباق' : null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.md),
                        TextFormField(
                          key: MealsScreen.descriptionKey,
                          controller: _description,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'وصف (اختياري)',
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        _WindowPicker(
                          start: _start,
                          end: _end,
                          onChanged: (s, e) => setState(() {
                            _start = s;
                            _end = e;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                // A meal is published in the morning and gone by the evening, so its
                // photograph is the only thing a customer has to go on — there is no
                // reputation attached to a dish that exists for one day.
                MediaPicker(
                  kind: MediaKind.dailyMeal,
                  url: _mediaUrl,
                  name: _name.text.trim().isEmpty ? 'وجبة' : _name.text.trim(),
                  height: 140,
                  onUploaded: (media) => setState(() {
                    _mediaId = media.id;
                    _mediaUrl = media.url;
                  }),
                ),
                const SizedBox(height: Space.md),
                FilledButton(
                  key: MealsScreen.saveKey,
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('انشر'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final int start;
  final int end;
  final void Function(int start, int end) onChanged;

  /// The windows a home kitchen here actually uses. A free time picker for a choice
  /// with three real answers is three taps instead of one.
  static const windows = [
    (12 * 60, 15 * 60, '12 — 3'),
    (13 * 60, 16 * 60, '1 — 4'),
    (17 * 60, 20 * 60, '5 — 8'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'وقت الاستلام',
          style: LuqmaType.caption.copyWith(
            color: Theme.of(context).luqma.textSecondary,
          ),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final (s, e, label) in windows)
              ChoiceChip(
                label: Text(label),
                selected: start == s && end == e,
                onSelected: (_) => onChanged(s, e),
              ),
          ],
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: MealsScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.soup_kitchen_outlined,
              size: 56,
              color: theme.luqma.textSecondary,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'لسه منشرتش أكلة',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'قول بتطبخ إيه النهارده وكام طبق، والباقي علينا.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

