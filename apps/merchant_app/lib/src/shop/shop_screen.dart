import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'hours_screen.dart';
import 'statement_screen.dart';


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
  static const statementKey = Key('shop.statement');
  static const walletKey = Key('shop.wallet');
  static const promotionsKey = Key('shop.promotions');
  static const hoursKey = Key('shop.hours');
  static const noFeedbackKey = Key('shop.noFeedback');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final staff = ref.watch(staffIdentityProvider);
    final merchantAsync = staff.merchantId == null
        ? null
        : ref.watch(merchantProvider(staff.merchantId!));
    final merchant = merchantAsync?.value;

    // `.value` is null while loading *and* null on failure, and everything below was
    // gated on it — so a dropped connection drew an empty page with `BusyToggle`
    // collapsed to nothing. That control is how a merchant stops orders during a rush,
    // and one that is simply absent does not read as "the connection is down": it reads
    // as a shop that is fine, while orders keep arriving at a kitchen with no way to say
    // stop.
    //
    // `hasError` rather than a match on `AsyncError`: a stream that fails before it has
    // ever emitted stays `AsyncLoading` with the error hanging off it.
    if (merchantAsync != null && merchantAsync.hasError) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('المطعم')),
        body: LuqmaErrorView(
          failure: merchantAsync.error!,
          onRetry: () => ref.invalidate(merchantProvider(staff.merchantId!)),
        ),
      );
    }

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
                if (staff.merchantId != null) ...[
                  const SizedBox(height: Space.lg),
                  // The schedule the whole product derives "can this shop take an order"
                  // from. It had no editor anywhere, so a merchant whose hours were wrong
                  // — or empty — was shut with nothing on any screen that changed it.
                  _Tile(
                    tileKey: ShopScreen.hoursKey,
                    icon: Icons.schedule_rounded,
                    title: 'مواعيد الشغل',
                    subtitle: 'إمتى المطعم بيستقبل طلبات',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HoursScreen(merchantId: staff.merchantId!),
                      ),
                    ),
                  ),
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
      // Nothing to do here about the token any more. `keepPushTokenRegistered` is
      // watching the session, so signing out is what takes this device off the account —
      // one place that decides, instead of a screen that has to remember.
      await ref.read(authServiceProvider).signOut();
    }
  }
}

class _Identity extends ConsumerStatefulWidget {
  const _Identity({required this.merchant});

  final Merchant merchant;

  static const coverKey = Key('shop.cover');
  static const logoKey = Key('shop.logo');
  static const descriptionKey = Key('shop.description');
  static const saveDescriptionKey = Key('shop.description.save');

  @override
  ConsumerState<_Identity> createState() => _IdentityState();
}

class _IdentityState extends ConsumerState<_Identity> {
  /// The pictures as they stand, replaced the moment a new one is uploaded so the
  /// merchant sees what they picked rather than the old one until they reopen the screen.
  String? _coverUrl;
  String? _logoUrl;
  bool _saving = false;

  late final _description =
      TextEditingController(text: widget.merchant.description ?? '');

  /// Whether the typed line differs from the saved one.
  ///
  /// A save button that is always live is a save button somebody presses to find out
  /// whether it did anything.
  bool _descriptionChanged = false;

  Merchant get merchant => widget.merchant;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPictures());
    _description.addListener(() {
      final changed =
          _description.text.trim() != (merchant.description?.trim() ?? '');
      if (changed != _descriptionChanged) {
        setState(() => _descriptionChanged = changed);
      }
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// Resolves the ids the merchant row carries into URLs.
  ///
  /// The row stores the id, never the address — that is the rule for every image in the
  /// product, and it is what lets a rejected picture disappear everywhere at once.
  Future<void> _loadPictures() async {
    final wanted = [
      for (final (id, isLogo) in [
        (merchant.coverMediaId, false),
        (merchant.logoMediaId, true),
      ])
        if (id != null && id.isNotEmpty) (id, isLogo),
    ];
    // Nothing to resolve, nothing to reach for. Reading the repository first looks
    // harmless and is not: a shop with no pictures yet — which is every shop on the day
    // it is added — would build the media repository, and through it the Supabase client,
    // for two ids that do not exist.
    if (wanted.isEmpty) return;

    final media = ref.read(mediaRepositoryProvider);
    for (final (id, isLogo) in wanted) {
      final result = await media.get(id);
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          _logoUrl = result.valueOrNull?.url;
        } else {
          _coverUrl = result.valueOrNull?.url;
        }
      });
    }
  }

  Future<void> _attach(Media media, {required bool isLogo}) async {
    final previous = isLogo ? _logoUrl : _coverUrl;
    setState(() {
      if (isLogo) {
        _logoUrl = media.url;
      } else {
        _coverUrl = media.url;
      }
      _saving = true;
    });

    // The id goes on the merchant row; the picture stays invisible to customers until an
    // admin approves it, like every other image in the product.
    final result = await ref.read(merchantRepositoryProvider).saveMerchant(
          isLogo
              ? merchant.copyWith(logoMediaId: media.id)
              : merchant.copyWith(coverMediaId: media.id),
        );
    if (!mounted) return;
    setState(() => _saving = false);

    // The result was once discarded, and the new picture was already on the screen — so a
    // save that failed looked exactly like one that worked. The merchant closes the app
    // believing their shop has a picture; the row still carries the old id, or none, and
    // the customer sees the tinted placeholder for ever.
    if (result case Err()) {
      setState(() {
        if (isLogo) {
          _logoUrl = previous;
        } else {
          _coverUrl = previous;
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('الصورة موصلتش. جرّب تاني.')),
      );
    }
  }

  Future<void> _saveDescription() async {
    setState(() => _saving = true);
    final typed = _description.text.trim();
    final result = await ref.read(merchantRepositoryProvider).saveMerchant(
          merchant.copyWith(description: typed.isEmpty ? null : typed),
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _descriptionChanged = result is Err;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok() => 'اتحفظ.',
          Err(:final failure) => switch (failure) {
              OfflineFailure() => 'مفيش نت — جرّب تاني.',
              _ => 'مقدرناش نحفظ. جرّب تاني.',
            },
        }),
      ),
    );
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(top: Space.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: Space.lg),
          // Labelled, because there are two of them now and a merchant looking at two
          // picture boxes has no way to tell which one ends up where.
          _Label(text: 'صورة الغلاف', hint: 'الصورة الكبيرة فوق صفحة المطعم'),
          const SizedBox(height: Space.sm),
          MediaPicker(
            key: _Identity.coverKey,
            kind: MediaKind.merchantCover,
            url: _coverUrl,
            name: merchant.name,
            ownerId: merchant.id,
            height: 120,
            onUploaded: (media) => _attach(media, isLogo: false),
          ),
          const SizedBox(height: Space.lg),
          // The mark.
          //
          // `logo_media_id` has been a column since the first schema and no screen in any
          // of the three apps could write it — so a shop got a cover photograph and, in
          // the place its own mark belongs, a storefront glyph identical to every other
          // restaurant in the city. The logo is what a regular customer recognises in a
          // list without reading, which is what the tile on their home is built around.
          _Label(text: 'لوجو المطعم', hint: 'بيظهر جنب اسمك في القوايم'),
          const SizedBox(height: Space.sm),
          MediaPicker(
            key: _Identity.logoKey,
            kind: MediaKind.merchantLogo,
            url: _logoUrl,
            name: merchant.name,
            ownerId: merchant.id,
            height: 96,
            onUploaded: (media) => _attach(media, isLogo: true),
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: _Identity.descriptionKey,
            controller: _description,
            maxLength: 120,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'وصف قصير',
              hintText: 'مشويات وحلويات شرقية',
              // Said here rather than discovered on the customer's home: this line is
              // what tells somebody scrolling past what kind of food this shop sells.
              helperText: 'بيظهر تحت اسم المطعم في الصفحة الرئيسية.',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              key: _Identity.saveDescriptionKey,
              onPressed: _descriptionChanged && !_saving ? _saveDescription : null,
              child: const Text('احفظ الوصف'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading for one control, with the sentence that says where it lands.
class _Label extends StatelessWidget {
  const _Label({required this.text, required this.hint});

  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: theme.textTheme.titleSmall),
        Text(
          hint,
          style: LuqmaType.caption.copyWith(color: colors.textSecondary),
        ),
      ],
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
    // Whether a subscription term has run out is a question about a moment, and the
    // moment has to be one a test can choose.
    final now = ref.watch(clockProvider)();
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
          // Only where something is actually taken per order. Under a subscription the
          // statement is a page of zeroes, and a screen that says nothing every time is
          // one somebody stops believing when it finally has something to say.
          if (merchant.revenueModel != RevenueModel.subscription) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ShopScreen.statementKey,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatementScreen(merchantId: merchant.id),
                  ),
                ),
                icon: const Icon(Icons.list_alt_rounded, size: Sizes.iconSm),
                label: const Text('كشف الحساب'),
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
        // Left hand-written: this is a section inside a page that is otherwise fine, so
        // a failure is one quiet sentence rather than the full error block with a retry
        // that `LuqmaAsyncView` draws. Losing the ratings must not take over the screen.
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
