/// The one translation between Postgres columns and the models.
///
/// The database is `snake_case` because unquoted identifiers in Postgres fold to lower
/// case — `merchantId` becomes `merchantid`, silently — and quoting every identifier for
/// ever would poison every policy and every query anybody types by hand.
///
/// The models keep the camelCase JSON they already had. Nothing above the repositories
/// learns that the backend changed, which is the whole reason the migration is a swap
/// rather than a rewrite.
///
/// **Only the top level is renamed.** A `jsonb` column arrives as a decoded map whose
/// inner keys the app itself wrote, already camelCase; renaming those again would turn
/// `unitPrice` into something no model has ever heard of.
abstract final class ColumnNames {
  const ColumnNames._();

  /// A row from Postgres, as the models expect it.
  static Map<String, dynamic> toModel(Map<String, dynamic> row) =>
      {for (final entry in row.entries) _camel(entry.key): entry.value};

  /// A model's JSON, as Postgres expects it.
  static Map<String, dynamic> toRow(Map<String, dynamic> json) =>
      {for (final entry in json.entries) _snake(entry.key): entry.value};

  static String _camel(String column) {
    final parts = column.split('_');
    if (parts.length == 1) return column;

    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
            .join();
  }

  static String _snake(String field) {
    // Already snake_case — a name written that way on purpose. Splitting it again would
    // produce `merchant__id`, and the insert would fail on a column nobody has.
    if (field.contains('_')) return field;

    return field.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m[0]!.toLowerCase()}',
    );
  }
}
