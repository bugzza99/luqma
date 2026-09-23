import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'checkout_key.dart';
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
  static const couponRemoveKey = Key('checkout.coupon.remove');
  static const couponCardKey = Key('checkout.coupon.card');
  static const linesKey = Key('checkout.lines');

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _note = TextEditingController();
  final _coupon = TextEditingController();
  final _phone = TextEditingController();

  /// The list, so a refusal can bring its sentence into view. The sentence sits at the
  /// top and the button that failed is in the footer: somebody who had scrolled down to
  /// the coupon or the note saw the button come back and nothing else, and read it as the
  /// tap not having registered.
  final _scroll = ScrollController();

  Failure? _failure;
  bool _sending = false;

  /// Set when the typed phone cannot be a mobile the courier can call. Cleared the
  /// moment the field changes, so a correction dismisses the error.
  String? _phoneError;

  /// The verdict the server returned for the typed code. An accepted one rides along
  /// on the draft; a rejected one is said out loud under the field.
  CouponEvaluation? _couponEvaluation;
  String? _appliedCouponCode;

  /// The delivery fee the coupon was judged against.
  ///
  /// A verdict is only true for the basket it was given. Change the address and the fee
  /// changes with the zone — and a free-delivery coupon that was worth 10 EGP is now
  /// worth 15, or the minimum it cleared no longer clears. The old verdict stays on
  /// screen looking settled while the number under it has moved.
  int? _couponJudgedAgainstFee;
  bool _checkingCoupon = false;
  bool _couponCheckFailed = false;

  @override
  void dispose() {
    _note.dispose();
    _coupon.dispose();
    _phone.dispose();
    _scroll.dispose();
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
      // No answer is an answer to say (B11): the spinner stopping with nothing else on
      // the screen read as a code the server had silently ignored.
      _couponCheckFailed = result.failureOrNull != null;
      _couponEvaluation = evaluation;
      _couponJudgedAgainstFee = deliveryFee;
      _appliedCouponCode =
          evaluation is CouponAccepted ? code.toUpperCase() : null;
    });
  }

  /// The screen renders from `_couponEvaluation` and `_place` sends `_appliedCouponCode`,
  /// so clearing one and not the other is a discount the customer can see and will not be
  /// given, or one they are given and cannot see. The courier collects cash at a door
  /// against the number on this screen; the two must not be able to disagree.
  void _removeCoupon() {
    setState(() {
      _couponEvaluation = null;
      _appliedCouponCode = null;
      _couponJudgedAgainstFee = null;
      _coupon.clear();
    });
  }

  Future<void> _place(
    Cart cart,
    Address address,
    LuqmaIdentity identity, {
    required int shownTotal,
  }) async {
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
            // Made with this screen, not this tap. A failed response enables the same
            // button again, and the retry must still name the order the server may have
            // already made.
            clientOrderId: ref.read(checkoutKeyProvider.notifier).keyFor(cart),
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
        LuqmaTelemetry.event('order.failed', data: {
          'failure': failure.runtimeType.toString(),
        });
        setState(() {
          _sending = false;
          _failure = failure;
          // A code the server refused at placement comes off the order, with its
          // reason in the coupon slot. Left on, every retry re-sent the dead code and
          // failed again — with a sentence about the network — until the customer
          // happened to tap «شيل».
          if (failure is CouponFailure) {
            _couponEvaluation = CouponRejected(failure.reason);
            _appliedCouponCode = null;
          }
        });
        if (_scroll.hasClients && _scroll.offset > 0) {
          await _scroll.animateTo(
            0,
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      case Ok(:final value):
        LuqmaTelemetry.event('order.placed', data: {
          'type': value.type.name,
          'items': cart.toOrderLines().length,
        });
        // Emptied only once the order exists. Left full, the tracking screen would sit
        // above a basket offering to send the same order again.
        ref.read(cartProvider.notifier).clear();
        setState(() => _sending = false);
        // The basket keeps the price a dish had when it went in, and the server priced it
        // again from the menu. When they differ the server's figure is the one the courier
        // collects — and the customer, who was shown the other, is told now rather than
        // at the door (B5). On the app's own messenger, so it outlives this screen.
        if (value.pricing.total != shownTotal) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              content: Text(
                'الإجمالي النهائي ${LuqmaStrings.of(context).price(value.pricing.total)} '
                '— اتغيّر عن اللي كان ظاهر لأن الأسعار اتحدّثت.',
              ),
            ),
          );
        }
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

    // Dropped the moment the fee it was judged against is no longer the fee. The
    // customer re-applies the code, which is a keystroke; the alternative is a total
    // that does not match what the server will charge.
    if (_couponJudgedAgainstFee != null && _couponJudgedAgainstFee != deliveryFee) {
      _couponEvaluation = null;
      _appliedCouponCode = null;
      _couponJudgedAgainstFee = null;
    }

    final acceptedCoupon =
        _couponEvaluation is CouponAccepted ? _couponEvaluation as CouponAccepted : null;
    final pricing = OrderPricing.compute(
      items: cart.toOrderLines(),
      deliveryFee: deliveryFee,
      coupon: acceptedCoupon,
    );

    // The fee is the zone's, and without the zone list there is no fee to show — only a
    // zero that reads as free delivery, on a button promising a total the courier would
    // then contradict at the door (B5). No zone, no total, no order yet.
    final feeKnown = zone != null;
    final ready = identity != null &&
        merchant != null &&
        address != null &&
        feeKnown &&
        inRange &&
        cart.isNotEmpty &&
        !_sending;

    // Not dead code, though the reason it was written for is. It used to say a Google
    // account carries no phone; Google sign-in left in Phase 3 and every customer now
    // signs up *with* a number, so `identity.phone` is set for all of them. What is left
    // is staff — an owner or a courier ordering their own dinner signs in with a real
    // address and carries no phone here. The courier still needs a number to call, so it
    // is asked once and written to the user's row before the order goes out.
    // A comment justifying a branch by a feature that no longer exists is how the branch
    // gets deleted by the next person to read it.
    final needsPhone = identity != null && (identity.phone?.trim().isEmpty ?? true);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('تأكيد الطلب')),
      body: identity == null
          ? LuqmaEmptyView(
            title: 'خطوة واحدة وخلاص',
            message: 'سجّل دخول عشان نعرف نوصّلك الطلب ونتابعه معاك.',
            action: FilledButton(
              key: CheckoutScreen.signInKey,
              onPressed: widget.onSignIn,
              child: const Text('سجّل دخول'),
            ),
          )
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.md,
                Space.gutter,
                Space.xxxl,
              ),
              children: [
                for (final (index, section) in _sections(
                  cart: cart,
                  address: address,
                  zone: zone,
                  merchant: merchant,
                  pricing: pricing,
                  inRange: inRange,
                  needsPhone: needsPhone,
                  acceptedCoupon: acceptedCoupon,
                ).indexed)
                  Padding(
                    // A failure inserts a notice and the coupon swaps a card for a field,
                    // so this list changes length under Flutter — which matches children
                    // by position and would carry one section's entrance onto its
                    // neighbour, the way the address screen lost a typed street.
                    //
                    // Prefixed rather than reusing `section.key` directly: putting the
                    // child's own key on its wrapper puts that key on two widgets, and
                    // every `findsOneWidget` on a notice then finds two.
                    key: ValueKey('slot:${section.key ?? section.runtimeType}'),
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Motion.of(context, Motion.quick) == Duration.zero
                        ? section : LuqmaEntrance(index: index, child: section),
                  ),
              ],
            ),
      bottomNavigationBar: identity == null
          ? null
          : _Footer(
              total: pricing.total,
              sending: _sending,
              onPlace:
                  ready
                      ? () => _place(cart, address, identity,
                          shownTotal: pricing.total)
                      : null,
            ),
    );
  }

  /// The screen's sections, in order, so the entrance stagger indexes them without each
  /// one having to know its own position — and so a section that is not shown does not
  /// leave a gap in the sequence.
  /// What the customer is told when the order did not go.
  ///
  /// «جرّب تاني» is only true of a dead connection, and it used to be said for nearly
  /// every refusal the server names: a switched-off dish, a basket under the minimum, a
  /// shop that had just shut. The narrow types come before the broad ones they extend.
  String _failureSentence(Failure failure) => switch (failure) {
        OfflineFailure() => 'مفيش نت دلوقتي. سلتك زي ما هي — جرّب تاني.',
        CouponFailure() =>
          'الكود ده مبقاش ينفع واتشال من الطلب. راجع الإجمالي واطلب تاني.',
        OrderRefusedFailure(:final reason) => switch (reason) {
            OrderRefusal.shopClosed =>
              'المطعم مش بيستقبل طلبات دلوقتي. جرّب بعدين أو اختار مطعم تاني.',
            OrderRefusal.dishUnavailable =>
              'فيه صنف في السلة مبقاش متاح دلوقتي. شيله من السلة وكمّل.',
            OrderRefusal.belowMinimum =>
              'الطلب أقل من الحد الأدنى للمطعم. زوّد حاجة وكمّل.',
            OrderRefusal.zoneNotServed =>
              'المطعم مبيوصلش العنوان ده. غيّر العنوان أو اختار مطعم تاني.',
            OrderRefusal.tooManyItems =>
              'السلة فيها أصناف كتير أوي لطلب واحد. قسّمها على طلبين.',
            OrderRefusal.noteTooLong => 'الملاحظة طويلة. قصّرها وابعت تاني.',
            OrderRefusal.emptyBasket => 'السلة فاضية.',
            OrderRefusal.soldOut || OrderRefusal.mealClosed =>
              'حاجة في الطلب خلصت. راجع السلة وكمّل.',
          },
        ConflictFailure() => 'حصل تغيير في الطلب. راجع السلة وجرّب تاني.',
        AccountBlockedFailure() =>
          'الحساب ده موقوف عن الطلب. لو شايف إن فيه غلط كلّم لقمة.',
        PermissionFailure() => 'لازم تسجّل دخول عشان تبعت الطلب.',
        _ => 'مقدرناش نبعت الطلب. سلتك زي ما هي — جرّب تاني.',
      };

  List<Widget> _sections({
    required Cart cart,
    required Address? address,
    required Zone? zone,
    required Merchant? merchant,
    required OrderPricing pricing,
    required bool inRange,
    required bool needsPhone,
    required CouponAccepted? acceptedCoupon,
  }) {
    return [
      if (_failure != null)
        LuqmaNotice(
          key: CheckoutScreen.errorKey,
          icon: Icons.error_outline_rounded,
          tone: NoticeTone.problem,
          text: _failureSentence(_failure!),
        ),
      _AddressCard(
        address: address,
        zoneName: zone?.name,
        merchantId: cart.merchantId,
      ),
      if (address == null)
        LuqmaNotice(
          key: CheckoutScreen.needsAddressKey,
          icon: Icons.location_off_outlined,
          tone: NoticeTone.problem,
          text: 'محتاجين عنوان عشان الأوردر يوصل.',
        )
      else if (!inRange)
        LuqmaNotice(
          key: CheckoutScreen.outOfRangeKey,
          icon: Icons.wrong_location_outlined,
          tone: NoticeTone.problem,
          // Found out here, not from a rejection an hour later.
          text: '${merchant?.name ?? "المطعم"} مبيوصلش '
              '${zone?.name ?? "المنطقة دي"}. غيّر العنوان أو اختار مطعم تاني.',
        ),
      if (needsPhone) _PhoneField(controller: _phone, error: _phoneError,
          onChanged: () {
            if (_phoneError != null) setState(() => _phoneError = null);
          }),
      // The applied code and the box to type one are the same slot, never both: a field
      // still offering «طبّق» under a code that is already on reads as a second discount
      // waiting to be claimed.
      _CouponSlot(
        child: acceptedCoupon != null
            ? _CouponCard(
                code: _appliedCouponCode ?? '',
                saved: acceptedCoupon.total,
                onRemove: _removeCoupon,
              )
            : _CouponField(
                controller: _coupon,
                checking: _checkingCoupon,
                rejection: _couponEvaluation is CouponRejected
                    ? _couponSentence((_couponEvaluation! as CouponRejected).reason)
                    : _couponCheckFailed
                        ? 'مقدرناش نتأكد من الكود دلوقتي. جرّب تاني.'
                        : null,
                onApply: cart.isNotEmpty && !_checkingCoupon
                    ? () => _applyCoupon(cart, pricing.deliveryFee)
                    : null,
              ),
      ),
      _Lines(cart: cart),
      _Bill(
        pricing: pricing,
        hasAddress: address != null && zone != null,
        zoneName: zone?.name,
      ),
      const _CashNote(),
      _NoteField(controller: _note),
    ];
  }
}

/// A card in this screen's language: white, hairlined, and lifted only where a shadow
/// can actually be seen. Every panel below is one, so the shape is stated once.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

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
        // A dark page has nothing for a shadow to fall on, and drawing one there only
        // muddies the edge the border is already carrying.
        boxShadow:
            theme.brightness == Brightness.light ? Elevations.card : Elevations.none,
      ),
      child: child,
    );
  }
}

/// The artboard draws these as bare coloured words, which at that size is a target a
/// finger misses. The word keeps its size; what grows is the box around it.
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    super.key,
    required this.label,
    required this.onTap,
    required this.colour,
  });

  final String label;
  final VoidCallback? onTap;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final child = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: Sizes.minTarget,
          minHeight: Sizes.minTarget,
        ),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text(
              label,
              style: LuqmaType.bodyStrong.copyWith(color: colour),
            ),
          ),
        ),
      );
    if (onTap == null) {
      return Semantics(button: true, enabled: false, child: child);
    }
    return LuqmaPressable(onTap: onTap!, child: child);
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.zoneName,
    required this.merchantId,
  });

  final String? merchantId;
  final Address? address;
  final String? zoneName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final landmark = address?.landmarkName ?? address?.landmarkNote;
    final heading = [
      if (zoneName != null && zoneName!.isNotEmpty) zoneName!,
      if (landmark != null && landmark.isNotEmpty) 'جنب $landmark',
    ].join(' · ');
    final detail = address?.copyWith(landmarkName: null, landmarkNote: null)
        .format(zoneName: '').split(' · ').where((part) => part.isNotEmpty)
        .join(' · ');

    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child:
                Icon(Icons.place_outlined, color: colors.brand, size: Sizes.iconMd),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading.isEmpty ? address?.label ?? 'التوصيل إلى' : heading,
                  style: LuqmaType.bodyStrong,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  detail ?? 'لسه مفيش عنوان محفوظ',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          _InlineAction(
            key: CheckoutScreen.changeAddressKey,
            label: address == null ? 'ضيف' : 'تغيير',
            colour: colors.price,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => address == null
                    ? AddressEditorScreen(merchantId: merchantId)
                    : AddressListScreen(merchantId: merchantId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponSlot extends StatelessWidget {
  const _CouponSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context, Motion.quick) == Duration.zero) return child;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.quick),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      // Retain departing space, never a stale saving or a second actionable control.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final child in previous)
            IgnorePointer(child: ExcludeSemantics(
              child: Opacity(opacity: 0, child: child),
            )),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation, alignment: Alignment.topCenter, child: child,
      ),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.code,
    required this.saved,
    required this.onRemove,
  });

  final String code;
  final int saved;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return _Card(
      key: CheckoutScreen.couponCardKey,
      child: Row(
        children: [
          Icon(Icons.confirmation_number_outlined,
              color: colors.price, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كود $code اتطبق',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.success),
                ),
                const SizedBox(height: Space.xs),
                // What it is worth on *this* basket, in money. The artboard says «خصم
                // 15٪», but a percentage is a rule and the customer is deciding about a
                // number — and a fixed-amount or free-delivery code has no percentage to
                // print at all.
                Text(
                  'وفّرت ${strings.price(saved)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          _InlineAction(
            key: CheckoutScreen.couponRemoveKey,
            label: 'شيل',
            colour: colors.danger,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CouponField extends StatelessWidget {
  const _CouponField({
    required this.controller,
    required this.checking,
    required this.rejection,
    required this.onApply,
  });

  final TextEditingController controller;
  final bool checking;
  final String? rejection;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: CheckoutScreen.couponInputKey,
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'كود خصم (إن وجد)',
                    hintText: 'مثلاً LAUNCH',
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              _InlineAction(
                key: CheckoutScreen.couponApplyKey,
                label: checking ? 'بنشوف…' : 'طبّق',
                colour: onApply == null ? colors.textSecondary : colors.brand,
                onTap: onApply,
              ),
            ],
          ),
          if (rejection != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              rejection!,
              key: CheckoutScreen.couponFeedbackKey,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: TextField(
        key: CheckoutScreen.phoneKey,
        controller: controller,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        // The error lives under the field, where the correction is typed.
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: 'رقم الموبايل',
          hintText: '01012345678',
          errorText: error,
        ),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: TextField(
        key: CheckoutScreen.noteKey,
        controller: controller,
        maxLines: 2,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'ملاحظة للمطعم أو الدليفري',
          hintText: 'الشقة فوق الصيدلية، مثلاً',
        ),
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

    return _Card(
      key: CheckoutScreen.linesKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الطلب', style: LuqmaType.bodyStrong),
          const SizedBox(height: Space.sm),
          for (final line in cart.lines)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Row(
                children: [
                  Text(
                    '${line.quantity}×',
                    style: LuqmaType.bodyStrong
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(line.name, style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    strings.price(line.lineTotal),
                    style:
                        LuqmaType.priceSmall.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({
    required this.pricing,
    required this.hasAddress,
    required this.zoneName,
  });

  final OrderPricing pricing;
  final bool hasAddress;
  final String? zoneName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuqmaBillLine(label: 'الأصناف', value: strings.price(pricing.subtotal)),
          if (pricing.subtotalDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            LuqmaBillLine(
              key: CheckoutScreen.billDiscountKey,
              label: 'خصم الكود',
              value: '− ${strings.price(pricing.subtotalDiscount)}',
              emphasis: true,
            ),
          ],
          // Two discounts, not one. The artboard drew a single line because its example
          // had a single code, but a free-delivery coupon lands on the other one and both
          // can be non-zero at once — folding them together hides which one moved.
          if (pricing.deliveryDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            LuqmaBillLine(
              label: 'خصم التوصيل',
              value: '− ${strings.price(pricing.deliveryDiscount)}',
              emphasis: true,
            ),
          ],
          const SizedBox(height: Space.sm),
          LuqmaBillLine(
            label: zoneName == null ? 'التوصيل' : 'التوصيل — $zoneName',
            // Never a zero that looks like free delivery when the truth is that no
            // address has been chosen yet.
            value: hasAddress ? strings.price(pricing.deliveryFee) : '—',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: Divider(height: 1),
          ),
          Row(
            key: CheckoutScreen.totalKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child:
                    Text('المطلوب دفعه كاش', style: theme.textTheme.titleMedium),
              ),
              Text(
                strings.price(pricing.total),
                style: LuqmaType.display.copyWith(color: colors.price),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _CashNote extends ConsumerWidget {
  const _CashNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The owner sets how long a kitchen has to answer (`accept_timeout_minutes`); the
    // sentence promising it was a compiled-in 5 that would have gone on saying five after
    // the owner made it ten.
    final minutes = ref.watch(appConfigProvider).acceptTimeoutMinutes;
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: CheckoutScreen.cashKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.fieldAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: colors.textSecondary, size: Sizes.iconSm),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'جهّز المبلغ كاش للمندوب. المطعم بيأكد الطلب خلال $minutes دقايق.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.sending,
    required this.onPlace,
  });

  static const buttonHeight = 50.0;

  static const pulseFrom = 0.92;

  final int total;
  final bool sending;
  final VoidCallback? onPlace;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    final label = Text(
      sending ? 'بنبعت الطلب…' : 'اطلب دلوقتي · ${strings.price(total)}',
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: FilledButton(
            key: CheckoutScreen.placeKey,
            onPressed: onPlace,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(buttonHeight),
            ),
            // The amount grows into place rather than being swapped. A cross-fade would
            // put two totals on the button at once, and this is the number somebody is
            // about to count out in cash — the basket's subtotal settled the same rule.
            child: Motion.of(context, Motion.quick) == Duration.zero
                ? label
                : TweenAnimationBuilder<double>(
                    key: ValueKey(total),
                    tween: Tween(begin: pulseFrom, end: 1),
                    duration: Motion.of(context, Motion.quick),
                    curve: Motion.enter,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: label,
                  ),
          ),
        ),
      ),
    );
  }
}
