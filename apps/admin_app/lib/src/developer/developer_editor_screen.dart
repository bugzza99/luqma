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
  static const previewKey = Key('developer.preview');
  static const previewDialogKey = Key('developer.previewDialog');
  static const nameKey = Key('developer.name');
  static const bioKey = Key('developer.bio');
  static const photoKey = Key('developer.photo');
  static const facebookKey = Key('developer.facebook');
  static const whatsappKey = Key('developer.whatsapp');
  static const instagramKey = Key('developer.instagram');

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

  late Map<String, String> _saved;
  bool _busy = false;

  String? _facebookError;
  String? _whatsappError;
  String? _instagramError;

  bool get _hasUnsavedChanges =>
      _photo.text.trim() != _saved['developer_photo_media_id'] ||
      _name.text.trim() != _saved['developer_name'] ||
      _bio.text.trim() != _saved['developer_bio'] ||
      _facebook.text.trim() != _saved['developer_facebook'] ||
      _whatsapp.text.trim() != _saved['developer_whatsapp'] ||
      _instagram.text.trim() != _saved['developer_instagram'];

  /// The picture as it stands, so the picker shows it rather than a monogram.
  ///
  /// Loaded from the id the config carries, and replaced the moment a new one is
  /// uploaded — an admin's upload is approved as it arrives, so what they see here is
  /// what the customer sees.
  String? _photoUrl;

  /// The page as a customer will see it, drawn from what is typed now — and each link
  /// opens, so a wrong one is found here rather than by a customer.
  Future<void> _preview() {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final links = [
      ('فيسبوك', _facebook.text.trim()),
      ('واتساب', _whatsapp.text.trim()),
      ('انستجرام', _instagram.text.trim()),
    ].where((l) => l.$2.isNotEmpty).toList();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: DeveloperEditorScreen.previewDialogKey,
        title: const Text('كده هتظهر للعملاء'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_photoUrl != null)
                ClipOval(
                  child: Image.network(_photoUrl!, width: 96, height: 96, fit: BoxFit.cover),
                )
              else
                CircleAvatar(
                  radius: 48,
                  backgroundColor: colors.surface,
                  child: Icon(Icons.person_outline_rounded, color: colors.textSecondary),
                ),
              const SizedBox(height: Space.md),
              Text(
                _name.text.trim().isEmpty ? '(من غير اسم)' : _name.text.trim(),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (_bio.text.trim().isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Text(_bio.text.trim(), textAlign: TextAlign.center),
              ],
              const SizedBox(height: Space.md),
              for (final (label, url) in links)
                TextButton(
                  onPressed: () => openExternalLink(
                    dialogContext,
                    ref,
                    Uri.parse(url),
                    whenUnavailable: 'الرابط ده مش بيفتح — راجعه.',
                  ),
                  child: Text('جرّب رابط $label'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _saved = {
      'developer_photo_media_id': _photo.text.trim(),
      'developer_name': _name.text.trim(),
      'developer_bio': _bio.text.trim(),
      'developer_facebook': _facebook.text.trim(),
      'developer_whatsapp': _whatsapp.text.trim(),
      'developer_instagram': _instagram.text.trim(),
    };
    for (final c in [_photo, _name, _bio, _facebook, _whatsapp, _instagram]) {
      c.addListener(_onTextChanged);
    }
    unawaited(_loadPhoto());
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
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
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _facebookError = null;
      _whatsappError = null;
      _instagramError = null;
    });

    final fb = _facebook.text.trim();
    final wa = _whatsapp.text.trim();
    final ig = _instagram.text.trim();

    if (fb.isNotEmpty && !fb.startsWith('https://')) {
      _facebookError = 'الرابط لازم يبدأ بـ https://';
    }
    if (ig.isNotEmpty && !ig.startsWith('https://')) {
      _instagramError = 'الرابط لازم يبدأ بـ https://';
    }
    if (wa.isNotEmpty && !Phone.isValidEgyptianMobile(wa)) {
      _whatsappError = 'اكتب رقم موبايل مصري صحيح';
    }

    if (_facebookError != null || _whatsappError != null || _instagramError != null) {
      setState(() {});
      return;
    }

    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
      'developer_photo_media_id': _photo.text.trim(),
      'developer_name': _name.text.trim(),
      'developer_bio': _bio.text.trim(),
      'developer_facebook': fb,
      'developer_whatsapp': wa,
      'developer_instagram': ig,
    });
    if (!mounted) return;
    setState(() => _busy = false);

    if (result is Ok) {
      setState(() {
        _saved = {
          'developer_photo_media_id': _photo.text.trim(),
          'developer_name': _name.text.trim(),
          'developer_bio': _bio.text.trim(),
          'developer_facebook': fb,
          'developer_whatsapp': wa,
          'developer_instagram': ig,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اتحفظ')),
      );
    } else if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(switch (failure) {
          OfflineFailure() => 'مفيش نت — جرّب تاني.',
          _ => 'مقدرناش نحفظ. جرّب تاني.',
        })),
      );
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسيب التعديلات من غير حفظ؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('سيب'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Column(
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
                  key: DeveloperEditorScreen.facebookKey,
                  controller: _facebook,
                  decoration: InputDecoration(
                    labelText: 'رابط فيسبوك',
                    hintText: 'https://facebook.com/…',
                    errorText: _facebookError,
                  ),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  key: DeveloperEditorScreen.whatsappKey,
                  controller: _whatsapp,
                  decoration: InputDecoration(
                    labelText: 'رابط واتساب',
                    hintText: '01012345678',
                    errorText: _whatsappError,
                  ),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  key: DeveloperEditorScreen.instagramKey,
                  controller: _instagram,
                  decoration: InputDecoration(
                    labelText: 'رابط انستجرام',
                    hintText: 'https://instagram.com/…',
                    errorText: _instagramError,
                  ),
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
            child: Row(
              children: [
                // Seen as a customer sees it, links included, before it is published — a
                // typo in a link used to be found by a customer (QA review 2026-09-19).
                Expanded(
                  child: OutlinedButton.icon(
                    key: DeveloperEditorScreen.previewKey,
                    onPressed: _preview,
                    icon: const Icon(Icons.visibility_outlined, size: Sizes.iconSm),
                    label: const Text('معاينة'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  flex: 2,
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
            ),
          ),
        ],
      ),
    );
  }
}
