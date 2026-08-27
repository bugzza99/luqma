import 'package:freezed_annotation/freezed_annotation.dart';

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
  cuisine,
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
