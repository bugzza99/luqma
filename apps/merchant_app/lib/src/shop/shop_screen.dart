import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'busy_toggle.dart';

/// The shop: whether it is open, what customers said about it, and the way out.
///
/// The busy control is at the top rather than behind a menu, because after answering an
/// order it is the thing a merchant changes most often — and the moment they need it is
/// the moment they have the least attention to spare looking for it.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  static const signOutKey = Key('shop.signOut');
  static const confirmSignOutKey = Key('shop.confirmSignOut');
  static const feedbackKey = Key('shop.feedback');
  static const noFeedbackKey = Key('shop.noFeedback');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final staff = ref.watch(staffIdentityProvider);
    final merchant = staff.merchantId == null
        ? null
        : ref.watch(merchantProvider(staff.merchantId!)).value;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('المطعم')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          const BusyToggle(),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (merchant != null) _Identity(merchant: merchant),
                const SizedBox(height: Space.lg),
                if (merchant != null) _Rating(merchant: merchant),
                const SizedBox(height: Space.xl),
                Text(
                  staff.email ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.sm),
                TextButton(
                  key: signOutKey,
                  onPressed: () => _confirmSignOut(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.danger,
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    // Asked, because the way back in is a password the merchant may not have to hand,
    // and because signing out during a rush costs orders.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجّل خروج؟'),
        content: const Text(
          'مش هتوصلك طلبات جديدة على التليفون ده لحد ما تدخل تاني.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
          FilledButton(
            key: confirmSignOutKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اخرج'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authServiceProvider).signOut();
    }
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.merchant});

  final Merchant merchant;

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
          Icon(
            merchant.type == MerchantType.homeKitchen
                ? Icons.soup_kitchen_outlined
                : Icons.storefront_outlined,
            color: colors.brand,
            size: Sizes.iconLg,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(merchant.name, style: theme.textTheme.titleMedium),
                Text(
                  merchant.phone,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What customers have said.
///
/// The average is only shown once there are enough of them. One bad night in a town
/// where everyone knows everyone should not follow a merchant around, and a "1.0" next
/// to a single review is a number that reads as a verdict.
class _Rating extends ConsumerWidget {
  const _Rating({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final threshold = ref.watch(appConfigProvider).minRatingsToShow;
    final enough = merchant.ratingCount >= threshold;

    return Container(
      key: enough ? ShopScreen.feedbackKey : ShopScreen.noFeedbackKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.star_rounded,
            color: enough ? colors.accent : colors.border,
            size: Sizes.iconLg,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: enough
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.ratingAvg.toStringAsFixed(1),
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        'من ${merchant.ratingCount} تقييم',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  )
                : Text(
                    'التقييم هيظهر بعد ما يوصل $threshold تقييمات.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
          ),
        ],
      ),
    );
  }
}
