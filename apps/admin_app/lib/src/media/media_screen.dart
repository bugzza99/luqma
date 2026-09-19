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

  static Key contextKey(String id) => Key('media.context.$id');
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
                  border: Border(bottom: BorderSide(color: colors.hairline)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: Sizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        strings.mediaQueueWaitingCount(value.length),
                        style: LuqmaType.bodySmall.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
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

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.media});

  final Media media;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  bool _isApproving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final media = widget.media;

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
              child: InkWell(
                onTap: () => _openZoom(context, media),
                child: Image.network(
                  media.url,
                  fit: BoxFit.contain,
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
                          style: LuqmaType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
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
                        _mediaKindLabel(media.kind),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (media.width > 0 && media.height > 0)
                      Text(
                        '${media.width}×${media.height}',
                        style: LuqmaType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                // Whose picture, and where it will appear: an admin approving a dish photo
                // has to know which shop's menu it lands on (QA review 2026-09-19). Never
                // the uploader's raw id, which told nobody anything.
                Builder(builder: (context) {
                  final about = ref
                      .watch(pendingMediaContextProvider)
                      .asData
                      ?.value[media.id];
                  final lines = [
                    if (about?.shop != null) 'المحل: ${about!.shop}',
                    if (about?.item != null) 'على: ${about!.item}',
                    if (about?.uploader != null) 'رفعها: ${about!.uploader}',
                    if (media.createdAt != null)
                      formatMediaDateTime(media.createdAt!),
                  ];
                  if (lines.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    key: MediaScreen.contextKey(media.id),
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      lines.join(' · '),
                      style: LuqmaType.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: MediaScreen.approveKey(media.id),
                        onPressed: _isApproving
                            ? null
                            : () async {
                                setState(() => _isApproving = true);
                                final messenger = ScaffoldMessenger.of(context);
                                final res = await ref
                                    .read(mediaActionsProvider.notifier)
                                    .approve(media.id);
                                if (mounted) {
                                  setState(() => _isApproving = false);
                                }
                                if (res.isOk) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('تم اعتماد الصورة بنجاح'),
                                    ),
                                  );
                                } else {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'فشل اعتماد الصورة، حاول مرة أخرى',
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.success,
                          foregroundColor: colors.background,
                          shape: const RoundedRectangleBorder(
                            borderRadius: Radii.fieldAll,
                          ),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        child: _isApproving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.background,
                                ),
                              )
                            : const Text(
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
                        onPressed: _isApproving
                            ? null
                            : () => _reject(context, ref, media.id),
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
}

String _mediaKindLabel(MediaKind kind) => switch (kind) {
  MediaKind.merchantLogo => 'لوجو مطعم',
  MediaKind.merchantCover => 'صورة غلاف',
  MediaKind.menuItem => 'صنف في المنيو',
  MediaKind.dailyMeal => 'وجبة بيتي',
  MediaKind.promotion => 'بانر إعلان',
  MediaKind.aboutPhoto => 'صورة المالك',
  MediaKind.cuisine => 'صورة قسم',
};

String formatMediaDateTime(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final isToday =
      local.year == current.year &&
      local.month == current.month &&
      local.day == current.day;
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  final isYesterday =
      local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;

  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final marker = local.hour >= 12 ? 'م' : 'ص';
  final timeStr = '$hour:$minute$marker';

  if (isToday) {
    return 'النهارده $timeStr';
  } else if (isYesterday) {
    return 'امبارح $timeStr';
  } else {
    final monthName = luqmaMonthName(local.month);
    return '${local.day} $monthName $timeStr';
  }
}

void _openZoom(BuildContext context, Media media) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).luqma;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(_mediaKindLabel(media.kind)),
            leading: IconButton(
              tooltip: 'إغلاق',
              icon: const Icon(Icons.close),
              constraints: const BoxConstraints(
                minWidth: Sizes.minTarget,
                minHeight: Sizes.minTarget,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                media.url,
                fit: BoxFit.contain,
                errorBuilder: (context, _, _) => Center(
                  child: Text(
                    'الصورة مش بتفتح',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _reject(BuildContext context, WidgetRef ref, String id) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _RejectDialog(
      onConfirm: (reason) async {
        final res = await ref
            .read(mediaActionsProvider.notifier)
            .reject(id, reason);
        if (res.isOk && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم رفض الصورة بنجاح')));
        }
        return res;
      },
    ),
  );
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.onConfirm});

  final Future<Result<void>> Function(String reason) onConfirm;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return AlertDialog(
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.sheet),
      ),
      title: const Text('سبب الرفض'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: TextStyle(color: colors.danger)),
            const SizedBox(height: Space.sm),
          ],
          TextField(
            key: MediaScreen.reasonFieldKey,
            controller: _reasonController,
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
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: MediaScreen.confirmRejectKey,
          onPressed: _isSubmitting
              ? null
              : () async {
                  setState(() {
                    _isSubmitting = true;
                    _errorMessage = null;
                  });
                  final res = await widget.onConfirm(
                    _reasonController.text.trim(),
                  );
                  if (mounted && !res.isOk) {
                    setState(() {
                      _isSubmitting = false;
                      _errorMessage = 'فشل رفض الصورة، حاول مرة أخرى';
                    });
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: colors.background,
            shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          ),
          child: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.background,
                  ),
                )
              : const Text('ارفض'),
        ),
      ],
    );
  }
}
