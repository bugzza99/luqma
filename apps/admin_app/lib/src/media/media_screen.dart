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

    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(strings.mediaQueueTitle)),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: pending,
          onRetry: () => ref.invalidate(pendingMediaProvider),
          empty: LuqmaEmptyView(
            key: MediaScreen.emptyKey,
            message: 'مفيش صور مستنية مراجعة.',
          ),
          isEmpty: (value) => value.isEmpty,
          builder: (context, value) => Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    bottom: BorderSide(color: colors.hairline),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: Sizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      strings.mediaQueueWaitingCount(value.length),
                      style: LuqmaType.bodySmall.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(Space.gutter),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    // Wide enough that a photo can actually be judged. A grid of thumbnails
                    // is a grid nobody can review honestly.
                    maxCrossAxisExtent: 360,
                    mainAxisSpacing: Space.md,
                    crossAxisSpacing: Space.md,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _Card(media: value[i]),
                ),
              ),
            ],
          ),
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
        boxShadow: Elevations.card,
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
                // Whole, on a moderation screen above all: an admin cropped to the
                // middle of a photograph approves the middle of it, and whatever is at
                // the edges — a competitor logo, a phone number, something worse —
                // reaches the city unseen.
                fit: BoxFit.contain,
                // A photo that will not load is itself a reason to refuse it, so the
                // failure is shown rather than hidden behind a blank box.
                errorBuilder: (context, _, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: colors.danger,
                        size: 36,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'الصورة مش بتفتح',
                        style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _label(media.kind),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${media.width}×${media.height}',
                      style: LuqmaType.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: MediaScreen.approveKey(media.id),
                        onPressed: () => ref
                            .read(mediaActionsProvider.notifier)
                            .approve(media.id),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.success,
                          foregroundColor: colors.background,
                          shape: const RoundedRectangleBorder(
                            borderRadius: Radii.fieldAll,
                          ),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        child: const Text(
                          'اعتماد',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        key: MediaScreen.rejectKey(media.id),
                        onPressed: () => _reject(context, ref, media.id),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.danger,
                          side: BorderSide(color: colors.danger, width: 1.5),
                          shape: const RoundedRectangleBorder(
                            borderRadius: Radii.fieldAll,
                          ),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        child: const Text(
                          'رفض',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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
    final colors = Theme.of(context).luqma;

    return AlertDialog(
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.sheet),
      ),
      title: const Text('سبب الرفض'),
      content: TextField(
        key: MediaScreen.reasonFieldKey,
        autofocus: true,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'الصورة مش واضحة، الإضاءة وحشة…',
          hintStyle: TextStyle(color: colors.textSecondary),
          border: OutlineInputBorder(
            borderRadius: Radii.fieldAll,
            borderSide: BorderSide(color: colors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.fieldAll,
            borderSide: BorderSide(color: colors.border),
          ),
        ),
        onChanged: (v) => _reason = v,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          child: const Text('إلغاء'),
        ),
        // Not required. A reason is worth asking for — a merchant told nothing simply
        // uploads the same photo again — but blocking the refusal on one would leave bad
        // photos live while somebody thinks of the wording.
        FilledButton(
          key: MediaScreen.confirmRejectKey,
          onPressed: () => widget.onConfirm(_reason),
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: colors.background,
            shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          ),
          child: const Text('ارفض'),
        ),
      ],
    );
  }
}

