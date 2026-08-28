import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../address/address_list_screen.dart';
import '../home/sections/home_kitchen_section.dart';

/// Reserving a portion.
///
/// A separate screen from the ordinary checkout, because a pre-order is a different
/// promise: one dated meal, collected in a window, from somebody who has already cooked
/// it. It never touches the basket — mixing a portion of today's محشي with a restaurant
/// order to be cooked now would produce something nobody can fulfil.
///
/// The reservation itself is a server transaction. Two people tapping the last portion
/// at the same moment is the whole reason `dailyMeals` exists as its own collection, and
/// no client can settle that race correctly.
class PreorderCheckoutScreen extends ConsumerStatefulWidget {
  const PreorderCheckoutScreen({
    super.key,
    required this.meal,
    required this.quantity,
    required this.onPlaced,
    this.onSignIn,
  });

  final DailyMeal meal;
  final int quantity;
  final ValueChanged<Order> onPlaced;
  final VoidCallback? onSignIn;

  static const reserveKey = Key('preorder.reserve');
  static const totalKey = Key('preorder.total');
  static const signInKey = Key('preorder.signIn');
  static const errorKey = Key('preorder.error');
  static const needsAddressKey = Key('preorder.needsAddress');
  static const outOfRangeKey = Key('preorder.outOfRange');
  static const addressKey = Key('preorder.address');
  static const pickupKey = Key('preorder.pickup');

  @override
  ConsumerState<PreorderCheckoutScreen> createState() =>
      _PreorderCheckoutScreenState();
}

class _PreorderCheckoutScreenState extends ConsumerState<PreorderCheckoutScreen> {
  final _note = TextEditingController();

  Failure? _failure;
  bool _sending = false;

  /// Whether this meal needs somewhere to send it.
  ///
  /// Only when Luqma's courier is carrying it. A meal the customer collects has nowhere
  /// to deliver to, and one arranged directly with the cook is between the two of them —
  /// demanding an address for either would be a step invented for a required field.
  bool get _needsAddress =>
      widget.meal.deliveryOption == DeliveryOption.platformCourier;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _reserve(Address? address) async {
    setState(() {
      _sending = true;
      _failure = null;
    });

    final meal = widget.meal;
    final note = _note.text.trim();

    final result = await ref.read(orderRepositoryProvider).placeOrder(
          OrderDraft(
            merchantId: meal.merchantId,
            dailyMealId: meal.id,
            addressId: address?.id,
            type: OrderType.preorder,
            items: [
              OrderLine(
                itemId: meal.id,
                name: meal.name,
                unitPrice: meal.price,
                quantity: widget.quantity,
              ),
            ],
            note: note.isEmpty ? null : note,
          ),
        );

    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() {
          _sending = false;
          _failure = failure;
        });
      case Ok(:final value):
        setState(() => _sending = false);
        widget.onPlaced(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final identity = ref.watch(currentIdentityProvider).value;
    final address = ref.watch(chosenAddressProvider).value;
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    final zone = zones.where((z) => z.id == address?.zoneId).firstOrNull;

    final meal = widget.meal;
    final cook = ref.watch(merchantProvider(meal.merchantId)).value;
    final total = meal.price * widget.quantity;

    // Having an address is not the same as being somewhere the cook delivers to.
    // `CheckoutScreen` has always made that distinction; this screen checked only that
    // an address existed, so a customer in a zone this kitchen does not serve could
    // confirm — and find out from a rejection instead of from the screen.
    final inRange = !_needsAddress ||
        (cook != null &&
            address != null &&
            Delivery.serves(merchant: cook, zoneId: address.zoneId));

    final ready = identity != null &&
        !_sending &&
        (!_needsAddress || address != null) &&
        inRange &&
        meal.canBeOrderedAt(ref.watch(clockProvider)());

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('تأكيد الحجز')),
      body: identity == null
          ? _SignedOut(onSignIn: widget.onSignIn)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.xxxl,
              ),
              children: [
                if (_failure != null) ...[
                  _Notice(
                    noticeKey: PreorderCheckoutScreen.errorKey,
                    icon: Icons.error_outline_rounded,
                    color: colors.danger,
                    text: switch (_failure!) {
                      OfflineFailure() => 'مفيش نت دلوقتي. جرّب تاني.',
                      // The race this whole collection exists for. Said as what it is,
                      // not as a generic failure: somebody got the last portion first.
                      ConflictFailure() =>
                        'للأسف الأكلة خلصت قبل ما تأكد. جرّب حاجة تانية.',
                      PermissionFailure() => 'لازم تسجّل دخول عشان تحجز.',
                      _ => 'مقدرناش نأكد الحجز. جرّب تاني.',
                    },
                  ),
                  const SizedBox(height: Space.lg),
                ],
                _MealSummary(meal: meal, quantity: widget.quantity),
                const SizedBox(height: Space.lg),
                _Collection(meal: meal),
                if (_needsAddress) ...[
                  const SizedBox(height: Space.lg),
                  _AddressCard(address: address, zoneName: zone?.name),
                  if (address == null) ...[
                    const SizedBox(height: Space.md),
                    _Notice(
                      noticeKey: PreorderCheckoutScreen.needsAddressKey,
                      icon: Icons.location_off_outlined,
                      color: colors.danger,
                      text: 'محتاجين عنوان عشان الأكلة توصلك.',
                    ),
                  ] else if (!inRange) ...[
                    const SizedBox(height: Space.md),
                    _Notice(
                      noticeKey: PreorderCheckoutScreen.outOfRangeKey,
                      icon: Icons.wrong_location_outlined,
                      color: colors.danger,
                      // Found out here, not from a rejection after the portion is gone.
                      text: '${cook?.name ?? "المطبخ"} مبيوصلش '
                          '${zone?.name ?? "المنطقة دي"}. غيّر العنوان.',
                    ),
                  ],
                ],
                const SizedBox(height: Space.lg),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة للمطبخ',
                    hintText: 'هاجي الساعة تلاتة، مثلاً',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: identity == null
          ? null
          : Container(
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
                        key: PreorderCheckoutScreen.totalKey,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // `Expanded`, because the label is a full sentence in Arabic
                          // and the price beside it is unbreakable. On a 360dp phone —
                          // which is most of them — the pair overflowed by 49px, and a
                          // test window of 800x600 is wide enough to hide that.
                          Expanded(
                            child: Text(
                              strings.cashOnDelivery,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ),
                          Text(
                            strings.price(total),
                            style: LuqmaType.price.copyWith(color: colors.price),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      FilledButton(
                        key: PreorderCheckoutScreen.reserveKey,
                        onPressed: ready ? () => _reserve(address) : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: Text(_sending ? 'بنأكد الحجز…' : 'أكّد الحجز'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _MealSummary extends StatelessWidget {
  const _MealSummary({required this.meal, required this.quantity});

  final DailyMeal meal;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Text(
            '$quantity×',
            style: LuqmaType.bodyStrong.copyWith(color: colors.brand),
          ),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(meal.name, style: theme.textTheme.titleMedium)),
          Text(
            strings.price(meal.price * quantity),
            style: LuqmaType.priceSmall.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// When and how the portion is handed over.
///
/// Repeated here even though the meal screen said it, because this is the last screen
/// before somebody commits — and "I did not realise I had to go and collect it" is the
/// complaint this repetition exists to prevent.
class _Collection extends StatelessWidget {
  const _Collection({required this.meal});

  final DailyMeal meal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final (key, icon, text) = switch (meal.deliveryOption) {
      DeliveryOption.pickup => (
          PreorderCheckoutScreen.pickupKey,
          Icons.storefront_outlined,
          'تستلمه بنفسك من المطبخ، ${formatWindow(meal)}.',
        ),
      DeliveryOption.platformCourier => (
          PreorderCheckoutScreen.addressKey,
          Icons.delivery_dining_outlined,
          'دليفري لقمة هيوصّلهولك في وقت الاستلام، ${formatWindow(meal)}.',
        ),
      DeliveryOption.sellerArrangement => (
          PreorderCheckoutScreen.pickupKey,
          Icons.handshake_outlined,
          'اتفق مع المطبخ على التوصيل، ${formatWindow(meal)}.',
        ),
    };

    return Container(
      key: key,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: colors.surface, borderRadius: Radii.cardAll),
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

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.zoneName});

  final Address? address;
  final String? zoneName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, color: colors.brand, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              address?.format(zoneName: zoneName ?? '') ?? 'لسه مفيش عنوان محفوظ',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddressListScreen()),
            ),
            child: Text(address == null ? 'ضيف' : 'غيّر'),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.noticeKey,
    required this.icon,
    required this.color,
    required this.text,
  });

  final Key noticeKey;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: noticeKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: Sizes.iconSm, color: color),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'خطوة واحدة وخلاص',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'سجّل دخول عشان نحجزلك الطبق ونعرف نرجعلك.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              key: PreorderCheckoutScreen.signInKey,
              onPressed: onSignIn,
              child: const Text('سجّل دخول بجوجل'),
            ),
          ],
        ),
      ),
    );
  }
}
