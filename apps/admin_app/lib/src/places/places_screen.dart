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
              child: switch (state) {
                AsyncLoading() => const Center(child: CircularProgressIndicator()),
                AsyncError(:final error) => _Error(failure: error),
                AsyncData(:final value) => switch (_tab) {
                    _Tab.zones => _Zones(zones: value.zones),
                    _Tab.landmarks =>
                      _Landmarks(zones: value.zones, landmarks: value.landmarks),
                    _Tab.suggestions => _Suggestions(
                        suggestions: value.suggestions,
                        zones: value.zones,
                      ),
                  },
              },
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
            onPressed: () => _editLandmark(
              context,
              ref,
              null,
              state.value?.zones ?? const [],
            ),
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
    final colors = Theme.of(context).luqma;

    return Padding(
      padding: const EdgeInsets.all(Space.gutter),
      child: Row(
        children: [
          _TabButton(
            tabKey: PlacesScreen.zonesTabKey,
            label: 'المناطق',
            selected: current == _Tab.zones,
            onTap: () => onChanged(_Tab.zones),
          ),
          const SizedBox(width: Space.sm),
          _TabButton(
            tabKey: PlacesScreen.landmarksTabKey,
            label: 'العلامات',
            selected: current == _Tab.landmarks,
            onTap: () => onChanged(_Tab.landmarks),
          ),
          const SizedBox(width: Space.sm),
          _TabButton(
            tabKey: PlacesScreen.suggestionsTabKey,
            // The count carries the whole message: there is work waiting, and how much.
            label: suggestionCount > 0 ? 'مقترحة ($suggestionCount)' : 'مقترحة',
            selected: current == _Tab.suggestions,
            highlight: suggestionCount > 0 ? colors.accent : null,
            onTap: () => onChanged(_Tab.suggestions),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tabKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.highlight,
  });

  final Key tabKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return ChoiceChip(
      key: tabKey,
      label: Text(label),
      selected: selected,
      // The accent marks unreviewed work, which is exactly the "offers and things needing
      // attention" role it is reserved for.
      side: highlight != null && !selected ? BorderSide(color: highlight!, width: 1.5) : null,
      onSelected: (_) => onTap(),
      backgroundColor: colors.card,
    );
  }
}

class _Zones extends ConsumerWidget {
  const _Zones({required this.zones});

  final List<Zone> zones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LuqmaStrings.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      itemCount: zones.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final zone = zones[i];
        return _Row(
          title: zone.name,
          trailing: Text(
            strings.price(zone.defaultDeliveryFee),
            style: TextStyle(
              color: Theme.of(context).luqma.price,
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: () => _editZone(context, ref, zone),
        );
      },
    );
  }
}

class _Landmarks extends ConsumerWidget {
  const _Landmarks({required this.zones, required this.landmarks});

  final List<Zone> zones;
  final List<Landmark> landmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      children: [
        for (final zone in zones) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(zone.name, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final landmark in landmarks.where((l) => l.zoneId == zone.id))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _Row(
                title: landmark.name,
                onTap: () => _editLandmark(context, ref, landmark, zones),
              ),
            ),
        ],
      ],
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.suggestions, required this.zones});

  final List<LandmarkSuggestion> suggestions;
  final List<Zone> zones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    if (suggestions.isEmpty) {
      return Center(
        key: PlacesScreen.noSuggestionsKey,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            'مفيش أماكن جديدة دلوقتي.\nلما عميل يكتب علامة مش في اللستة، هتلاقيها هنا.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final suggestion = suggestions[i];
        final zone = zones.where((z) => z.id == suggestion.zoneId).firstOrNull;

        return _Row(
          title: suggestion.name,
          // Where and how often — the two things that decide whether it is real.
          subtitle: '${zone?.name ?? suggestion.zoneId} · '
              'اتكتبت ${suggestion.count} مرة',
          trailing: FilledButton(
            key: PlacesScreen.acceptSuggestionKey(suggestion.name),
            onPressed: () => ref
                .read(placesControllerProvider.notifier)
                .acceptSuggestion(suggestion),
            child: const Text('أضف'),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing, this.onTap});

  final String title;
  final String? subtitle;
  final Widget? trailing;
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
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);
    return Center(
      child: Text(switch (failure) {
        OfflineFailure() => strings.errorOffline,
        PermissionFailure() => strings.errorPermission,
        _ => strings.errorUnknown,
      }),
    );
  }
}

Future<void> _editZone(BuildContext context, WidgetRef ref, Zone? existing) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditDialog(
      title: existing == null ? 'منطقة جديدة' : 'تعديل المنطقة',
      initialName: existing?.name,
      initialFee: existing == null ? null : Money.format(existing.defaultDeliveryFee),
      onSave: (name, fee, _) async {
        await ref.read(placesControllerProvider.notifier).saveZone(
              existing: existing,
              name: name,
              deliveryFee: fee ?? 0,
            );
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      },
    ),
  );
}

Future<void> _editLandmark(
  BuildContext context,
  WidgetRef ref,
  Landmark? existing,
  List<Zone> zones,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditDialog(
      title: existing == null ? 'علامة جديدة' : 'تعديل العلامة',
      initialName: existing?.name,
      zones: zones,
      initialZoneId: existing?.zoneId ?? zones.firstOrNull?.id,
      onDelete: existing == null
          ? null
          : () async {
              await ref
                  .read(placesControllerProvider.notifier)
                  .deleteLandmark(existing.id);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
      onSave: (name, _, zoneId) async {
        await ref.read(placesControllerProvider.notifier).saveLandmark(
              existing: existing,
              name: name,
              zoneId: zoneId ?? zones.first.id,
            );
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
  final Future<void> Function(String name, int? fee, String? zoneId) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _name = widget.initialName ?? '';
  late String _fee = widget.initialFee ?? '';
  late String? _zoneId = widget.initialZoneId;

  @override
  Widget build(BuildContext context) {
    final wantsFee = widget.initialFee != null || widget.zones == null;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                validator: (v) =>
                    Money.parse(v ?? '') == null ? 'اكتب رقم صحيح' : null,
                onSaved: (v) => _fee = v!,
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
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).luqma.danger,
            ),
            child: const Text('احذف'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: PlacesScreen.saveKey,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            _formKey.currentState!.save();
            widget.onSave(_name, Money.parse(_fee), _zoneId);
          },
          child: const Text('احفظ'),
        ),
      ],
    );
  }
}
