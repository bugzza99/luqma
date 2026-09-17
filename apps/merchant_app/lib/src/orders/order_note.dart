import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

/// The same instruction at acceptance and while cooking. Keeping its presentation
/// together means a note cannot become a badge on one screen and disappear behind
/// an extra tap on the other; the person holding the kitchen phone needs the words.
class OrderNote extends StatelessWidget {
  const OrderNote({super.key, required this.note});

  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = note?.trim() ?? '';
    // Most orders carry none, and a heading over an empty space on every card is how a
    // real instruction stops being noticed on the one card that has it.
    if (text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ملاحظة العميل',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary)),
          const SizedBox(height: Space.xs),
          // No line cap: the end may be the part that says which ingredient to leave
          // out. The database bounds the text, and the order list already scrolls.
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
