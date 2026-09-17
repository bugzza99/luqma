/// What the category chips show, and what the menu is narrowed to.
///
/// One decision rather than two, because the two halves have to agree. They were written
/// as separate lines in `build` and drifted apart in the one case that matters: the chips
/// hide once fewer than two named categories remain, and a selection matching the survivor
/// went on filtering with no chip left to clear it — hiding every dish the merchant never
/// filed under a category, until somebody left the screen and came back. A filter with no
/// visible control is not a filter.
///
/// [namedCategoryIds] is the menu's categories that carry a name, in menu order; a
/// merchant's uncategorised dishes are not one of them. [chosen] is the chip the customer
/// last pressed, which outlives the data it points at — categories arrive on a live
/// subscription, so one can be renamed away or deleted while this screen is open.
({bool showChips, String? selected}) menuFilter({
  required List<String?> namedCategoryIds,
  required String? chosen,
}) {
  // One category is not a choice, and a row holding a single chip reads as a filter that
  // has already been applied.
  final showChips = namedCategoryIds.length >= 2;
  return (
    showChips: showChips,
    selected:
        showChips && namedCategoryIds.contains(chosen) ? chosen : null,
  );
}
