import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// A promotion slot on the home screen.
///
/// The slot *is* the placement: which promotions can appear here and how many rotate are
/// read off this section's own parameters. That is why there is no separate placements
/// collection — one fewer place for the two to disagree.
///
/// Every render mode occupies the same 3:1 box, so the screen never jumps as banners
/// rotate. The same ratio is enforced on upload, where a banner that is not 3:1 is
/// refused outright.
class AdSlotSection extends ConsumerWidget {
  const AdSlotSection({super.key, required this.section});

  final HomeSection section;

  static Key slotKey(String sectionKey) => Key('adSlot.$sectionKey');
  static Key bannerKey(String promotionId) => Key('adSlot.banner.$promotionId');
  static const dotsKey = Key('adSlot.dots');

  int get _maxAds => switch (section.params['maxAds']) {
        final int n when n > 0 => n,
        _ => 1,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(livePromotionsProvider).value ?? const <Promotion>[];

    final banners = live
        .where((p) =>
            p.channel == PromotionChannel.homeBanner &&
            p.belongsIn(section.key) &&
            // A banner promising a picture and carrying none renders as a broken box on
            // the home screen of every customer in the city.
            p.canRender)
        .take(_maxAds)
        .toList();

    // Nothing sold means no space taken. An empty band under nothing reads as a broken
    // image, and a customer should not pay attention for a merchant who paid nothing.
    // A failed read lands here too, deliberately: the home is assembled from independent
    // blocks, and one that cannot load should cost itself and not the restaurants.
    if (banners.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: slotKey(section.key),
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: banners.length == 1
          ? AspectRatio(
              aspectRatio: Sizes.bannerAspect,
              child: _Banner(promotion: banners.first),
            )
          : _Carousel(banners: banners),
    );
  }
}

/// More than one banner, turning itself over.
///
/// Three rules, and the third is the one that is easy to leave out:
///
/// - it advances on its own, because a banner nobody swipes is a banner nobody sees;
/// - it stops the moment somebody touches it, because turning the page under a thumb
///   that is reaching for it is the app arguing with the person holding it;
/// - and it does not advance at all when the phone asks for reduced motion. That setting
///   is on for people who get motion sick and for people using a screen reader, and a
///   carousel that keeps moving under a reader is one that never finishes being read.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.banners});

  final List<Promotion> banners;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  static const _interval = Duration(seconds: 5);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: MediaQuery is not available yet in initState,
    // and this has to react if the setting changes while the app is open.
    _schedule(reducedMotion: MediaQuery.disableAnimationsOf(context));
  }

  /// Set once somebody touches the thing, and never cleared.
  ///
  /// Cancelling the timer was not enough: `didChangeDependencies` reschedules, and it
  /// fires for a theme change, a locale change, the keyboard coming up, a rotation —
  /// so the rotation resumed under the reader's thumb, which is the thing the listener
  /// below exists to prevent.
  bool _stopped = false;

  void _schedule({required bool reducedMotion}) {
    _timer?.cancel();
    if (reducedMotion || _stopped) return;

    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: Sizes.bannerAspect,
          child: NotificationListener<ScrollNotification>(
            // A touch stops the rotation for good. Somebody who started swiping is
            // reading, and taking the page away mid-sentence is worse than never
            // rotating at all.
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _stopped = true;
                _timer?.cancel();
              }
              return false;
            },
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final promotion in widget.banners)
                  _Banner(promotion: promotion),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Row(
          key: AdSlotSection.dotsKey,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.banners.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.xs + 1),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 16 : 5,
                height: 5,
                decoration: BoxDecoration(
                  // Burgundy for the one you are on, and the interactive outline colour
                  // for the rest — the decorative hairline is 1.5:1 on cream and would
                  // leave the other dots invisible.
                  color: i == _page ? colors.brand : colors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: AdSlotSection.bannerKey(promotion.id),
      onTap: () => openMerchant(context, promotion.merchantId),
      borderRadius: Radii.cardAll,
      child: ClipRRect(
        borderRadius: Radii.cardAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The gradient is the fallback as well as the text mode's background: a
            // merchant with no artwork gets a banner that still looks made on purpose,
            // which is the whole commercial point of the text mode.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [colors.brand, colors.brandPressed],
                ),
              ),
            ),
            // Storage arrived; this did not follow it. For two phases the slot drew
            // `SizedBox.shrink()` here, so a merchant who paid for a banner, uploaded
            // artwork and had it approved got the gradient — indistinguishable from a
            // banner that never had a picture.
            //
            // The gradient stays underneath as the fallback: an image that is missing,
            // unapproved or slow to arrive leaves a banner that still looks made on
            // purpose rather than a grey box.
            if (promotion.renderMode != PromotionRender.text &&
                promotion.imageUrl != null)
              Image.network(
                promotion.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (promotion.renderMode == PromotionRender.imageWithText)
              DecoratedBox(
                decoration: BoxDecoration(color: colors.scrim),
              ),
            if (promotion.renderMode != PromotionRender.image)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promotion.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.onBrand,
                      ),
                    ),
                    if (promotion.body.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        promotion.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onBrand.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
