import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/money.dart';
import '../models/geography.dart';
import '../providers/providers.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../l10n/app_localizations.dart';

/// Collects an address the way people here give one: the zone first, then a landmark,
/// then the fine detail.
///
/// Not a map with a pin. Edku's streets are not systematically numbered and the map data
/// is thin, so a pin tells a courier less than "next to Al-Nour pharmacy" does. The zone
/// also does two jobs beyond addressing — it prices the delivery and bounds which
/// merchants can take the order — which is why it is asked first and never optional.
///
/// Shared by CustomerApp and AdminApp; an address entered on the owner's phone during
/// onboarding is the same shape as one a customer types.
class AddressPicker extends ConsumerStatefulWidget {
  const AddressPicker({super.key, this.initial, required this.onSaved});

  final Address? initial;
  final ValueChanged<Address> onSaved;

  static const saveKey = Key('address.save');
  static const buildingKey = Key('address.building');
  static const floorKey = Key('address.floor');
  static const apartmentKey = Key('address.apartment');
  static const streetKey = Key('address.street');
  static const landmarkNoteKey = Key('address.landmarkNote');
  static const otherLandmarkKey = Key('address.otherLandmark');

  @override
  ConsumerState<AddressPicker> createState() => _AddressPickerState();
}

class _AddressPickerState extends ConsumerState<AddressPicker> {
  final _formKey = GlobalKey<FormState>();

  String? _zoneId;
  String? _landmarkId;
  bool _namingOwnLandmark = false;

  late String? _landmarkNote = widget.initial?.landmarkNote;
  late String? _street = widget.initial?.street;
  late String? _building = widget.initial?.building;
  late String? _floor = widget.initial?.floor;
  late String? _apartment = widget.initial?.apartment;

  @override
  void initState() {
    super.initState();
    _zoneId = widget.initial?.zoneId;
    _landmarkId = widget.initial?.landmarkId;
    _namingOwnLandmark = widget.initial?.landmarkNote?.isNotEmpty ?? false;
  }

  void _save(List<Landmark> landmarks) {
    if (_zoneId == null) {
      // Validated separately from the text fields because the zone is a choice, not an
      // entry, and a form validator cannot point at it.
      setState(() {});
      return;
    }
    _formKey.currentState!.save();

    final landmark = landmarks.where((l) => l.id == _landmarkId).firstOrNull;
    widget.onSaved(
      Address(
        id: widget.initial?.id ?? '',
        zoneId: _zoneId!,
        landmarkId: _namingOwnLandmark ? null : landmark?.id,
        landmarkName: _namingOwnLandmark ? null : landmark?.name,
        landmarkNote: _namingOwnLandmark ? _landmarkNote : null,
        street: _street,
        building: _building,
        floor: _floor,
        apartment: _apartment,
        label: widget.initial?.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    final allLandmarks = ref.watch(landmarksProvider).value ?? const <Landmark>[];

    // Landmarks from another zone are places on the other side of town; offering them is
    // worse than offering none.
    final landmarks = allLandmarks.where((l) => l.zoneId == _zoneId).toList();
    final zone = zones.where((z) => z.id == _zoneId).firstOrNull;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          _SectionLabel(text: strings.addressZone),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final z in zones)
                ChoiceChip(
                  label: Text(z.name),
                  selected: _zoneId == z.id,
                  onSelected: (_) => setState(() {
                    _zoneId = z.id;
                    // A landmark only means anything inside its own zone.
                    _landmarkId = null;
                    _namingOwnLandmark = false;
                  }),
                ),
            ],
          ),
          if (_zoneId == null) ...[
            const SizedBox(height: Space.sm),
            Text(
              strings.addressZoneRequired,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
          if (zone != null) ...[
            const SizedBox(height: Space.md),
            _DeliveryFeeNote(zone: zone, strings: strings),
          ],

          if (_zoneId != null) ...[
            const SizedBox(height: Space.xl),
            _SectionLabel(text: strings.addressLandmark),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final l in landmarks)
                  ChoiceChip(
                    label: Text(l.name),
                    selected: !_namingOwnLandmark && _landmarkId == l.id,
                    onSelected: (_) => setState(() {
                      _landmarkId = l.id;
                      _namingOwnLandmark = false;
                    }),
                  ),
                // The admin's list will never be complete, and a customer whose landmark
                // is missing must not be stuck at this step.
                ChoiceChip(
                  key: AddressPicker.otherLandmarkKey,
                  label: Text(strings.addressOtherLandmark),
                  selected: _namingOwnLandmark,
                  onSelected: (_) => setState(() {
                    _namingOwnLandmark = true;
                    _landmarkId = null;
                  }),
                ),
              ],
            ),
            if (_namingOwnLandmark) ...[
              const SizedBox(height: Space.md),
              TextFormField(
                key: AddressPicker.landmarkNoteKey,
                initialValue: _landmarkNote,
                decoration: InputDecoration(hintText: strings.addressLandmarkHint),
                onSaved: (v) => _landmarkNote = v,
              ),
            ],
          ],

          const SizedBox(height: Space.xl),
          _SectionLabel(text: strings.addressDetail),
          const SizedBox(height: Space.sm),
          TextFormField(
            key: AddressPicker.streetKey,
            initialValue: _street,
            decoration: InputDecoration(labelText: strings.addressStreet),
            onSaved: (v) => _street = v,
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: AddressPicker.buildingKey,
                  initialValue: _building,
                  decoration: InputDecoration(labelText: strings.addressBuilding),
                  onSaved: (v) => _building = v,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextFormField(
                  key: AddressPicker.floorKey,
                  initialValue: _floor,
                  decoration: InputDecoration(labelText: strings.addressFloor),
                  onSaved: (v) => _floor = v,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextFormField(
                  key: AddressPicker.apartmentKey,
                  initialValue: _apartment,
                  decoration: InputDecoration(labelText: strings.addressApartment),
                  onSaved: (v) => _apartment = v,
                ),
              ),
            ],
          ),

          const SizedBox(height: Space.xl),
          FilledButton(
            key: AddressPicker.saveKey,
            onPressed: () => _save(allLandmarks),
            child: Text(strings.addressSave),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

/// Shows what delivery to this zone costs, while the customer is still choosing.
///
/// The fee belongs to the destination, so springing it on someone at checkout — after
/// they have built a basket — is the moment they abandon the order.
class _DeliveryFeeNote extends StatelessWidget {
  const _DeliveryFeeNote({required this.zone, required this.strings});

  final Zone zone;
  final LuqmaStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.fieldAll,
      ),
      child: Text(
        '${strings.addressDeliveryFee} ${strings.price(zone.defaultDeliveryFee)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.price),
      ),
    );
  }
}
