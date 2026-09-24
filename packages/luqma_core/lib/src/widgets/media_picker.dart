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
/// Whether pictures uploaded in this app arrive approved. False everywhere but AdminApp,
/// which overrides it at its root: the owner's own photographs — six hundred dishes during
/// onboarding — are not something the owner should then approve one by one, and the
/// screen already promised «صورك بتظهر على طول» while the rows waited in the queue
/// (QA review 2026-09-19). The database refuses an approved upload from anybody else.
final uploadsArriveApprovedProvider = Provider<bool>((ref) => false);

class MediaPicker extends ConsumerStatefulWidget {
  const MediaPicker({
    super.key,
    required this.kind,
    required this.url,
    required this.name,
    required this.onUploaded,
    this.ownerId,
    this.approved = false,
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

  /// An admin's picture: it arrives approved and is on the product at once. AdminApp
  /// passes it; the database refuses it from anybody else.
  final bool approved;

  static const pickKey = Key('mediaPicker.pick');
  static const errorKey = Key('mediaPicker.error');
  static const pendingKey = Key('mediaPicker.pending');
  static const hintKey = Key('mediaPicker.hint');

  /// Logo badges are drawn square at 2x minTarget rather than stretched across the card.
  static const logoPreviewSize = 96.0;

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
      final shrink = ref.read(shrinkImageProvider);
      final bytes = await shrink(picked);
      // The small copy lists and thumbnails draw, cut from the photograph just made
      // rather than from the camera's original: a 1600px decode, not a twelve-megapixel
      // one, for the second pass.
      final small = await shrink(
        bytes,
        maxEdge: ImageCompressor.smallEdge,
        quality: ImageCompressor.smallQuality,
      );
      final (width, height) = ImageCompressor.dimensionsOf(bytes);
      // Whoever is signed in, read here rather than passed in: the policy on `media`
      // requires `uploaded_by = auth.uid()`, so there has only ever been one correct
      // value for it, and a parameter is somewhere a caller can put a different one.
      result = await ref.read(mediaRepositoryProvider).upload(
            kind: widget.kind,
            bytes: bytes,
            small: small,
            uploadedBy: ref.read(currentIdentityProvider).value?.uid ?? '',
            ownerId: widget.ownerId,
            width: width,
            height: height,
            approved: widget.approved || ref.read(uploadsArriveApprovedProvider),
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

    final previewImage = LuqmaImage(url: widget.url, name: widget.name);
    final Widget preview;
    if (widget.kind == MediaKind.merchantLogo) {
      preview = Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRRect(
          borderRadius: Radii.cardAll,
          child: SizedBox.square(
            dimension: MediaPicker.logoPreviewSize,
            child: previewImage,
          ),
        ),
      );
    } else {
      // Capped in height: at full width a dish photo filled a phone screen and pushed the
      // name and the price below the fold of the very sheet that edits them.
      preview = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ClipRRect(
            borderRadius: Radii.cardAll,
            child: AspectRatio(
              aspectRatio: widget.kind.aspectRatio,
              child: previewImage,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        preview,
        const SizedBox(height: Space.xs),
        Text(
          // A sentence, so it lives in the ARB file rather than on the enum: the model says
          // what size, the l10n says how to say it, and English stays a file.
          LuqmaStrings.of(context).mediaRecommendedSize(
              '${widget.kind.recommendedWidth}', '${widget.kind.recommendedHeight}'),
          key: MediaPicker.hintKey,
          style:
              theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
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
