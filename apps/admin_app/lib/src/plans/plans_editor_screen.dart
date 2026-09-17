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
  static Key boostKey(String id) => Key('plans.boost.$id');
  static Key verifiedKey(String id) => Key('plans.verified.$id');
  static Key bannersKey(String id) => Key('plans.banners.$id');
  static Key pushesKey(String id) => Key('plans.pushes.$id');
  static Key saveKey(String id) => Key('plans.save.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final plans = ref.watch(allPlansProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('الخطط والأسعار')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: plans,
          onRetry: () => ref.invalidate(allPlansProvider),
          empty: LuqmaEmptyView(
            key: PlansEditorScreen.emptyKey,
            message: 'مفيش خطط.',
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
                  border: Border(
                    bottom: BorderSide(color: colors.hairline),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: Sizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        strings.plansSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(Space.gutter),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (context, i) => _PlanEditor(plan: value[i]),
                ),
              ),
            ],
          ),
        ),
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
  late final _banners = TextEditingController(
    text: widget.plan.features.homeBannerSlots <= 0
        ? ''
        : widget.plan.features.homeBannerSlots.toString(),
  );
  late final _pushes = TextEditingController(
    text: widget.plan.features.monthlyPromotionCount <= 0
        ? ''
        : widget.plan.features.monthlyPromotionCount.toString(),
  );
  late bool _boost = widget.plan.features.boostRank;
  late bool _verified = widget.plan.features.verifiedBadge;
  late bool _isActive = widget.plan.isActive;
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _banners.dispose();
    _pushes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = Money.parse(_price.text.trim());
    if (price == null) {
      _say('اكتب سعر صحيح');
      return;
    }
    // A blank count is none — the shop gets no free placements of that kind.
    final banners = _banners.text.trim().isEmpty ? 0 : int.tryParse(_banners.text.trim());
    final pushes = _pushes.text.trim().isEmpty ? 0 : int.tryParse(_pushes.text.trim());
    if (banners == null || banners < 0 || pushes == null || pushes < 0) {
      _say('اكتب رقم صحيح للبانرات والإشعارات');
      return;
    }

    setState(() => _busy = true);
    final result = await ref.read(plansActionsProvider.notifier).save(
          widget.plan.copyWith(
            priceMonthly: price,
            features: widget.plan.features.copyWith(
              boostRank: _boost,
              verifiedBadge: _verified,
              homeBannerSlots: banners,
              monthlyPromotionCount: pushes,
            ),
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
    final strings = LuqmaStrings.of(context);

    final isBrandHeader = widget.plan.priceMonthly > 0;
    final headerBg = isBrandHeader ? colors.brand : colors.surface;
    final headerFg = isBrandHeader ? colors.background : colors.textPrimary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(
          color: widget.plan.id == 'pro' ? colors.brand : colors.hairline,
          width: widget.plan.id == 'pro' ? 1.5 : 1.0,
        ),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            color: headerBg,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        widget.plan.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: headerFg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.plan.isFree) ...[
                        const SizedBox(width: Space.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.textPrimary.withValues(alpha: 0.1),
                            borderRadius: Radii.pillAll,
                          ),
                          child: Text(
                            strings.plansFreeBadge,
                            style: LuqmaType.caption.copyWith(
                              color: headerFg,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ] else if (!_isActive) ...[
                        const SizedBox(width: Space.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.danger,
                            borderRadius: Radii.pillAll,
                          ),
                          child: Text(
                            strings.plansInactiveBadge,
                            style: LuqmaType.caption.copyWith(
                              color: colors.background,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isActive ? 'مفعلة' : 'معطلة',
                      style: LuqmaType.caption.copyWith(
                        color: headerFg.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeThumbColor:
                          isBrandHeader ? colors.background : colors.brand,
                      activeTrackColor: isBrandHeader
                          ? colors.background.withValues(alpha: 0.4)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      widget.plan.isFree
                          ? 'مجاني'
                          : Money.format(widget.plan.priceMonthly),
                      style: LuqmaType.price.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (!widget.plan.isFree) ...[
                      const SizedBox(width: Space.xs),
                      Text(
                        'ج / شهر',
                        style: LuqmaType.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.sm),
                // Four benefits, and every one of them is now enforced (2026-09-17): the
                // subscription itself replaces the commission, `boostRank` lifts the shop in
                // the customer's list, `verifiedBadge` draws «موثّق» beside its name, and the
                // two counts are free placements a month, decided by the server when the shop
                // asks. What is deliberately not here: the item limit and "analytics", which
                // nothing reads — every shop has its own numbers and no menu is capped.
                const Divider(height: Space.lg),
                TextField(
                  key: PlansEditorScreen.priceKey(widget.plan.id),
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'السعر الشهري (جنيه)',
                    suffixText: 'ج',
                    border: OutlineInputBorder(
                      borderRadius: Radii.fieldAll,
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                // A row rather than a `SwitchListTile`: this card paints its own background,
                // and a list tile inside one asserts that its ink would be invisible.
                _FeatureSwitch(
                  switchKey: PlansEditorScreen.boostKey(widget.plan.id),
                  title: 'ظهور في الأول',
                  subtitle: 'المحل يطلع فوق في قايمة المطاعم',
                  value: _boost,
                  onChanged: (v) => setState(() => _boost = v),
                ),
                _FeatureSwitch(
                  switchKey: PlansEditorScreen.verifiedKey(widget.plan.id),
                  title: 'علامة «موثّق»',
                  subtitle: 'شارة جنب اسم المحل عند العميل',
                  value: _verified,
                  onChanged: (v) => setState(() => _verified = v),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  key: PlansEditorScreen.bannersKey(widget.plan.id),
                  controller: _banners,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'بانرات مجانية في الشهر (فاضي = مفيش)',
                    border: OutlineInputBorder(borderRadius: Radii.fieldAll),
                  ),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  key: PlansEditorScreen.pushesKey(widget.plan.id),
                  controller: _pushes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'إشعارات مجانية في الشهر (فاضي = مفيش)',
                    border: OutlineInputBorder(borderRadius: Radii.fieldAll),
                  ),
                ),
                const SizedBox(height: Space.md),
                FilledButton(
                  key: PlansEditorScreen.saveKey(widget.plan.id),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                    backgroundColor: colors.brand,
                    foregroundColor: colors.background,
                    shape: const RoundedRectangleBorder(
                      borderRadius: Radii.fieldAll,
                    ),
                  ),
                  child: Text(
                    _busy ? 'جاري…' : 'احفظ الخطة',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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

class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ],
    );
  }
}
