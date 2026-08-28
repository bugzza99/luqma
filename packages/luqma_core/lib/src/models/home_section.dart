import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_section.freezed.dart';
part 'home_section.g.dart';

/// One block on the customer's home screen, chosen and ordered by the owner.
///
/// This is the whole of "dynamic": the server picks which blocks appear, in what order,
/// and with what parameters. It cannot describe a *new kind* of block — the app owns a
/// fixed map of types to widgets, and a [type] outside that map draws nothing. That
/// boundary is what keeps this from becoming server-driven UI, which would have cost
/// three times the work and been far harder to keep from breaking.
@freezed
abstract class HomeSection with _$HomeSection {
  const factory HomeSection({
    /// Stable identity for this block. Two blocks of the same type — an ad slot near
    /// the top and another further down — are told apart by this.
    required String key,

    /// Must match a type the app registered.
    required String type,
    @Default('') String titleAr,
    @Default(0) int sortOrder,
    @Default(true) bool isVisible,
    String? cityId,

    /// Type-specific settings: how many ads a slot rotates, how long for.
    @Default(<String, dynamic>{}) Map<String, dynamic> params,
  }) = _HomeSection;

  factory HomeSection.fromJson(Map<String, dynamic> json) =>
      _$HomeSectionFromJson(json);
}
