import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../config/config_controller.dart';
import '../shell/layout.dart';

/// Edits the customer's «عن المطور» page — the person who made Luqma.
///
/// Split from «حول لقمة» at the owner's request: the photo and personal links used to sit
/// on the product's page. Everything is stored on the config table. The photo is the id
/// of an approved `media` row: there is no second path for images, so a photo that has
/// not passed the moderation queue is not shown, exactly like every other image.
class DeveloperEditorScreen extends ConsumerWidget {
  const DeveloperEditorScreen({super.key});

  static const saveKey = Key('developer.save');
  static const nameKey = Key('developer.name');
  static const bioKey = Key('developer.bio');
  static const photoKey = Key('developer.photo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(adminConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('عن المطور')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: config,
          onRetry: () => ref.invalidate(adminConfigProvider),
          builder: (context, value) => _DeveloperForm(initial: value)
        ),
      ),
    );
  }
}

class _DeveloperForm extends ConsumerStatefulWidget {
  const _DeveloperForm({required this.initial});

  final Map<String, Object> initial;

  @override
  ConsumerState<_DeveloperForm> createState() => _DeveloperFormState();
}

class _DeveloperFormState extends ConsumerState<_DeveloperForm> {
  late final _photo = _field('developer_photo_media_id');
  late final _name = _field('developer_name');
  late final _bio = _field('developer_bio');
  late final _facebook = _field('developer_facebook');
  late final _whatsapp = _field('developer_whatsapp');
  late final _instagram = _field('developer_instagram');

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
    for (final c in [_photo, _name, _bio, _facebook, _whatsapp, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
      'developer_photo_media_id': _photo.text.trim(),
      'developer_name': _name.text.trim(),
      'developer_bio': _bio.text.trim(),
      'developer_facebook': _facebook.text.trim(),
      'developer_whatsapp': _whatsapp.text.trim(),
      'developer_instagram': _instagram.text.trim(),
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
          'اللي هيظهر للعميل في صفحة «عن المطور» — لوحدها، مش جوه «حول لقمة».',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.lg),
        Text('صورتك', style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.sm),
        // Was a text field asking for the uuid of an already-approved image — a workflow
        // that could not be completed, because nothing in the product could upload one.
        MediaPicker(
          key: DeveloperEditorScreen.photoKey,
          kind: MediaKind.aboutPhoto,
          url: _photoUrl,
          name: 'صورة المالك',
          onUploaded: (media) => setState(() {
            _photo.text = media.id;
            _photoUrl = media.url;
          }),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: DeveloperEditorScreen.nameKey,
          controller: _name,
          decoration: const InputDecoration(labelText: 'الاسم'),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: DeveloperEditorScreen.bioKey,
          controller: _bio,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'نبذة عنك'),
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
            key: DeveloperEditorScreen.saveKey,
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
