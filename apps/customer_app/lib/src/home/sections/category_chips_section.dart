import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The category filter, as a scrolling row rather than a tab of its own.
///
/// Edku will have on the order of thirty merchants — not enough to fill a tab, which is
/// why this ended up inside the home screen. Being a section rather than fixed chrome
/// also means the owner can move it or hide it like anything else here.
class CategoryChipsSection extends ConsumerStatefulWidget {
  const CategoryChipsSection({super.key, required this.section});

  final HomeSection section;

  @override
  ConsumerState<CategoryChipsSection> createState() => _CategoryChipsSectionState();
}

class _CategoryChipsSectionState extends ConsumerState<CategoryChipsSection> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    // Placeholder list until merchant categories are aggregated for the city. The
    // interaction and the layout are what the home screen needs settled first.
    const categories = ['مشويات', 'أسماك', 'كشري', 'حلويات'];

    return SizedBox(
      height: Sizes.minTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        children: [
          _Chip(
            label: 'الكل',
            selected: _selected == null,
            onTap: () => setState(() => _selected = null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: Space.sm),
            _Chip(
              label: category,
              selected: _selected == category,
              onTap: () => setState(() => _selected = category),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: colors.card,
        selectedColor: colors.brand,
        labelStyle: LuqmaType.bodySmall.copyWith(
          color: selected ? colors.onBrand : colors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        side: BorderSide(color: selected ? colors.brand : colors.border),
      ),
    );
  }
}
