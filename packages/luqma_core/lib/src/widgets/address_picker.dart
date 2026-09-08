import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/motion.dart';
import 'chip.dart';
import 'entrance.dart';
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
/// Written to be shared by CustomerApp and AdminApp, so an address entered on the owner's
/// phone during onboarding is the same shape as one a customer types. **AdminApp does not
/// use it** — as of 2026-09-08 the only caller in the workspace is the customer's address
/// editor. The sentence stood for phases as a description of the product rather than of
/// the code, and it is worth knowing which it is before changing anything here on the
/// belief that two apps depend on it.
class AddressPicker extends ConsumerStatefulWidget {
  const AddressPicker({
    super.key,
    this.initial,
    required this.onSaved,
    this.afterZone,
    this.afterDetails,
    this.saving = false,
  });

  final Address? initial;
  final ValueChanged<Address> onSaved;

  // Slots keep customer-only context out of a form also used during onboarding.
  final Widget Function(Zone? zone)? afterZone;
  final Widget Function(Zone? zone)? afterDetails;
  final bool saving;
  static const fieldHeight = 50.0;

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
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Keyed, all three, and not for the usual list reason. Choosing a
                  // zone inserts the landmark section *between* this one and the
                  // details, so without keys Flutter matches the old details entrance
                  // against the new landmark one and recycles it — which rebuilds every
                  // detail field from `initialValue`, and those are only assigned in
                  // `onSaved`. A customer who typed their street before picking a zone
                  // watched all four fields go blank with nothing said.
                  LuqmaEntrance(
                    key: const ValueKey('address.zone'),
                    index: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(text: strings.addressZone),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final z in zones)
                              LuqmaChip(
                                label: z.name,
                                selected: _zoneId == z.id,
                                onTap: () => setState(() {
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
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colors.danger),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.afterZone != null) widget.afterZone!(zone),
                  if (_zoneId != null) ...[
                    const SizedBox(height: Space.xl),
                    LuqmaEntrance(
                      key: const ValueKey('address.landmark'),
                      index: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(text: strings.addressLandmark),
                          const SizedBox(height: Space.sm),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              for (final l in landmarks)
                                LuqmaChip(
                                  label: l.name,
                                  selected: !_namingOwnLandmark && _landmarkId == l.id,
                                  onTap: () => setState(() {
                                    _landmarkId = l.id;
                                    _namingOwnLandmark = false;
                                  }),
                                ),
                              // The admin's list cannot cover every customer's landmark.
                              LuqmaChip(
                                key: AddressPicker.otherLandmarkKey,
                                label: strings.addressOtherLandmark,
                                dashed: true,
                                selected: _namingOwnLandmark,
                                onTap: () => setState(() {
                                  _namingOwnLandmark = true;
                                  _landmarkId = null;
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: Motion.of(context, Motion.quick),
                      curve: Motion.enter,
                      alignment: Alignment.topCenter,
                      child: _namingOwnLandmark
                          ? Padding(
                              padding: const EdgeInsets.only(top: Space.md),
                              child: TextFormField(
                                key: AddressPicker.landmarkNoteKey,
                                initialValue: _landmarkNote,
                                decoration: InputDecoration(
                                  labelText: strings.addressLandmarkHint,
                                  constraints: const BoxConstraints(
                                    minHeight: AddressPicker.fieldHeight,
                                  ),
                                ),
                                onChanged: (v) => _landmarkNote = v,
                                onSaved: (v) => _landmarkNote = v,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  LuqmaEntrance(
                    key: const ValueKey('address.detail'),
                    index: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionLabel(text: strings.addressDetail),
                        const SizedBox(height: Space.sm),
                        _field(AddressPicker.streetKey, strings.addressStreet,
                          _street, (v) => _street = v),
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            Expanded(child: _field(AddressPicker.buildingKey,
                              strings.addressBuilding, _building, (v) => _building = v)),
                            const SizedBox(width: Space.md),
                            Expanded(child: _field(AddressPicker.floorKey,
                              strings.addressFloor, _floor, (v) => _floor = v)),
                            const SizedBox(width: Space.md),
                            Expanded(child: _field(AddressPicker.apartmentKey,
                              strings.addressApartment, _apartment, (v) => _apartment = v)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.afterDetails != null) widget.afterDetails!(zone),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            padding: const EdgeInsets.all(Space.gutter),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: AddressPicker.saveKey,
                  onPressed: widget.saving ? null : () => _save(allLandmarks),
                  child: Text(strings.addressSave),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(Key key, String label, String? initial, FormFieldSetter<String> save) {
    return TextFormField(
      key: key,
      initialValue: initial,
      decoration: InputDecoration(
        constraints: const BoxConstraints(minHeight: AddressPicker.fieldHeight),
        labelText: label,
      ),
      onSaved: save,
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
