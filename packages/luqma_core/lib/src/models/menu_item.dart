import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/column_names.dart';

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

  /// A `menu_items` row, with the two places the table is looser than this model.
  ///
  /// `category_id` is `on delete set null` on purpose: deleting a category must not take
  /// the dishes with it — somebody has to be able to re-file them. So a dish really can
  /// arrive with no category, and every reader of the table has to expect it.
  ///
  /// It lives here rather than in a repository because it was in one, privately, and the
  /// next repository to read this table did not know: an uncategorised dish threw
  /// `type 'Null' is not a subtype of type 'String'` inside the search, and because the
  /// rows are mapped in a loop, one orphaned dish took the whole city's search with it —
  /// on the one screen `docs/04` removed the categories tab in favour of.
  static MenuItem fromRow(Map<String, dynamic> row) {
    final model = ColumnNames.toModel(row);
    model['categoryId'] ??= '';
    model['options'] ??= <dynamic>[];
    return MenuItem.fromJson(model);
  }
}
