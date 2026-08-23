import 'package:freezed_annotation/freezed_annotation.dart';

part 'menu_item.freezed.dart';
part 'menu_item.g.dart';

/// A choice attached to an item — a size, an extra. Priced per unit, in piastres.
@freezed
abstract class MenuOption with _$MenuOption {
  const factory MenuOption({
    required String id,
    required String name,
    @Default(0) int price,
  }) = _MenuOption;

  factory MenuOption.fromJson(Map<String, dynamic> json) => _$MenuOptionFromJson(json);
}

@freezed
abstract class MenuItem with _$MenuItem {
  const factory MenuItem({
    required String id,
    required String merchantId,
    required String categoryId,
    required String name,

    /// Piastres.
    required int price,
    String? description,

    /// Points at a `media` document, which is invisible until an admin approves it.
    /// The item itself stays visible meanwhile — a dish with no photo still sells.
    String? mediaId,

    /// False keeps the item on the merchant's menu and off the customer's.
    @Default(true) bool isAvailable,
    @Default(<MenuOption>[]) List<MenuOption> options,
    @Default(0) int sortOrder,
  }) = _MenuItem;

  factory MenuItem.fromJson(Map<String, dynamic> json) => _$MenuItemFromJson(json);
}
