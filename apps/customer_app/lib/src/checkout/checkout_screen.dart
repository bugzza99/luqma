import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../address/address_editor_screen.dart';
import '../address/address_list_screen.dart';
import '../cart/cart.dart';
import '../cart/cart_controller.dart';

/// The last screen before an order exists.
///
/// The number here is money somebody will hand to a courier at a door, so it is broken
/// down rather than presented as one figure, and every reason the order could be refused
/// is settled on this screen instead of at the merchant an hour later.
///
/// What gets sent is a *draft* — the basket, the address, the note. Not a total: the
/// server recomputes that from the merchant's own menu, because a total computed on the
/// phone is a total anyone can edit, and the courier collects whatever the screen says.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.onPlaced,
    this.onSignIn,
  });

  final ValueChanged<Order> onPlaced;
  final VoidCallback? onSignIn;

  static const totalKey = Key('checkout.total');
  static const placeKey = Key('checkout.place');
  static const cashKey = Key('checkout.cash');
  static const noteKey = Key('checkout.note');
  static const phoneKey = Key('checkout.phone');
  static const errorKey = Key('checkout.error');
  static const signInKey = Key('checkout.signIn');
  static const needsAddressKey = Key('checkout.needsAddress');
  static const couponInputKey = Key('checkout.coupon');
  static const couponApplyKey = Key('checkout.coupon.apply');
  static const couponFeedbackKey = Key('checkout.coupon.feedback');
  static const billDiscountKey = Key('checkout.bill.discount');
  static const outOfRangeKey = Key('checkout.outOfRange');
  static const changeAddressKey = Key('checkout.changeAddress');

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _note = TextEditingController();
  final _coupon = TextEditingController();
  final _phone = TextEditingController();

  Failure? _failure;
  bool _sending = false;

  /// Set when the typed phone cannot be a mobile the courier can call. Cleared the
  /// moment the field changes, so a correction dismisses the error.
  String? _phoneError;

  /// The verdict the server returned for the typed code. An accepted one rides along
  /// on the draft; a rejected one is said out loud under the field.
  CouponEvaluation? _couponEvaluation;
  String? _appliedCouponCode;
  bool _checkingCoupon = false;

  @override
  void dispose() {
    _note.dispose();
    _coupon.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// One sentence per refusal, in the words a person answers to. "Expired" and "the
  /// order is too small" ask for two different next steps from the same customer.
  String _couponSentence(CouponRejection reason) => switch (reason) {
        CouponRejection.notFound => 'الكود ده مش موجود.',
        CouponRejection.inactive => 'الكود ده متوقف مؤقتًا.',
        CouponRejection.notYetValid => 'الكود ده لسه ما بدأش.',
        CouponRejection.expired => 'صلاحية الكود خلصت.',
        CouponRejection.minOrderNotMet =>
          'الطلب أقل من الحد الأدنى اللي الكود بيشتغل عليه.',
        CouponRejection.wrongMerchant => 'الكود ده مش للمطعم ده.',
        CouponRejection.firstOrderOnly => 'الكود ده لأول طلب بس.',
        CouponRejection.alreadyUsed => 'استخدمت الكود ده قبل كده.',
        CouponRejection.exhausted => 'خلص عدد استخدامات الكود.',
        CouponRejection.malformed => 'فيه مشكلة في إعداد الكود.',
      };

  Future<void> _applyCoupon(Cart cart, int deliveryFee) async {
    final code = _coupon.text.trim();
    if (code.isEmpty || cart.merchantId == null) return;

    setState(() => _checkingCoupon = true);

    // Priced by the server, not by this screen - the same arithmetic that will judge
    // the code again when the order is placed.
    final result = await ref.read(orderRepositoryProvider).evaluateCoupon(
          code: code,
          merchantId: cart.merchantId!,
          subtotal: cart.subtotal,
          deliveryFee: deliveryFee,
        );

    if (!mounted) return;

    final evaluation = result.valueOrNull;
    setState(() {
      _checkingCoupon = false;
      _couponEvaluation = evaluation;
      _appliedCouponCode =
          evaluation is CouponAccepted ? code.toUpperCase() : null;
    });
  }

  Future<void> _place(Cart cart, Address address, LuqmaIdentity identity) async {
    setState(() {
      _sending = true;
      _failure = null;
      _phoneError = null;
    });

    // A brand-new Google account has no phone, and a courier with nobody to call is a
    // courier who cannot deliver. The phone is captured once here, written to the user's
    // row, and then read back by place_order onto the order itself.
    final needsPhone = identity.phone?.trim().isEmpty ?? true;
    if (needsPhone) {
      final phone = _phone.text.trim();
      if (!Phone.isValidEgyptianMobile(phone)) {
        setState(() {
          _sending = false;
          _phoneError = 'اكتب رقم موبايل مصري صحيح — يبدأ بـ 01 ومكوّن من 11 رقم.';
        });
        return;
      }

      final saved = await ref.read(profileRepositoryProvider).savePhone(
            uid: identity.uid,
            phone: phone,
          );
      if (!mounted) return;
      if (saved is Err) {
        setState(() {
          _sending = false;
          _failure = saved.failure;
        });
        return;
      }
    }

    final note = _note.text.trim();
    final result = await ref.read(orderRepositoryProvider).placeOrder(
          OrderDraft(
            merchantId: cart.merchantId!,
            addressId: address.id,
            items: cart.toOrderLines(),
            type: OrderType.instant,
            // Only an accepted code rides along; the server judges it again regardless.
            couponCode: _appliedCouponCode,
            note: note.isEmpty ? null : note,
          ),
        );

    if (!mounted) return;

    switch (result) {
      // The basket survives a refusal. Emptying it would make the customer rebuild the
      // order from memory because the network dropped for two seconds.
      case Err(:final failure):
        setState(() {
          _sending = false;
          _failure = failure;
        });
      case Ok(:final value):
        // Emptied only once the order exists. Left full, the tracking screen would sit
        // above a basket offering to send the same order again.
        ref.read(cartProvider.notifier).clear();
        setState(() => _sending = false);
        widget.onPlaced(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    final identity = ref.watch(currentIdentityProvider).value;
    final cart = ref.watch(cartProvider);
    final address = ref.watch(chosenAddressProvider).value;
    final merchant =
        ref.watch(merchantProvider(cart.merchantId ?? '')).value;
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    final config = ref.watch(appConfigProvider);

    final zone = zones.where((z) => z.id == address?.zoneId).firstOrNull;
    final inRange = merchant != null &&
        address != null &&
        Delivery.serves(merchant: merchant, zoneId: address.zoneId);
    final deliveryFee = merchant != null && zone != null && inRange
        ? Delivery.feeFor(merchant: merchant, zone: zone, config: config)
        : 0;

    final acceptedCoupon =
        _couponEvaluation is CouponAccepted ? _couponEvaluation as CouponAccepted : null;
    final pricing = OrderPricing.compute(
      items: cart.toOrderLines(),
      deliveryFee: deliveryFee,
      coupon: acceptedCoupon,
    );

    final ready = identity != null &&
        merchant != null &&
        address != null &&
        inRange &&
        cart.isNotEmpty &&
        !_sending;

    // A Google account usually carries no phone. The courier needs one to call, so it is
    // asked here — once — and written to the user's row before the order goes out.
    final needsPhone = identity != null && (identity.phone?.trim().isEmpty ?? true);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('تأكيد الطلب')),
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
                    noticeKey: CheckoutScreen.errorKey,
                    icon: Icons.error_outline_rounded,
                    color: colors.danger,
                    text: switch (_failure!) {
                      OfflineFailure() =>
                        'مفيش نت دلوقتي. سلتك زي ما هي — جرّب تاني.',
                      ConflictFailure() =>
                        'حصل تغيير في الطلب. راجع السلة وجرّب تاني.',
                      PermissionFailure() => 'لازم تسجّل دخول عشان تبعت الطلب.',
                      _ => 'مقدرناش نبعت الطلب. سلتك زي ما هي — جرّب تاني.',
                    },
                  ),
                  const SizedBox(height: Space.lg),
                ],
                _AddressCard(address: address, zoneName: zone?.name),
                if (address == null) ...[
                  const SizedBox(height: Space.md),
                  _Notice(
                    noticeKey: CheckoutScreen.needsAddressKey,
                    icon: Icons.location_off_outlined,
                    color: colors.danger,
                    text: 'محتاجين عنوان عشان الأوردر يوصل.',
                  ),
                ] else if (!inRange) ...[
                  const SizedBox(height: Space.md),
                  _Notice(
                    noticeKey: CheckoutScreen.outOfRangeKey,
                    icon: Icons.wrong_location_outlined,
                    color: colors.danger,
                    // Found out here, not from a rejection an hour later.
                    text: '${merchant?.name ?? "المطعم"} مبيوصلش '
                        '${zone?.name ?? "المنطقة دي"}. غيّر العنوان أو اختار مطعم تاني.',
                  ),
                ],
                if (needsPhone) ...[
                  const SizedBox(height: Space.xl),
                  TextField(
                    key: CheckoutScreen.phoneKey,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    // The error lives under the field, where the correction is typed.
                    onChanged: (_) {
                      if (_phoneError != null) setState(() => _phoneError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'رقم الموبايل',
                      hintText: '01012345678',
                      errorText: _phoneError,
                    ),
                  ),
                ],
                const SizedBox(height: Space.xl),
                _Lines(cart: cart),
                const SizedBox(height: Space.xl),
                _Bill(pricing: pricing, hasAddress: address != null),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: CheckoutScreen.couponInputKey,
                        controller: _coupon,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'كود خصم (إن وجد)',
                          hintText: 'مثلاً LAUNCH',
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    FilledButton.tonal(
                      key: CheckoutScreen.couponApplyKey,
                      onPressed:
                          cart.isNotEmpty && !_checkingCoupon
                              ? () => _applyCoupon(cart, deliveryFee)
                              : null,
                      child: Text(_checkingCoupon ? 'جاري الفحص…' : 'طبّق'),
                    ),
                  ],
                ),
                if (_couponEvaluation != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    switch (_couponEvaluation!) {
                      CouponAccepted(:final total) =>
                        'تم تطبيق الخصم: وفرت ${LuqmaStrings.of(context).price(total)}.',
                      CouponRejected(:final reason) => _couponSentence(reason),
                    },
                    key: CheckoutScreen.couponFeedbackKey,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _couponEvaluation is CouponAccepted
                              ? colors.brand
                              : colors.danger,
                        ),
                  ),
                ],
                const SizedBox(height: Space.xl),
                _CashNote(),
                const SizedBox(height: Space.xl),
                TextField(
                  key: CheckoutScreen.noteKey,
                  controller: _note,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة للمطعم أو الدليفري',
                    hintText: 'الشقة فوق الصيدلية، مثلاً',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: identity == null
          ? null
          : _Footer(
              total: pricing.total,
              sending: _sending,
              onPlace:
                  ready ? () => _place(cart, address, identity) : null,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address?.label ?? 'التوصيل إلى',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  address?.format(zoneName: zoneName ?? '') ??
                      'لسه مفيش عنوان محفوظ',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            key: CheckoutScreen.changeAddressKey,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => address == null
                    ? const AddressEditorScreen()
                    : const AddressListScreen(),
              ),
            ),
            child: Text(address == null ? 'ضيف' : 'غيّر'),
          ),
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الطلب', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        for (final line in cart.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                Text(
                  '${line.quantity}×',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(line.name, style: theme.textTheme.bodyMedium),
                ),
                Text(
                  strings.price(line.lineTotal),
                  style: LuqmaType.priceSmall.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({required this.pricing, required this.hasAddress});

  final OrderPricing pricing;
  final bool hasAddress;

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
      child: Column(
        children: [
          _Line(label: 'الأكل', value: strings.price(pricing.subtotal)),
          const SizedBox(height: Space.sm),
          _Line(
            label: 'التوصيل',
            // Never a zero that looks like free delivery when the truth is that no
            // address has been chosen yet.
            value: hasAddress ? strings.price(pricing.deliveryFee) : '—',
          ),
          if (pricing.subtotalDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            _Line(
              key: CheckoutScreen.billDiscountKey,
              label: 'خصم الكود',
              value: '-${strings.price(pricing.subtotalDiscount)}',
              emphasis: true,
            ),
          ],
          if (pricing.deliveryDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            _Line(
              label: 'خصم التوصيل',
              value: '-${strings.price(pricing.deliveryDiscount)}',
              emphasis: true,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: Divider(height: 1),
          ),
          Row(
            key: CheckoutScreen.totalKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: theme.textTheme.titleMedium),
              Text(
                strings.price(pricing.total),
                style: LuqmaType.price.copyWith(color: colors.price),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: emphasis ? theme.luqma.brand : theme.luqma.textSecondary,
          ),
        ),
        Text(
          value,
          style: LuqmaType.priceSmall.copyWith(
            color: emphasis ? theme.luqma.brand : theme.luqma.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Cash is stated, never chosen.
///
/// A payment step with exactly one option is a screen that exists to be tapped through.
class _CashNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: CheckoutScreen.cashKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: colors.textPrimary, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              strings.cashOnDelivery,
              style: theme.textTheme.bodyMedium,
            ),
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.sending,
    required this.onPlace,
  });

  final int total;
  final bool sending;
  final VoidCallback? onPlace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

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
              // Repeated under the thumb, because the bill above may be scrolled away
              // at the moment the button is pressed.
              Text(
                '${strings.collectFromCustomer}: ${strings.price(total)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.sm),
              FilledButton(
                key: CheckoutScreen.placeKey,
                onPressed: onPlace,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(sending ? 'بنبعت الطلب…' : strings.placeOrder),
              ),
            ],
          ),
        ),
      ),
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
              'سجّل دخول عشان نعرف نوصّلك الطلب ونتابعه معاك.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              key: CheckoutScreen.signInKey,
              onPressed: onSignIn,
              child: const Text('سجّل دخول بجوجل'),
            ),
          ],
        ),
      ),
    );
  }
}
