import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../app/push.dart';

import '../promotions/promotions_screen.dart';
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
  static const billingKey = Key('shop.billing');
  static const walletKey = Key('shop.wallet');
  static const promotionsKey = Key('shop.promotions');
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
                if (merchant != null) ...[
                  const SizedBox(height: Space.lg),
                  _Billing(merchant: merchant),
                ],
                const SizedBox(height: Space.lg),
                _Tile(
                  tileKey: ShopScreen.promotionsKey,
                  icon: Icons.campaign_outlined,
                  title: 'الإعلانات',
                  subtitle: 'اطلب بانر أو رفع في الترتيب',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MerchantPromotionsScreen(),
                    ),
                  ),
                ),
                if (staff.merchantId != null) ...[
                  const SizedBox(height: Space.lg),
                  _Feedback(merchantId: staff.merchantId!),
                ],
                const SizedBox(height: Space.xl),
                Text(
                  staff.email ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
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
      // Before the session goes, not after: a till behind a counter that keeps the last
      // merchant's token goes on ringing for a shop the person holding it no longer
      // works for, and once signed out there is no account to take it off.
      //
      // Guarded, because signing out must always work. An account somebody cannot leave
      // is trusted less, not more — and a token left behind is a nuisance, where a
      // sign-out button that does nothing is a person stuck in somebody else's shop.
      try {
        await LuqmaPush.stop(ref.read(pushTokenRepositoryProvider));
      } catch (_) {}
      await ref.read(authServiceProvider).signOut();
    }
  }
}

class _Identity extends ConsumerStatefulWidget {
  const _Identity({required this.merchant});

  final Merchant merchant;

  static const coverKey = Key('shop.cover');

  @override
  ConsumerState<_Identity> createState() => _IdentityState();
}

class _IdentityState extends ConsumerState<_Identity> {
  /// The cover as it stands, replaced the moment a new one is uploaded so the merchant
  /// sees what they picked rather than the old picture until they reopen the screen.
  String? _coverUrl;
  bool _saving = false;

  Merchant get merchant => widget.merchant;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCover());
  }

  /// Resolves the id the merchant row carries into a URL.
  ///
  /// The row stores the id, never the address — that is the rule for every image in the
  /// product, and it is what lets a rejected picture disappear everywhere at once.
  Future<void> _loadCover() async {
    final id = merchant.coverMediaId;
    if (id == null || id.isEmpty) return;

    final result = await ref.read(mediaRepositoryProvider).get(id);
    if (!mounted) return;
    setState(() => _coverUrl = result.valueOrNull?.url);
  }

  Future<void> _attachCover(Media media) async {
    setState(() {
      _coverUrl = media.url;
      _saving = true;
    });

    // The id goes on the merchant row; the picture stays invisible to customers until an
    // admin approves it, like every other image in the product.
    await ref
        .read(merchantRepositoryProvider)
        .saveMerchant(merchant.copyWith(coverMediaId: media.id));
    if (mounted) setState(() => _saving = false);
  }

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
      child: Column(
        children: [
          // The picture at the top of this shop's page on the customer's home. Until now
          // there was no way for a merchant to have one at all.
          MediaPicker(
            key: _Identity.coverKey,
            kind: MediaKind.merchantCover,
            url: _coverUrl,
            name: merchant.name,
            ownerId: merchant.id,
            height: 120,
            onUploaded: _attachCover,
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(top: Space.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: Space.md),
          Row(
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What this merchant is paying, and — under prepaid — what is left.
///
/// Read-only. Money is settled in cash with the owner, so a merchant changing their own
/// terms from their phone is not a feature, it is a hole. What they need from this screen
/// is to know where they stand before somebody arrives to collect.
class _Billing extends ConsumerWidget {
  const _Billing({required this.merchant});

  final Merchant merchant;

  static const _modelNames = {
    RevenueModel.subscription: 'اشتراك شهري',
    RevenueModel.commission: 'عمولة على كل أوردر',
    RevenueModel.prepaid: 'رصيد مدفوع مقدماً',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final subscription = ref.watch(subscriptionProvider(merchant.id)).value;
    final plans = ref.watch(plansProvider).value ?? const <Plan>[];
    final plan = plans.where((p) => p.id == merchant.planId).firstOrNull;
    final now = DateTime.now();
    final canAfford = Revenue.canAffordAnOrder(merchant);

    return Container(
      key: ShopScreen.billingKey,
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
              Icon(
                Icons.receipt_long_outlined,
                color: colors.brand,
                size: Sizes.iconMd,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  plan?.name ?? _modelNames[merchant.revenueModel]!,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (merchant.revenueModel == RevenueModel.prepaid) ...[
            const SizedBox(height: Space.sm),
            Row(
              key: ShopScreen.walletKey,
              children: [
                Expanded(
                  child: Text(
                    'الرصيد',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  strings.price(merchant.walletBalance),
                  style: LuqmaType.priceSmall.copyWith(
                    color: canAfford ? colors.price : colors.danger,
                  ),
                ),
              ],
            ),
            if (!canAfford) ...[
              const SizedBox(height: Space.xs),
              Text(
                // The one thing on this card that changes what happens next: with no
                // credit the shop stops receiving orders at all.
                'الرصيد خلص — مش هتوصلك طلبات لحد ما يتشحن.',
                style: LuqmaType.bodySmall.copyWith(color: colors.danger),
              ),
            ],
          ] else if (subscription != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              subscription.isActiveAt(now)
                  ? 'الاشتراك ساري ${subscription.daysLeftAt(now)} يوم كمان'
                  : 'الاشتراك خلص',
              style: LuqmaType.bodySmall.copyWith(
                color: subscription.isActiveAt(now)
                    ? colors.textSecondary
                    : colors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The words, as opposed to the stars.
///
/// Private to this merchant until the public-comments flag is turned on. Somebody who
/// reads honest criticism in private fixes it; in public they argue with it.
class _Feedback extends ConsumerWidget {
  const _Feedback({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final feedback = ref.watch(merchantFeedbackProvider(merchantId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('اللي العملاء قالوه', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        switch (feedback) {
          // First, and on `hasError`: a stream that fails before it has ever emitted
          // stays AsyncLoading with the error hanging off it.
          AsyncValue(hasError: true) => Text(
            'مش قادرين نجيب التقييمات دلوقتي.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          AsyncValue(hasValue: true, :final value?) when value.isEmpty => Text(
            'لسه محدش قيّم طلب.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          AsyncValue(hasValue: true, :final value?) => Column(
            children: [
              for (final one in value.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _FeedbackRow(feedback: one),
                ),
            ],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.feedback});

  final CustomerRating feedback;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= feedback.stars
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: Sizes.iconSm,
                  color: i <= feedback.stars ? colors.accent : colors.border,
                ),
            ],
          ),
          // Most people rate without typing, and those ratings still belong here — a
          // list of comments alone would read as nothing but complaints, because
          // complaints are what people bother to write.
          if (feedback.comment != null && feedback.comment!.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(feedback.comment!, style: theme.textTheme.bodyMedium),
          ],
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'التقييم هيظهر بعد ما يوصل $threshold تقييمات.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A row that leads somewhere.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: tileKey,
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.brand, size: Sizes.iconMd),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: colors.textSecondary,
              size: Sizes.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}
