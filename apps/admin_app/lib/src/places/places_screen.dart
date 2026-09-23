import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'places_controller.dart';

/// Where Edku's addressing layer is maintained: the zones, the landmarks, and the places
/// customers named that are not on the map yet.
///
/// The third tab is the reason this screen is shaped the way it is. Nobody can write the
/// landmark list in advance — not even someone who lives here — so it grows from the
/// notes customers type when the list does not have theirs. Every one of those notes is a
/// place a courier already had to be told about.
class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  static const zonesTabKey = Key('places.tab.zones');
  static const landmarksTabKey = Key('places.tab.landmarks');
  static const suggestionsTabKey = Key('places.tab.suggestions');
  static const addZoneKey = Key('places.addZone');
  static const addLandmarkKey = Key('places.addLandmark');
  static const nameFieldKey = Key('places.name');
  static const feeFieldKey = Key('places.fee');
  static const zoneFieldKey = Key('places.zone');
  static const saveKey = Key('places.save');
  static const noSuggestionsKey = Key('places.noSuggestions');

  static Key acceptSuggestionKey(String name) => Key('places.accept.$name');

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

enum _Tab { zones, landmarks, suggestions }

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  _Tab _tab = _Tab.zones;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(placesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الأماكن')),
      body: AdminContent(
        child: Column(
          children: [
            _Tabs(
              current: _tab,
              suggestionCount: state.value?.suggestions.length ?? 0,
              onChanged: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: LuqmaAsyncView(
                value: state,
                onRetry: () => ref.invalidate(placesControllerProvider),
                builder: (context, value) => switch (_tab) {
                  _Tab.zones => _Zones(
                    zones: value.zones,
                    landmarks: value.landmarks,
                  ),
                  _Tab.landmarks => _Landmarks(
                    zones: value.zones,
                    landmarks: value.landmarks,
                  ),
                  _Tab.suggestions => _Suggestions(
                    suggestions: value.suggestions,
                    zones: value.zones,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: switch (_tab) {
        _Tab.zones => FloatingActionButton.extended(
          key: PlacesScreen.addZoneKey,
          onPressed: () => _editZone(context, ref, null),
          icon: const Icon(Icons.add),
          label: const Text('منطقة'),
        ),
        _Tab.landmarks => FloatingActionButton.extended(
          key: PlacesScreen.addLandmarkKey,
          onPressed: () =>
              _editLandmark(context, ref, null, state.value?.zones ?? const []),
          icon: const Icon(Icons.add),
          label: const Text('علامة'),
        ),
        // Nothing to add by hand here — the list is what customers already told us.
        _Tab.suggestions => null,
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.current,
    required this.suggestionCount,
    required this.onChanged,
  });

  final _Tab current;
  final int suggestionCount;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.gutter),
      // A Wrap: on a narrow phone the third tab moves to a second line rather than
      // leaving the screen.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            LuqmaChip(
              key: PlacesScreen.zonesTabKey,
              label: 'المناطق',
              selected: current == _Tab.zones,
              onTap: () => onChanged(_Tab.zones),
            ),
            LuqmaChip(
              key: PlacesScreen.landmarksTabKey,
              label: 'العلامات',
              selected: current == _Tab.landmarks,
              onTap: () => onChanged(_Tab.landmarks),
            ),
            LuqmaChip(
              key: PlacesScreen.suggestionsTabKey,
              // The count carries the whole message: there is work waiting, and how much.
              label: suggestionCount > 0
                  ? 'مقترحة ($suggestionCount)'
                  : 'مقترحة',
              selected: current == _Tab.suggestions,
              onTap: () => onChanged(_Tab.suggestions),
            ),
          ],
        ),
      ),
    );
  }
}

class _Zones extends StatelessWidget {
  const _Zones({required this.zones, required this.landmarks});

  final List<Zone> zones;
  final List<Landmark> landmarks;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.sm,
        bottom: 88,
      ),
      itemCount: zones.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final zone = zones[i];
        final zoneLandmarks = landmarks
            .where((l) => l.zoneId == zone.id)
            .toList();
        return _ZoneCard(zone: zone, landmarks: zoneLandmarks, allZones: zones);
      },
    );
  }
}

class _ZoneCard extends StatefulWidget {
  const _ZoneCard({
    required this.zone,
    required this.landmarks,
    required this.allZones,
  });

  final Zone zone;
  final List<Landmark> landmarks;
  final List<Zone> allZones;

  @override
  State<_ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends State<_ZoneCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.landmarks.length <= 8;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Consumer(
        builder: (context, ref, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _editZone(context, ref, widget.zone),
              borderRadius: Radii.cardAll,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.zone.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'إدكو',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    strings.price(widget.zone.defaultDeliveryFee),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.price,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Divider(height: 1, color: colors.hairline),
            const SizedBox(height: Space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    strings.placesLandmarksHeader,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.landmarks.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    borderRadius: Radii.pillAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.xs,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded
                                ? (widget.landmarks.length > 8
                                      ? 'إخفاء (${widget.landmarks.length})'
                                      : '${widget.landmarks.length} علامة')
                                : '${widget.landmarks.length} علامة',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                            color: colors.brand,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    '${widget.landmarks.length} علامة',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final landmark in widget.landmarks)
                    LuqmaChip(
                      label: '📍 ${landmark.name}',
                      selected: false,
                      onTap: () => _editLandmark(
                        context,
                        ref,
                        landmark,
                        widget.allZones,
                      ),
                    ),
                  LuqmaChip(
                    label: strings.placesAddLandmarkChip,
                    selected: false,
                    dashed: true,
                    onTap: () => _editLandmark(
                      context,
                      ref,
                      null,
                      widget.allZones,
                      initialZoneId: widget.zone.id,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Landmarks extends StatefulWidget {
  const _Landmarks({required this.zones, required this.landmarks});

  final List<Zone> zones;
  final List<Landmark> landmarks;

  @override
  State<_Landmarks> createState() => _LandmarksState();
}

class _LandmarksState extends State<_Landmarks> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    if (widget.zones.isEmpty) {
      return Consumer(
        builder: (context, ref, _) => LuqmaEmptyView(
          message: 'ضيف منطقة الأول',
          action: FilledButton(
            onPressed: () => _editZone(context, ref, null),
            child: const Text('إضافة منطقة'),
          ),
        ),
      );
    }

    final query = ArabicText.normalize(_searchQuery.trim());
    final filteredLandmarks = query.isEmpty
        ? widget.landmarks
        : widget.landmarks
              .where((l) => ArabicText.normalize(l.name).contains(query))
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xs,
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'بحث في العلامات…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: Radii.fieldAll,
                borderSide: BorderSide(color: Theme.of(context).luqma.hairline),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              return ListView(
                padding: const EdgeInsets.only(
                  left: Space.gutter,
                  right: Space.gutter,
                  bottom: 88,
                ),
                children: [
                  for (final zone in widget.zones) ...[
                    if (query.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Text(
                          zone.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final landmark in filteredLandmarks.where(
                        (l) => l.zoneId == zone.id,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _Row(
                            title: landmark.name,
                            onTap: () => _editLandmark(
                              context,
                              ref,
                              landmark,
                              widget.zones,
                            ),
                          ),
                        ),
                    ] else if (filteredLandmarks.any(
                      (l) => l.zoneId == zone.id,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Text(
                          zone.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final landmark in filteredLandmarks.where(
                        (l) => l.zoneId == zone.id,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _Row(
                            title: landmark.name,
                            onTap: () => _editLandmark(
                              context,
                              ref,
                              landmark,
                              widget.zones,
                            ),
                          ),
                        ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.zones});

  final List<LandmarkSuggestion> suggestions;
  final List<Zone> zones;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const LuqmaEmptyView(
        key: PlacesScreen.noSuggestionsKey,
        message:
            'مفيش أماكن جديدة دلوقتي.\nلما عميل يكتب علامة مش في اللستة، هتلاقيها هنا.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.sm,
        bottom: 88,
      ),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        return _SuggestionRow(suggestion: suggestions[i], zones: zones);
      },
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({required this.suggestion, required this.zones});

  final LandmarkSuggestion suggestion;
  final List<Zone> zones;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    final zone = widget.zones
        .where((z) => z.id == suggestion.zoneId)
        .firstOrNull;

    return Consumer(
      builder: (context, ref, _) {
        return _Row(
          title: suggestion.name,
          subtitle:
              '${zone?.name ?? suggestion.zoneId} · '
              'اتكتبت ${suggestion.count} مرة',
          // Below the name rather than beside it: three buttons beside a place name left
          // the name a column one letter wide on a phone.
          footer: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              IconButton(
                key: Key('places.dismiss.${suggestion.name}'),
                tooltip: 'رفض الاقتراح',
                icon: const Icon(Icons.close_rounded),
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('رفض «${suggestion.name}»'),
                            content: const Text(
                              'مش هيظهر هنا تاني حتى لو العملاء كتبوه تاني.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('رجوع'),
                              ),
                              FilledButton(
                                key: const Key('places.confirmDismiss'),
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('ارفض'),
                              ),
                            ],
                          ),
                        );
                        if (sure != true || !context.mounted) return;
                        setState(() => _isSubmitting = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final res = await ref
                            .read(placesControllerProvider.notifier)
                            .dismissSuggestion(suggestion);
                        if (mounted) setState(() => _isSubmitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              res.isOk
                                  ? 'اترفض الاقتراح'
                                  : 'مقدرناش نرفضه. جرّب تاني.',
                            ),
                          ),
                        );
                      },
              ),
              OutlinedButton(
                key: Key('places.editAccept.${suggestion.name}'),
                onPressed: _isSubmitting
                    ? null
                    : () => _editLandmark(
                        context,
                        ref,
                        null,
                        widget.zones,
                        initialZoneId: suggestion.zoneId,
                        initialName: suggestion.name,
                      ),
                child: const Text('عدّل واقبل'),
              ),
              const SizedBox(width: Space.xs),
              FilledButton(
                key: PlacesScreen.acceptSuggestionKey(suggestion.name),
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        setState(() => _isSubmitting = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final res = await ref
                            .read(placesControllerProvider.notifier)
                            .acceptSuggestion(suggestion);
                        if (mounted) {
                          setState(() => _isSubmitting = false);
                        }
                        if (res.isOk) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('تمت إضافة العلامة بنجاح'),
                            ),
                          );
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('فشل إضافة العلامة')),
                          );
                        }
                      },
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('أضف'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.footer,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? footer;

  Widget _withFooter(Widget row) => footer == null
      ? row
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            const SizedBox(height: Space.sm),
            footer!,
          ],
        );
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        child: _withFooter(
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _editZone(BuildContext context, WidgetRef ref, Zone? existing) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditDialog(
      title: existing == null ? 'منطقة جديدة' : 'تعديل المنطقة',
      initialName: existing?.name,
      initialFee: existing == null
          ? null
          : Money.format(existing.defaultDeliveryFee),
      onSave: (name, fee, _) async {
        final res = await ref
            .read(placesControllerProvider.notifier)
            .saveZone(existing: existing, name: name, deliveryFee: fee ?? 0);
        if (res.isOk && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم حفظ المنطقة بنجاح')));
        }
        return res;
      },
    ),
  );
}

Future<void> _editLandmark(
  BuildContext context,
  WidgetRef ref,
  Landmark? existing,
  List<Zone> zones, {
  String? initialZoneId,
  String? initialName,
}) {
  if (zones.isEmpty) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ضيف منطقة الأول'),
        content: const Text('لازم تضيف منطقة قبل ما تضيف علامة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _editZone(context, ref, null);
            },
            child: const Text('إضافة منطقة'),
          ),
        ],
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditDialog(
      title: existing == null ? 'علامة جديدة' : 'تعديل العلامة',
      initialName: existing?.name ?? initialName,
      zones: zones,
      initialZoneId:
          zones.any((z) => z.id == (existing?.zoneId ?? initialZoneId))
          ? (existing?.zoneId ?? initialZoneId)
          : zones.firstOrNull?.id,
      // A moderator does not delete (D5): the database refuses it.
      onDelete: existing == null || ref.read(staffIdentityProvider).isModerator
          ? null
          : () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: Text('حذف ${existing.name}'),
                  content: Text(
                    'هل أنت متأكد من حذف "${existing.name}"؟ العناوين اللي استخدمتها هتحتفظ بالنص لكن هتفقد ربط العلامة.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(confirmContext).luqma.danger,
                      ),
                      child: const Text('حذف'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return null;

              final res = await ref
                  .read(placesControllerProvider.notifier)
                  .deleteLandmark(existing.id);
              if (res.isOk && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف العلامة بنجاح')),
                );
              } else if (!res.isOk && dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('فشل حذف العلامة')),
                );
              }
              return res;
            },
      onSave: (name, _, zoneId) async {
        final res = await ref
            .read(placesControllerProvider.notifier)
            .saveLandmark(
              existing: existing,
              name: name,
              zoneId: zoneId ?? zones.firstOrNull?.id ?? '',
            );
        if (res.isOk && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم حفظ العلامة بنجاح')));
        }
        return res;
      },
    ),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.onSave,
    this.initialName,
    this.initialFee,
    this.zones,
    this.initialZoneId,
    this.onDelete,
  });

  final String title;
  final String? initialName;
  final String? initialFee;
  final List<Zone>? zones;
  final String? initialZoneId;
  final Future<Result<dynamic>> Function(String name, int? fee, String? zoneId)
  onSave;
  final Future<Result<dynamic>?> Function()? onDelete;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _name = widget.initialName ?? '';
  late String _fee = widget.initialFee ?? '';
  late String? _zoneId = widget.initialZoneId;
  bool _isSubmitting = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final wantsFee = widget.initialFee != null || widget.zones == null;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).luqma.danger),
              ),
              const SizedBox(height: Space.sm),
            ],
            TextFormField(
              key: PlacesScreen.nameFieldKey,
              initialValue: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'اكتب الاسم' : null,
              onSaved: (v) => _name = v!.trim(),
            ),
            if (wantsFee) ...[
              const SizedBox(height: Space.md),
              TextFormField(
                key: PlacesScreen.feeFieldKey,
                initialValue: _fee,
                decoration: const InputDecoration(labelText: 'التوصيل بالجنيه'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final folded = ArabicDigits.fold(v ?? '');
                  return Money.parse(folded) == null ? 'اكتب رقم صحيح' : null;
                },
                onSaved: (v) => _fee = ArabicDigits.fold(v ?? ''),
              ),
            ],
            if (widget.zones != null) ...[
              const SizedBox(height: Space.md),
              DropdownButtonFormField<String>(
                key: PlacesScreen.zoneFieldKey,
                initialValue: _zoneId,
                decoration: const InputDecoration(labelText: 'المنطقة'),
                items: [
                  for (final zone in widget.zones!)
                    DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                ],
                onChanged: (v) => setState(() => _zoneId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() {
                      _isSubmitting = true;
                      _errorMessage = null;
                    });
                    final res = await widget.onDelete!();
                    if (res == null) {
                      if (mounted) setState(() => _isSubmitting = false);
                      return;
                    }
                    if (mounted && !res.isOk) {
                      setState(() {
                        _isSubmitting = false;
                        _errorMessage = 'فشل الحذف';
                      });
                    }
                  },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).luqma.danger,
            ),
            child: const Text('احذف'),
          ),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: PlacesScreen.saveKey,
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  _formKey.currentState!.save();
                  setState(() {
                    _isSubmitting = true;
                    _saving = true;
                    _errorMessage = null;
                  });
                  final res = await widget.onSave(
                    _name,
                    Money.parse(_fee),
                    _zoneId,
                  );
                  if (mounted && !res.isOk) {
                    setState(() {
                      _isSubmitting = false;
                      _saving = false;
                      _errorMessage = 'فشل الحفظ، حاول مرة أخرى';
                    });
                  }
                },
          // Spins only for a save: a delete waits on its own confirmation first, and a
          // spinner under that question read as if the save had started.
          child: _isSubmitting && _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('احفظ'),
        ),
      ],
    );
  }
}
