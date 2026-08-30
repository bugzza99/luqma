import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Every picture in the product, and what stands in when there isn't one.
///
/// On launch day there is no photograph of anything — the owner shoots them one merchant
/// at a time over the weeks after. So the empty case is not an edge here; it is the whole
/// screen for a while, and it has to look deliberate rather than broken.
///
/// What it is not: a grid of identical logos. Twenty cards wearing the same mark reads as
/// a page that failed to load, where twenty different tints read as a page whose pictures
/// have not been taken yet. The tint comes from the name, so a shop looks like itself
/// from the first day and keeps looking like itself until its photograph replaces it.
class LuqmaImage extends StatelessWidget {
  const LuqmaImage({
    super.key,
    required this.url,
    required this.name,
    this.fit = BoxFit.contain,
  });

  /// The approved image, or null when there is none yet.
  final String? url;

  /// What this is a picture of. Both the monogram and the accessible name come from it.
  final String name;

  /// How the picture meets its frame. Whole by default.
  ///
  /// `cover` fills the frame by throwing away whatever does not fit, and a merchant's
  /// photograph is not framed for our aspect ratio — so the dish ends up half out of
  /// shot, or the price the merchant had printed on it is the part that got cut. What is
  /// lost is invisible: the picture looks fine, it is simply not the picture.
  ///
  /// `contain` keeps all of it and lets the mat show at the edges, which reads as a frame
  /// rather than a fault. A caller framing something deliberately — a face in a circle —
  /// passes `cover` and means it.
  final BoxFit fit;

  /// The tints a name can land on, darkest-first, all of them carrying [LuqmaColors.background].
  ///
  /// Built by mixing brand tokens rather than written as new hexes: a colour invented
  /// here would be the one colour in the product that nobody contrast-tested, and it
  /// would be invented in the place hardest to notice — behind a letter, on a screen
  /// that looks finished.
  static List<Color> tintsFor(LuqmaColors colors) => [
        colors.brand,
        colors.brandPressed,
        Color.lerp(colors.brand, colors.textPrimary, 0.35)!,
        Color.lerp(colors.brand, colors.accent, 0.30)!,
        Color.lerp(colors.textPrimary, colors.brand, 0.30)!,
      ];

  /// The first letter, as a reader sees it.
  ///
  /// A grapheme, not a code unit: Arabic letters carry their diacritics as separate code
  /// points, so `name[0]` on "أُسرة" yields half a letter and draws a broken glyph.
  static String monogramOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '؟';
    return trimmed.characters.first;
  }

  /// Which tint this name gets — stable, so a shop does not change colour between the
  /// home screen and its own page.
  static Color tintFor(String name, LuqmaColors colors) {
    final tints = tintsFor(colors);
    // Summed code units rather than `hashCode`: Dart's String hash is not guaranteed
    // stable across runs or platforms, which would repaint the whole city on an upgrade.
    var sum = 0;
    for (final unit in name.trim().codeUnits) {
      sum = (sum + unit) % 1000003;
    }
    return tints[sum % tints.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final address = url;

    return Semantics(
      label: name.trim().isEmpty ? null : name,
      image: true,
      child: ExcludeSemantics(
        child: address == null || address.isEmpty
            ? _Monogram(name: name, colors: colors)
            : ColoredBox(
                // The mat behind a contained picture. Warm rather than grey or black:
                // this shows at the edges of most photographs in the product, so it is a
                // surface the eye reads as part of the card and not as empty space where
                // the picture stopped.
                color: colors.surface,
                child: Image.network(
                  address,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  // The monogram fills the space for the whole download, so the card is
                  // its final height from the first frame. A spinner in a box that grows
                  // when the picture lands moves everything under it while somebody is
                  // reaching for it.
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : _Monogram(name: name, colors: colors),
                  // A URL that 404s — an image deleted after rejection, a bucket that has
                  // moved — lands here, and is the same thing as no picture at all.
                  errorBuilder: (context, _, _) =>
                      _Monogram(name: name, colors: colors),
                ),
              ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.colors});

  final String name;
  final LuqmaColors colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LuqmaImage.tintFor(name, colors),
      child: Center(
        child: Text(
          LuqmaImage.monogramOf(name),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colors.background,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
