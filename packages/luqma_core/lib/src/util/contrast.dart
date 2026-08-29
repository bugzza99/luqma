import 'dart:math' as math;
import 'dart:ui';

/// WCAG relative luminance and contrast, used by the theme tests and available at
/// runtime for the one case the design cannot precompute: choosing readable text over
/// a merchant's own banner artwork.
abstract final class Contrast {
  const Contrast._();

  static double _channel(int component) {
    final v = component / 255;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  static double luminance(Color c) {
    return 0.2126 * _channel((c.r * 255).round()) +
        0.7152 * _channel((c.g * 255).round()) +
        0.0722 * _channel((c.b * 255).round());
  }

  /// Contrast ratio between two opaque colours, from 1.0 to 21.0.
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// AA for normal text.
  static bool passesText(Color fg, Color bg) => ratio(fg, bg) >= 4.5;

  /// AA for text at 18sp bold or 24sp regular and above, and for meaningful
  /// non-text boundaries such as field outlines.
  static bool passesLarge(Color fg, Color bg) => ratio(fg, bg) >= 3.0;

  /// Whichever of [light] or [dark] reads better on [background]. Use for text laid
  /// over an uploaded image once its average colour is known.
  static Color readableOn(Color background, {required Color light, required Color dark}) {
    return ratio(light, background) >= ratio(dark, background) ? light : dark;
  }
}
