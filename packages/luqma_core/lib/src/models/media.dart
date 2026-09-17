import 'package:freezed_annotation/freezed_annotation.dart';

import '../theme/dimens.dart';
import 'converters.dart';

part 'media.freezed.dart';
part 'media.g.dart';

/// What an image belongs to. A banner and a dish photo are judged against different
/// things, so the reviewer has to be told which they are looking at.
enum MediaKind {
  merchantLogo,
  merchantCover,
  menuItem,
  dailyMeal,
  promotion,

  /// The owner's own photograph on حول لقمة.
  aboutPhoto,

  /// The picture on one of the circles across the top of the customer's home.
  cuisine;

  /// The aspect ratio (width / height) at which this image is displayed across apps.
  ///
  /// The single source of truth for previewing in [MediaPicker] and displaying
  /// in customer and merchant screens.
  double get aspectRatio => switch (this) {
        MediaKind.merchantCover => 16 / 9,
        MediaKind.merchantLogo => 1.0,
        MediaKind.menuItem => 1.0,
        MediaKind.dailyMeal => 1.0,
        MediaKind.promotion => Sizes.bannerAspect,
        MediaKind.aboutPhoto => 1.0,
        MediaKind.cuisine => 1.0,
      };

  /// Recommended pixel dimensions for merchant uploads.
  ///
  /// Capped at 1600 on the long edge so no upload exceeds `ImageCompressor.maxEdge`.
  ({int width, int height}) get recommendedDimensions => switch (this) {
        MediaKind.merchantCover => (width: 1600, height: 900),
        MediaKind.merchantLogo => (width: 800, height: 800),
        MediaKind.menuItem => (width: 1200, height: 1200),
        MediaKind.dailyMeal => (width: 1200, height: 1200),
        MediaKind.promotion => (
            width: 1600,
            height: (1600 / Sizes.bannerAspect).round(),
          ),
        MediaKind.aboutPhoto => (width: 800, height: 800),
        MediaKind.cuisine => (width: 800, height: 800),
      };

  int get recommendedWidth => recommendedDimensions.width;
  int get recommendedHeight => recommendedDimensions.height;

}

enum MediaStatus { pending, approved, rejected }

/// Every image in the product, whatever it belongs to.
///
/// One collection so the moderation gate has exactly one door. Scattering an
/// `imageStatus` field across four collections would mean four rules, four triggers and
/// four queues — and one of them eventually forgotten, which is a gate with a hole in it.
@freezed
abstract class Media with _$Media {
  const factory Media({
    required String id,
    required MediaKind kind,
    required String url,
    String? thumbUrl,
    @Default(MediaStatus.pending) MediaStatus status,
    String? ownerId,
    String? uploadedBy,
    @Default(0) int width,
    @Default(0) int height,
    @Default(0) int bytes,
    String? reviewedBy,

    /// Why it was refused. A merchant told nothing simply uploads the same photo again.
    String? reviewNote,
    @TimestampConverter() DateTime? createdAt,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
