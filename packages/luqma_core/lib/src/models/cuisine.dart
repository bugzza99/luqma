import 'package:freezed_annotation/freezed_annotation.dart';

part 'cuisine.freezed.dart';
part 'cuisine.g.dart';

/// A kind of food, city-wide — what the circles across the top of the customer's home
/// are, and what a merchant is found by.
///
/// Deliberately not [MenuCategory]: that is one shop's own sectioning — "أطباق رئيسية",
/// "مشروبات" — and it exists once per merchant. A customer browsing does not want the
/// third restaurant's idea of a section; they want كشري, from whoever makes it.
///
/// Only an admin writes one. A merchant tagging itself into a circle it does not belong
/// in is the cheapest promotion in the product, and promotion is something merchants pay
/// for — see `promotions`.
@freezed
abstract class Cuisine with _$Cuisine {
  const factory Cuisine({
    required String id,
    required String cityId,
    required String name,

    /// The approved picture on the circle, or null while there is none.
    ///
    /// Resolved to a URL by whoever draws it, exactly like every other image in the
    /// product — the row carries the id, never the address.
    String? mediaId,

    /// The url of [mediaId], when it has been resolved and approved.
    ///
    /// Filled in by the repository rather than stored: a circle with no photograph
    /// still has to draw, so the home screen falls back to the monogram and nothing
    /// upstream has to check two fields.
    String? imageUrl,
    @Default(0) int sortOrder,
  }) = _Cuisine;

  const Cuisine._();

  factory Cuisine.fromJson(Map<String, dynamic> json) => _$CuisineFromJson(json);
}
