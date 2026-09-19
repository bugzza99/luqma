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
  static const deleteKey = Key('cuisines.delete');
  static const deleteConfirmKey = Key('cuisines.delete.confirm');
  static const deleteCancelKey = Key('cuisines.delete.cancel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuisines = ref.watch(cuisinesProvider);
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      appBar: AppBar(title: const Text('تصنيفات المحلات')),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('تصنيف جديد'),
      ),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: cuisines,
          onRetry: () => ref.invalidate(cuisinesProvider),
          empty: Center(
            key: emptyKey,
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(
                'مفيش تصنيفات محلات لسه. أضف أي تصنيف — مطاعم، صيدليات، سوبرماركت — وحط فيه المحلات من صفحة المحل (الدواير اللي فوق في تطبيق العميل).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
          isEmpty: (value) => value.isEmpty,
          builder: (context, value) => ListView.separated(
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
        ),
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

    final order = int.parse(ArabicDigits.fold(_sortOrder.text.trim()));

    final result = await ref.read(cuisineRepositoryProvider).save(
          Cuisine(
            id: widget.existing?.id ?? '',
            cityId: ref.read(currentCityProvider),
            name: _name.trim(),
            mediaId: _mediaId,
            sortOrder: order,
          ),
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التصنيف.')),
        );
      case Err(:final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    setState(() => _busy = true);
    final shopsResult = await ref.read(cuisineRepositoryProvider).merchantsIn(existing.id);
    if (!mounted) return;
    setState(() => _busy = false);

    final count = (shopsResult.valueOrNull ?? {}).length;
    final colors = Theme.of(context).luqma;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('احذف تصنيف «${existing.name}»'),
        content: Text(
          count == 0
              ? 'التصنيف ده مفيهوش أي محلات حالياً. الحذف نهائي وهيشيل التصنيف من التطبيق.'
              : 'التصنيف ده فيه $count ${count == 1 ? 'محل' : count == 2 ? 'محلين' : count <= 10 ? 'محلات' : 'محل'}، وهيخرجوا من التصنيف ده بس مش هيتحذفوا.',
        ),
        actions: [
          TextButton(
            key: CuisinesScreen.deleteCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: CuisinesScreen.deleteConfirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await ref.read(cuisineRepositoryProvider).delete(existing.id);
    if (!mounted) return;

    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف التصنيف.')),
        );
      case Err(:final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (failure) {
              OfflineFailure() => 'مفيش نت — جرّب تاني.',
              PermissionFailure() => 'مش مسموحلك تحذف التصنيف.',
              _ => 'معرفناش نحذف التصنيف. جرّب تاني.',
            }),
          ),
        );
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
                decoration: const InputDecoration(labelText: 'اسم التصنيف'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'اكتب اسم التصنيف' : null,
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
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return 'اكتب رقم';
                  final folded = ArabicDigits.fold(text);
                  if (int.tryParse(folded) == null) return 'اكتب رقم';
                  return null;
                },
              ),
              const SizedBox(height: Space.lg),
              Center(
                child: SizedBox(
                  width: 160,
                  child: MediaPicker(
                    kind: MediaKind.cuisine,
                    url: _mediaUrl,
                    name: _name.isEmpty ? 'تصنيف' : _name,
                    ownerId: widget.existing?.id,
                    onUploaded: (media) => setState(() {
                      _mediaId = media.id;
                      _mediaUrl = media.url;
                    }),
                  ),
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.md),
                Text(
                  switch (_failure!) {
                    OfflineFailure() => 'مفيش نت — جرّب تاني.',
                    ConflictFailure() => 'فيه تصنيف بنفس الاسم بالفعل.',
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
              if (widget.existing != null) ...[
                const SizedBox(height: Space.md),
                OutlinedButton(
                  key: CuisinesScreen.deleteKey,
                  onPressed: _busy ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(color: colors.danger),
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('احذف التصنيف'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
