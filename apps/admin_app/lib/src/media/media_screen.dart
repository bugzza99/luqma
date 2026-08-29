import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'media_controller.dart';

/// Reviewing photos before they reach the storefront.
///
/// Photography is what makes a food app read as premium, and one unreviewed picture of a
/// plate under a neon strip undoes a lot of it. This screen is the gate, and it works
/// only because it is the single door: every image in the product is a `media` document
/// and there is no path around it.
class MediaScreen extends ConsumerWidget {
  const MediaScreen({super.key});

  static const emptyKey = Key('media.empty');
  static const reasonFieldKey = Key('media.reason');
  static const confirmRejectKey = Key('media.confirmReject');

  static Key cardKey(String id) => Key('media.card.$id');
  static Key approveKey(String id) => Key('media.approve.$id');
  static Key rejectKey(String id) => Key('media.reject.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingMediaProvider);
    // Watched, not read on demand: the actions object resolves who is reviewing, and a
    // notifier first created by the button press has not resolved that yet — the very
    // first decision of a session would be recorded with nobody attached to it.
    ref.watch(mediaActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الصور')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: pending,
          onRetry: () => ref.invalidate(pendingMediaProvider),
          empty: LuqmaEmptyView(
              key: MediaScreen.emptyKey,
              message: 'مفيش صور مستنية مراجعة.',
            ),
          isEmpty: (value) => value.isEmpty,
          builder: (context, value) => GridView.builder(
              padding: const EdgeInsets.all(Space.gutter),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                // Wide enough that a photo can actually be judged. A grid of thumbnails
                // is a grid nobody can review honestly.
                maxCrossAxisExtent: 340,
                mainAxisSpacing: Space.md,
                crossAxisSpacing: Space.md,
                childAspectRatio: 0.78,
              ),
              itemCount: value.length,
              itemBuilder: (context, i) => _Card(media: value[i]),
            )
        ),
      ),
    );
  }
}


class _Card extends ConsumerWidget {
  const _Card({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: MediaScreen.cardKey(media.id),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: colors.surface,
              child: Image.network(
                media.url,
                fit: BoxFit.cover,
                // A photo that will not load is itself a reason to refuse it, so the
                // failure is shown rather than hidden behind a blank box.
                errorBuilder: (context, _, _) => Center(
                  child: Icon(Icons.broken_image, color: colors.textSecondary),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label(media.kind), style: theme.textTheme.bodySmall),
                Text(
                  '${media.width}×${media.height}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: MediaScreen.approveKey(media.id),
                        onPressed: () => ref
                            .read(mediaActionsProvider.notifier)
                            .approve(media.id),
                        child: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    OutlinedButton(
                      key: MediaScreen.rejectKey(media.id),
                      onPressed: () => _reject(context, ref, media.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.danger,
                        side: BorderSide(color: colors.danger),
                      ),
                      child: const Text('رفض'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(MediaKind kind) => switch (kind) {
        MediaKind.merchantLogo => 'لوجو مطعم',
        MediaKind.merchantCover => 'صورة غلاف',
        MediaKind.menuItem => 'صنف في المنيو',
        MediaKind.dailyMeal => 'وجبة بيتي',
        MediaKind.promotion => 'بانر إعلان',
        MediaKind.aboutPhoto => 'صورة المالك',
        MediaKind.cuisine => 'صورة قسم',
      };
}

Future<void> _reject(BuildContext context, WidgetRef ref, String id) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _RejectDialog(
      onConfirm: (reason) async {
        await ref.read(mediaActionsProvider.notifier).reject(id, reason);
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      },
    ),
  );
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.onConfirm});

  final Future<void> Function(String reason) onConfirm;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  var _reason = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سبب الرفض'),
      content: TextField(
        key: MediaScreen.reasonFieldKey,
        autofocus: true,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'الصورة مش واضحة، الإضاءة وحشة…',
        ),
        onChanged: (v) => _reason = v,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        // Not required. A reason is worth asking for — a merchant told nothing simply
        // uploads the same photo again — but blocking the refusal on one would leave bad
        // photos live while somebody thinks of the wording.
        FilledButton(
          key: MediaScreen.confirmRejectKey,
          onPressed: () => widget.onConfirm(_reason),
          child: const Text('ارفض'),
        ),
      ],
    );
  }
}

