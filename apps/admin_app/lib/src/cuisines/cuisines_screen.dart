import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// The kinds of food the customer's home is arranged by.
///
/// These are the circles across the top of CustomerApp — city-wide, with a picture each,
/// and deliberately not a merchant's own menu sections. Only an admin edits them: a
/// merchant putting itself in a circle it does not belong in is the cheapest promotion in
/// the product, and promotion is something merchants pay for.
class CuisinesScreen extends ConsumerWidget {
  const CuisinesScreen({super.key});

  static const addKey = Key('cuisines.add');
  static const rowKey = Key('cuisines.row');
  static const emptyKey = Key('cuisines.empty');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuisines = ref.watch(cuisinesProvider);
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      appBar: AppBar(title: const Text('الأقسام')),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('قسم جديد'),
      ),
      body: AdminContent(
        child: switch (cuisines) {
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(cuisinesProvider),
            ),
          AsyncValue(hasValue: true, :final value?) when value.isEmpty => Center(
              key: emptyKey,
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  'مفيش أقسام لسه. الأقسام هي الدواير اللي فوق في تطبيق العميل.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
          AsyncValue(hasValue: true, :final value?) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.gutter,
                Space.gutter,
                Space.xxxl + Space.xl,
              ),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) => _Row(
                cuisine: value[i],
                onTap: () => _edit(context, ref, value[i]),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Cuisine? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CuisineSheet(existing: existing),
    );
    if (saved ?? false) ref.invalidate(cuisinesProvider);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cuisine, required this.onTap});

  final Cuisine cuisine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: CuisinesScreen.rowKey,
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.sm + 2),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: LuqmaImage(url: cuisine.imageUrl, name: cuisine.name),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(cuisine.name, style: theme.textTheme.titleMedium),
            ),
            // Said out loud rather than left to be noticed: a circle with no picture
            // draws a letter on the customer's home, which looks deliberate enough that
            // nobody would think to come back and fix it.
            if (cuisine.imageUrl == null)
              Text(
                'من غير صورة',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _CuisineSheet extends ConsumerStatefulWidget {
  const _CuisineSheet({required this.existing});

  final Cuisine? existing;

  @override
  ConsumerState<_CuisineSheet> createState() => _CuisineSheetState();
}

class _CuisineSheetState extends ConsumerState<_CuisineSheet> {
  final _formKey = GlobalKey<FormState>();

  late String _name = widget.existing?.name ?? '';
  late String? _mediaId = widget.existing?.mediaId;
  late String? _mediaUrl = widget.existing?.imageUrl;
  late final _sortOrder = TextEditingController(
    text: '${widget.existing?.sortOrder ?? 0}',
  );

  bool _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await ref.read(cuisineRepositoryProvider).save(
          Cuisine(
            id: widget.existing?.id ?? '',
            cityId: ref.read(currentCityProvider),
            name: _name.trim(),
            mediaId: _mediaId,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
          ),
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'اسم القسم'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'اكتب اسم القسم' : null,
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الترتيب',
                  helperText: 'الأصغر بيظهر الأول',
                ),
              ),
              const SizedBox(height: Space.lg),
              MediaPicker(
                kind: MediaKind.cuisine,
                url: _mediaUrl,
                name: _name.isEmpty ? 'قسم' : _name,
                ownerId: widget.existing?.id,
                height: 140,
                onUploaded: (media) => setState(() {
                  _mediaId = media.id;
                  _mediaUrl = media.url;
                }),
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.md),
                Text(
                  switch (_failure!) {
                    OfflineFailure() => 'مفيش نت — جرّب تاني.',
                    ConflictFailure() => 'فيه قسم بنفس الاسم بالفعل.',
                    _ => 'مقدرناش نحفظ. جرّب تاني.',
                  },
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
                child: Text(_busy ? 'جاري…' : 'احفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
