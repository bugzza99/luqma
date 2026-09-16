import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../config/config_controller.dart';
import '../shell/layout.dart';

/// Edits what the customer's «حول لقمة» screen says — the product, and only the product.
///
/// It carried the owner's photo and personal links too until 2026-09-16; those are
/// «عن المطور» now, a page and an editor of their own. What is left is the description.
/// The WhatsApp button on that page is `support_whatsapp`, edited in الإعدادات.
class AboutEditorScreen extends ConsumerWidget {
  const AboutEditorScreen({super.key});

  static const saveKey = Key('about.save');
  static const descriptionKey = Key('about.description');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(adminConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('حول لقمة')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: config,
          onRetry: () => ref.invalidate(adminConfigProvider),
          builder: (context, value) => _AboutForm(initial: value)
        ),
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
  late final _description = _field('about_description');

  bool _busy = false;

  TextEditingController _field(String key) => TextEditingController(
        text: widget.initial[key] is String ? widget.initial[key] as String : '',
      );

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
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
          'الكلام اللي هيظهر للعميل في «حول لقمة» — عن التطبيق نفسه. صورتك ونبذتك في «عن المطور».',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.lg),
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
