import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../home/sections/home_kitchen_section.dart';

/// One home-cooked meal.
///
/// Not a menu item, and the screen is shaped by the difference. A menu item is a promise
/// to cook on demand; this is a count of portions somebody already cooked this morning.
/// So the two things at the top are how many are left and when they can be collected —
/// and reserving is capped by the count, because nobody can have more than exists.
///
/// A pre-order does **not** go in the basket. The basket is one restaurant's food to be
/// cooked now; this is one dated meal with a collection window, and mixing them would
/// produce an order nobody can fulfil.
class MealScreen extends ConsumerStatefulWidget {
  const MealScreen({super.key, required this.mealId, this.onReserve});

  final String mealId;

  /// Where reserving goes. Injected so the shell owns navigation, and so this screen is
  /// testable without one.
  final void Function(DailyMeal meal, int quantity)? onReserve;

  static const portionsKey = Key('mealScreen.portions');
  static const reserveKey = Key('mealScreen.reserve');
  static const lessKey = Key('mealScreen.less');
  static const moreKey = Key('mealScreen.more');
  static const quantityKey = Key('mealScreen.quantity');
  static const fulfilmentKey = Key('mealScreen.fulfilment');
  static const errorKey = Key('mealScreen.error');

  @override
  ConsumerState<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends ConsumerState<MealScreen> {
  int _quantity = 1;

  DailyMeal? _meal(List<DailyMeal> meals) =>
      meals.where((m) => m.id == widget.mealId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final meals = ref.watch(todaysMealsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('أكل بيتي')),
      body: switch (meals) {
        AsyncValue(hasError: true, :final error?) => _Error(failure: error),
        // A meal that is not in today's list is one the cook took down, or yesterday's
        // link. Far more common than a genuine error, and it needs its own sentence.
        AsyncValue(hasValue: true, :final value?) => _meal(value) == null
            ? const _Error(failure: NotFoundFailure())
            : _Loaded(
                meal: _meal(value)!,
                quantity: _quantity,
                onQuantity: (q) => setState(() => _quantity = q),
                onReserve: widget.onReserve,
              ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.meal,
    required this.quantity,
    required this.onQuantity,
    required this.onReserve,
  });

  final DailyMeal meal;
  final int quantity;
  final ValueChanged<int> onQuantity;
  final void Function(DailyMeal meal, int quantity)? onReserve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final kitchen = ref.watch(merchantProvider(meal.merchantId)).value;
    // From the shared clock, so this screen and the section behind it agree, and so
    // a test can stand inside the collection window without waiting for one.
    final canReserve = meal.canBeOrderedAt(ref.watch(clockProvider)());

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.xl,
            ),
            children: [
              Text(meal.name, style: theme.textTheme.headlineMedium),
              if (kitchen != null) ...[
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Icon(
                      Icons.soup_kitchen_outlined,
                      size: Sizes.iconSm,
                      color: colors.brand,
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      kitchen.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ],
              if (meal.description != null && meal.description!.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text(meal.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: Space.xl),

              // The two facts that decide everything on this screen.
              Container(
                key: MealScreen.portionsKey,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.portionsLeft(meal.remainingOrZero),
                      style: LuqmaType.bodyStrong.copyWith(
                        color: meal.isSoldOut ? colors.danger : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    PortionsMeter(
                      remaining: meal.remainingOrZero,
                      total: meal.totalQty,
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: Sizes.iconSm,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          'الاستلام ${formatWindow(meal)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              _Fulfilment(option: meal.deliveryOption),
            ],
          ),
        ),
        _Footer(
          meal: meal,
          quantity: quantity,
          canReserve: canReserve,
          onQuantity: onQuantity,
          onReserve: onReserve,
        ),
      ],
    );
  }
}

/// How the portion actually reaches the customer.
///
/// Said plainly and up front, because it is the thing that most often surprises somebody
/// about a home kitchen: there may be no delivery at all, and finding that out at
/// checkout is finding it out too late.
class _Fulfilment extends StatelessWidget {
  const _Fulfilment({required this.option});

  final DeliveryOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final (icon, text) = switch (option) {
      DeliveryOption.pickup => (
          Icons.storefront_outlined,
          'تستلمه بنفسك من المطبخ في وقت الاستلام.',
        ),
      DeliveryOption.platformCourier => (
          Icons.delivery_dining_outlined,
          'دليفري لقمة هيوصّلهولك.',
        ),
      DeliveryOption.sellerArrangement => (
          Icons.handshake_outlined,
          'الاتفاق على التوصيل بينك وبين المطبخ.',
        ),
    };

    return Container(
      key: MealScreen.fulfilmentKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          Icon(icon, size: Sizes.iconMd, color: colors.textPrimary),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.meal,
    required this.quantity,
    required this.canReserve,
    required this.onQuantity,
    required this.onReserve,
  });

  final DailyMeal meal;
  final int quantity;
  final bool canReserve;
  final ValueChanged<int> onQuantity;
  final void Function(DailyMeal meal, int quantity)? onReserve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    // Nobody can have more than exists. The cap is the count itself rather than a round
    // number, so the last two portions can still both be reserved by one person.
    final most = meal.remainingOrZero;
    final capped = quantity > most ? most : quantity;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Stepper(
                    quantity: capped,
                    canAdd: capped < most,
                    onLess: () => onQuantity(capped - 1),
                    onMore: () => onQuantity(capped + 1),
                  ),
                  const Spacer(),
                  Text(
                    strings.price(meal.price * (capped < 1 ? 1 : capped)),
                    style: LuqmaType.price.copyWith(color: colors.price),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              FilledButton(
                key: MealScreen.reserveKey,
                onPressed: canReserve && onReserve != null
                    ? () => onReserve!(meal, capped)
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(
                  meal.isSoldOut ? 'خلص النهارده' : 'احجز',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.canAdd,
    required this.onLess,
    required this.onMore,
  });

  final int quantity;
  final bool canAdd;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: MealScreen.lessKey,
            onPressed: quantity > 1 ? onLess : null,
            icon: const Icon(Icons.remove_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
          Text(
            '$quantity',
            key: MealScreen.quantityKey,
            style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          IconButton(
            key: MealScreen.moreKey,
            // Stops at what is left. Offering a fourth portion of three is an error
            // the customer only discovers after committing.
            onPressed: canAdd ? onMore : null,
            icon: const Icon(Icons.add_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);

    return Center(
      key: MealScreen.errorKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          switch (failure) {
            OfflineFailure() => strings.errorOffline,
            // Far more likely than a genuine error: the meal finished and the cook took
            // it down while somebody had the link open.
            NotFoundFailure() => 'الأكلة دي مش متاحة دلوقتي.',
            _ => strings.errorUnknown,
          },
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
