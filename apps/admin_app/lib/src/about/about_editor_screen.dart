import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../config/config_controller.dart';
import '../shell/layout.dart';

/// Edits what the customer's "حول لقمة" screen shows.
///
/// Everything is stored on the config table — nothing is compiled in, and the owner
/// fills it in after the screen exists. The photo is the id of an already-approved
/// `media` row: there is no second path for images, so a photo that has not passed the
/// moderation queue is not shown, exactly like every other image.
class AboutEditorScreen extends ConsumerWidget {
  const AboutEditorScreen({super.key});

  static const saveKey = Key('about.save');
  static const descriptionKey = Key('about.description');
  static const photoKey = Key('about.photo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(adminConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('حول لقمة')),
      body: AdminContent(
        child: switch (config) {
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(adminConfigProvider),
            ),
          AsyncValue(hasValue: true, :final value?) => _AboutForm(initial: value),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _AboutForm extends ConsumerStatefulWidget {
  const _AboutForm({required this.initial});

  final Map<String, Object> initial;

  @override
  ConsumerState<_AboutForm> createState() => _AboutFormState();
}

class _AboutFormState extends ConsumerState<_AboutForm> {
  late final _photo = _field('about_photo_media_id');
  late final _facebook = _field('about_facebook');
  late final _whatsapp = _field('about_whatsapp');
  late final _instagram = _field('about_instagram');
  late final _description = _field('about_description');

  bool _busy = false;

  /// The picture as it stands, so the picker shows it rather than a monogram.
  ///
  /// Loaded from the id the config carries, and replaced the moment a new one is
  /// uploaded — an admin's upload is approved as it arrives, so what they see here is
  /// what the customer sees.
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPhoto());
  }

  Future<void> _loadPhoto() async {
    final id = _photo.text.trim();
    if (id.isEmpty) return;

    final result = await ref.read(mediaRepositoryProvider).get(id);
    if (!mounted) return;
    setState(() => _photoUrl = result.valueOrNull?.url);
  }

  TextEditingController _field(String key) => TextEditingController(
        text: widget.initial[key] is String ? widget.initial[key] as String : '',
      );

  @override
  void dispose() {
    for (final c in [_photo, _facebook, _whatsapp, _instagram, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
      'about_photo_media_id': _photo.text.trim(),
      'about_facebook': _facebook.text.trim(),
      'about_whatsapp': _whatsapp.text.trim(),
      'about_instagram': _instagram.text.trim(),
      'about_description': _description.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(switch (failure) {
          OfflineFailure() => 'مفيش نت — جرّب تاني.',
          _ => 'مقدرناش نحفظ. جرّب تاني.',
        })),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
        Text(
          'الصورة والروابط اللي هتظهر للعميل في شاشة "حول لقمة".',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.lg),
        Text('صورتك', style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.sm),
        // Was a text field asking for the uuid of an already-approved image — a workflow
        // that could not be completed, because nothing in the product could upload one.
        MediaPicker(
          key: AboutEditorScreen.photoKey,
          kind: MediaKind.aboutPhoto,
          url: _photoUrl,
          name: 'صورة المالك',
          height: 180,
          onUploaded: (media) => setState(() {
            _photo.text = media.id;
            _photoUrl = media.url;
          }),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _facebook,
          decoration: const InputDecoration(
            labelText: 'رابط فيسبوك',
            hintText: 'https://facebook.com/…',
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _whatsapp,
          decoration: const InputDecoration(labelText: 'رابط واتساب'),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _instagram,
          decoration: const InputDecoration(labelText: 'رابط انستجرام'),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: AboutEditorScreen.descriptionKey,
          controller: _description,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'وصف لقمة'),
        ),
            ],
          ),
        ),
        // Pinned, not the last row of the list: this screen is a form, and its one
        // action should be reachable without hunting for where it scrolled to.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.gutter,
          ),
          child: FilledButton.icon(
            key: AboutEditorScreen.saveKey,
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined, size: Sizes.iconSm),
            label: Text(_busy ? 'جاري…' : 'احفظ'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
          ),
        ),
      ],
    );
  }
}
