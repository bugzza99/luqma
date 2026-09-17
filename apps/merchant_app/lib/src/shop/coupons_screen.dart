import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// A shop's own discount codes.
///
/// Live the moment they are made, with no approval — the owner's decision of 2026-09-17:
/// the discount is the shop's own money, so there is nobody else's permission to ask for.
/// The admin still sees every coupon and can pause any of them. Nothing here offers
/// platform-funded coupons; the database refuses a shop writing one, and hides the ones
/// an admin places on the shop.
class MerchantCouponsScreen extends ConsumerWidget {
  const MerchantCouponsScreen({super.key, required this.merchant});

  final Merchant merchant;

  static const addKey = Key('merchantCoupons.add');
  static const emptyKey = Key('merchantCoupons.empty');

  Future<void> _edit(BuildContext context, WidgetRef ref, Coupon? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: CouponForm(
          initial: existing,
          cityId: merchant.cityId,
          merchantId: merchant.id,
          clock: ref.read(clockProvider),
          onSave: (draft) async {
            final repo = ref.read(couponRepositoryProvider);
            final result =
                existing == null ? await repo.create(draft) : await repo.update(draft);
            if (result case Err(:final failure)) return failure;
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            return null;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final coupons = ref.watch(_shopCouponsProvider(merchant.id));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('كوبونات الخصم')),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('كوبون جديد'),
      ),
      body: LuqmaAsyncView(
        value: coupons,
        onRetry: () => ref.invalidate(_shopCouponsProvider(merchant.id)),
        isEmpty: (value) => value.isEmpty,
        empty: Center(
          key: emptyKey,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(
              'مفيش كوبونات لسه. الكوبون بيشتغل على طول أول ما تعمله، والخصم على حساب المحل.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        builder: (context, value) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.gutter,
            Space.gutter,
            Space.xxxl + Space.xl,
          ),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) {
            final coupon = value[i];
            return CouponTile(
              coupon: coupon,
              onTap: () => _edit(context, ref, coupon),
              onActiveChanged: (active) async {
                final result = await ref
                    .read(couponRepositoryProvider)
                    .setActive(coupon.id, active);
                if (result is Err && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('مقدرناش نغيّر حالة الكوبون. جرّب تاني.')),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}

final _shopCouponsProvider = StreamProvider.autoDispose.family<List<Coupon>, String>(
  (ref, merchantId) => ref.watch(couponRepositoryProvider).watchForMerchant(merchantId),
);
