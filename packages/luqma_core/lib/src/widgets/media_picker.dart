import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../media/image_compressor.dart';
import '../models/media.dart';
import '../providers/providers.dart';
import '../result.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'luqma_image.dart';

/// The one control that puts a picture into this product.
///
/// Shared by the menu editor, the daily-meal form, a merchant's logo and cover, the
/// cuisines editor and حول لقمة — six places, one widget. What it must never become is
/// six pickers that each learned the moderation rule separately, because five of them
/// would learn it slightly differently and the sixth would forget.
///
/// Everything between the gallery and the bucket happens here: pick, refuse what is not
/// a picture, shrink, upload, and then say plainly that the photograph is not live yet.
/// That last part is not decoration — a merchant who uploads a photo of their fish,
/// opens CustomerApp and sees nothing will upload it again, and again.
class MediaPicker extends ConsumerStatefulWidget {
  const MediaPicker({
    super.key,
    required this.kind,
    required this.url,
    required this.name,
    required this.onUploaded,
    this.ownerId,
    this.height = 160,
  });

  /// What the picture is of. Decides the path in the bucket and the moderation lane.
  final MediaKind kind;

  /// The approved image already attached, or null.
  final String? url;

  /// What this is a picture of — the monogram and the accessible name come from it.
  final String name;

  /// Who the image belongs to: a merchant id for a logo, a meal id for a meal.
  final String? ownerId;

  /// Called with the filed `media` row. The caller stores `media.id` on whatever it is
  /// editing — this widget never writes to another table.
  final ValueChanged<Media> onUploaded;

  final double height;

  static const pickKey = Key('mediaPicker.pick');
  static const errorKey = Key('mediaPicker.error');
  static const pendingKey = Key('mediaPicker.pending');

  @override
  ConsumerState<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends ConsumerState<MediaPicker> {
  bool _busy = false;
  Failure? _failure;
  bool _justUploaded = false;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    final picked = await ref.read(pickImageProvider)();
    if (!mounted) return;

    // Null is "changed their mind", and it ends here quietly.
    if (picked == null) {
      setState(() => _busy = false);
      return;
    }

    // Shrunk before anything is sent, so a caller cannot forget and a phone on mobile
    // data never uploads eight megabytes of a plate of fish.
    final Result<Media> result;
    try {
      final bytes = await ImageCompressor.shrink(picked);
      // Whoever is signed in, read here rather than passed in: the policy on `media`
      // requires `uploaded_by = auth.uid()`, so there has only ever been one correct
      // value for it, and a parameter is somewhere a caller can put a different one.
      result = await ref.read(mediaRepositoryProvider).upload(
            kind: widget.kind,
            bytes: bytes,
            uploadedBy: ref.read(currentIdentityProvider).value?.uid ?? '',
            ownerId: widget.ownerId,
          );
    } on FormatException {
      // Whatever was chosen is not an image this build can read — a video, a PDF, a file
      // that arrived broken. Its own sentence, because it is the one failure the person
      // can fix themselves by picking something else.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = const NotAnImageFailure();
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case Ok(:final value):
          _justUploaded = true;
          widget.onUploaded(value);
        case Err(:final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: Radii.cardAll,
          child: SizedBox(
            height: widget.height,
            child: LuqmaImage(url: widget.url, name: widget.name),
          ),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          key: MediaPicker.pickKey,
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.photo_camera_outlined, size: Sizes.iconSm),
          label: Text(
            _busy
                ? 'لحظة…'
                : (widget.url == null ? 'أضف صورة' : 'غيّر الصورة'),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(Sizes.minTarget),
            side: BorderSide(color: colors.border),
          ),
        ),
        if (_failure != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            key: MediaPicker.errorKey,
            switch (_failure!) {
              NotAnImageFailure() => 'الملف ده مش صورة. اختار صورة تانية.',
              OfflineFailure() => strings.errorOffline,
              PermissionFailure() => strings.errorPermission,
              _ => 'مقدرناش نرفع الصورة. جرّب تاني.',
            },
            style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
          ),
        ],
        // Said once, after an upload, and not on every rebuild afterwards: the merchant
        // needs to know why the photo has not appeared, not to be told off for it.
        if (_justUploaded && _failure == null) ...[
          const SizedBox(height: Space.sm),
          Row(
            key: MediaPicker.pendingKey,
            children: [
              Icon(Icons.schedule, size: Sizes.iconSm, color: colors.textSecondary),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  'الصورة اترفعت، وهتظهر بعد المراجعة.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
