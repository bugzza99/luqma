import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';
import 'section_gap.dart';

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

    return SectionGap(
      child: Padding(
      key: slotKey(section.key),
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: banners.length == 1
          ? AspectRatio(
              aspectRatio: Sizes.bannerAspect,
              child: _Banner(promotion: banners.first),
            )
          : _Carousel(banners: banners),
    ),
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
        duration: Motion.page,
        curve: Motion.emphasis,
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
                duration: Motion.of(context, Motion.quick),
                curve: Motion.emphasis,
                width: i == _page ? Space.lg : Space.xs + 1,
                height: Space.xs + 1,
                decoration: BoxDecoration(
                  // Burgundy for the one you are on, and the interactive outline colour
                  // for the rest — the decorative hairline is 1.5:1 on cream and would
                  // leave the other dots invisible.
                  color: i == _page ? colors.brand : colors.border,
                  borderRadius: Radii.pillAll,
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
    final colors = Theme.of(context).luqma;

    // A picture, or words. Never words over a picture: the merchant's photograph decides
    // where its own dark parts are, so a headline laid over it lands somewhere nobody
    // chose — legible on the artwork it was tested against and gone on the next one.
    final chosen = PromotionPalette.parse(promotion.backgroundColor);
    final ink = chosen == null ? colors.onBrand : PromotionPalette.inkOn(chosen);
    // The second line is orange on the burgundy gradient — the one place the design puts
    // orange on a dark ground — and the computed ink on a colour a merchant chose, where
    // a fixed orange could land pale-on-pale.
    //
    // `orangeLight`, not `colors.accent`. The accent follows the theme, and in the light
    // theme it is `#D67F2B`, which scores **3.70:1** on this burgundy — under the 4.5:1
    // that 12sp normal text needs. The artboard says `#E69B4A` and the artboard is right:
    // it scores 4.82:1. The ground here is brand burgundy in *both* themes, so its ink
    // cannot be the one that swaps with the theme.
    final subtitle =
        chosen == null ? LuqmaPalette.orangeLight : ink.withValues(alpha: 0.9);

    return InkWell(
      key: AdSlotSection.bannerKey(promotion.id),
      onTap: () => openMerchant(context, promotion.merchantId),
      borderRadius: Radii.cardAll,
      child: ClipRRect(
        borderRadius: Radii.cardAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The ground: the merchant's colour when they picked one, and the brand
            // gradient when they did not — which is what every text banner drew before
            // the colour existed, and what somebody who does not care should still get.
            DecoratedBox(
              decoration: BoxDecoration(
                color: chosen,
                gradient: chosen != null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        // `LuqmaPalette`, not the theme's brand: this ground carries
                        // small orange text, and the dark theme's brand is the lighter
                        // burgundy, on which that orange scores 3.83:1 and fails. See
                        // `LuqmaPalette.bannerTop`.
                        colors: [
                          LuqmaPalette.bannerTop,
                          LuqmaPalette.bannerBottom,
                        ],
                      ),
              ),
            ),
            // Whole, not cropped. `cover` fills the slot by throwing away whatever does
            // not fit, and what does not fit on a banner is usually the half the merchant
            // paid a designer for — the dish, or the price. `contain` keeps all of it and
            // lets the ground show at the edges, which is a frame rather than a bug.
            if (promotion.renderMode == PromotionRender.image &&
                promotion.imageUrl != null)
              Image.network(
                promotion.imageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (promotion.renderMode == PromotionRender.text)
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
                      // 15/bold, and the ink is computed from the ground — never stored —
                      // so there is no way to end up with pale words on a pale banner.
                      style: LuqmaType.bodyStrong
                          .copyWith(color: ink, fontWeight: FontWeight.w700),
                    ),
                    if (promotion.body.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        promotion.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LuqmaType.caption
                            .copyWith(color: subtitle, fontWeight: FontWeight.w600),
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
