import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'plans_editor_controller.dart';

/// Edits the three plans' prices and limits.
///
/// The one place a price change happens without a seed script. Prices are piastres and go
/// through the same `Money` reader the menu editor uses — refused rather than rounded —
/// so a plan the app cannot read exactly is not saved.
class PlansEditorScreen extends ConsumerWidget {
  const PlansEditorScreen({super.key});

  static const emptyKey = Key('plans.empty');

  static Key priceKey(String id) => Key('plans.price.$id');
  static Key saveKey(String id) => Key('plans.save.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(allPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الخطط والأسعار')),
      body: AdminContent(
        child: switch (plans) {
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(allPlansProvider),
            ),
          AsyncValue(hasValue: true, :final value?) when value.isEmpty => Center(
              key: PlansEditorScreen.emptyKey,
              child: Text(
                'مفيش خطط.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).luqma.textSecondary,
                    ),
              ),
            ),
          AsyncValue(hasValue: true, :final value?) => ListView.separated(
              padding: const EdgeInsets.all(Space.gutter),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.md),
              itemBuilder: (context, i) => _PlanEditor(plan: value[i]),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _PlanEditor extends ConsumerStatefulWidget {
  const _PlanEditor({required this.plan});

  final Plan plan;

  @override
  ConsumerState<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends ConsumerState<_PlanEditor> {
  late final _price = TextEditingController(
    text: Money.format(widget.plan.priceMonthly),
  );
  late final _maxItems = TextEditingController(
    text: widget.plan.features.maxItems <= 0
        ? ''
        : widget.plan.features.maxItems.toString(),
  );
  late bool _isActive = widget.plan.isActive;
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _maxItems.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = Money.parse(_price.text.trim());
    if (price == null) {
      _say('اكتب سعر صحيح');
      return;
    }
    // Zero items is how a plan says "unlimited"; a blank field reads the same way.
    final maxItems = _maxItems.text.trim().isEmpty
        ? 0
        : int.tryParse(_maxItems.text.trim());
    if (maxItems == null) {
      _say('اكتب رقم صحيح لعدد الأصناف');
      return;
    }

    setState(() => _busy = true);
    final result = await ref.read(plansActionsProvider.notifier).save(
          widget.plan.copyWith(
            priceMonthly: price,
            features: widget.plan.features.copyWith(maxItems: maxItems),
            isActive: _isActive,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err(:final failure)) {
      _say(switch (failure) {
        OfflineFailure() => 'مفيش نت — جرّب تاني.',
        PermissionFailure() => 'مش مسموح ليك تعدّل الخطط.',
        _ => 'مقدرناش نحفظ. جرّب تاني.',
      });
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.plan.name,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Switch(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: PlansEditorScreen.priceKey(widget.plan.id),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'السعر الشهري (جنيه)',
              suffixText: 'ج',
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _maxItems,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد الأصناف (0 = غير محدود)',
            ),
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            key: PlansEditorScreen.saveKey(widget.plan.id),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
            child: Text(_busy ? 'جاري…' : 'احفظ الخطة'),
          ),
        ],
      ),
    );
  }
}
