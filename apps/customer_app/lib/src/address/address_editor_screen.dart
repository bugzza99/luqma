import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Customer-only delivery context surrounds the shared address form.
class AddressEditorScreen extends ConsumerStatefulWidget {
  const AddressEditorScreen({super.key, this.initial, this.merchantId});

  final Address? initial;
  final String? merchantId;

  static const labelKey = Key('addressEditor.label');
  static const errorKey = Key('addressEditor.error');

  @override
  ConsumerState<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends ConsumerState<AddressEditorScreen> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');

  Failure? _failure;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save(Address address) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });

    final label = _label.text.trim();
    final result = await ref.read(addressActionsProvider).save(
          address.copyWith(label: label.isEmpty ? null : label),
        );

    if (!mounted) return;

    switch (result) {
      // Sending somebody back to a blank form after a failed save is the app losing
      // their work on its own behalf. The form stays exactly as they left it.
      case Err(:final failure):
        setState(() {
          _saving = false;
          _failure = failure;
        });
      case Ok():
        // Cleared before popping, not instead of it. A screen opened as a root — the
        // first-address flow at checkout has no editor to pop back from — would
        // otherwise sit under a progress bar that never goes away.
        setState(() => _saving = false);
        Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    // Watched, not merely read at save time: the address is saved onto whoever is
    // signed in, so the session has to be live and resolved before the save runs —
    // otherwise the save waits on a provider nothing has started.
    ref.watch(currentIdentityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('عنوان التوصيل'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: Column(
        children: [
          if (_failure != null)
            _ErrorBanner(key: AddressEditorScreen.errorKey, failure: _failure!),
          if (_saving) const LinearProgressIndicator(),
          Expanded(
            child: AddressPicker(
              initial: widget.initial,
              onSaved: _save,
              saving: _saving,
              afterZone: (zone) => _FeeNotice(
                zone: zone, merchantId: widget.merchantId,
              ),
              afterDetails: (zone) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LandmarkMap(zoneId: zone?.id),
                  LuqmaEntrance(
                    index: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.xl),
                      child: TextField(
                        key: AddressEditorScreen.labelKey,
                        controller: _label,
                        decoration: const InputDecoration(
                          labelText: 'اسم العنوان (اختياري)',
                          hintText: 'البيت، الشغل…',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      backgroundColor: colors.background,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({super.key, required this.failure});

  final Failure failure;
  static const _backgroundOpacity = .12;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      width: double.infinity,
      color: colors.danger.withValues(alpha: _backgroundOpacity),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: Sizes.iconSm, color: colors.danger),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              switch (failure) {
                OfflineFailure() => strings.errorOffline,
                PermissionFailure() => 'لازم تسجّل دخول الأول عشان تحفظ عنوان.',
                _ => strings.errorUnknown,
              },
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeNotice extends ConsumerWidget {
  const _FeeNotice({required this.zone, required this.merchantId});

  final Zone? zone;
  final String? merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = merchantId == null ? null
        : ref.watch(merchantProvider(merchantId!)).value;
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);
    final config = ref.watch(appConfigProvider);
    final destination = zone;
    final message = merchant == null || destination == null ? null
        : !Delivery.serves(merchant: merchant, zoneId: destination.id)
            ? 'المطعم مش بيوصل للمنطقة دي'
            : '${strings.addressDeliveryFee} ${strings.price(Delivery.feeFor(
                merchant: merchant, zone: destination, config: config))}';

    // Only the current quote survives a zone change; a departing price must not
    // remain readable while the new destination is already selected.
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.quick),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final child in previous)
            ExcludeSemantics(child: Opacity(opacity: 0, child: child)),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation, alignment: Alignment.topCenter, child: child,
      ),
      child: message == null ? const SizedBox.shrink()
          : Padding(
              key: ValueKey('${destination!.id}:$message'),
              padding: const EdgeInsets.only(top: Space.md),
              child: Container(
                key: const Key('addressEditor.fee'),
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.surface, borderRadius: Radii.fieldAll,
                ),
                child: Text(message,
                  style: LuqmaType.bodySmall.copyWith(color: colors.price)),
              ),
            ),
    );
  }
}

class _LandmarkMap extends ConsumerWidget {
  const _LandmarkMap({required this.zoneId});

  final String? zoneId;
  static const _height = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landmarks = (ref.watch(landmarksProvider).value ?? <Landmark>[])
        .where((l) => l.zoneId == zoneId && l.lat != null && l.lng != null)
        .toList();
    if (landmarks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: LuqmaEntrance(
        index: 3,
        child: LuqmaMap(
          key: ValueKey('addressEditor.map.$zoneId'),
          height: _height,
          showLabels: true,
          markers: [for (final l in landmarks) LuqmaMapMarker(
            id: l.id, lat: l.lat!, lng: l.lng!, label: l.name,
          )],
        ),
      ),
    );
  }
}
