import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Shop address editor.
///
/// Reuses the shared [AddressPicker] with its zone locked to `merchant.zoneId`:
/// the database owns the zone (it prices delivery and bounds orders) and protects
/// it against client writes.
class MerchantAddressScreen extends ConsumerStatefulWidget {
  const MerchantAddressScreen({super.key, required this.merchantId});

  final String merchantId;

  static const errorKey = Key('merchantAddress.error');

  @override
  ConsumerState<MerchantAddressScreen> createState() =>
      _MerchantAddressScreenState();
}

class _MerchantAddressScreenState extends ConsumerState<MerchantAddressScreen> {
  Failure? _failure;
  bool _saving = false;

  Future<void> _save(Merchant current, Address address) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });

    // Pin invariant: both halves or neither.
    final (lat, lng) = (address.lat != null && address.lng != null)
        ? (address.lat, address.lng)
        : (null, null);

    final updated = current.copyWith(
      landmarkId: address.landmarkId,
      landmarkName: address.landmarkName ?? address.landmarkNote,
      street: address.street,
      lat: lat,
      lng: lng,
    );

    final result =
        await ref.read(merchantRepositoryProvider).saveMerchant(updated);

    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() {
          _saving = false;
          _failure = failure;
        });
      case Ok():
        setState(() => _saving = false);
        Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final merchantAsync = ref.watch(merchantProvider(widget.merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('عنوان المطعم'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: merchantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => LuqmaErrorView(
          failure: err is Failure ? err : UnknownFailure(err.toString()),
          onRetry: () => ref.invalidate(merchantProvider(widget.merchantId)),
        ),
        data: (merchant) {
          final initialAddress = Address(
            id: '',
            zoneId: merchant.zoneId,
            landmarkId: merchant.landmarkId,
            landmarkName: merchant.landmarkName,
            street: merchant.street,
            lat: merchant.lat,
            lng: merchant.lng,
          );

          return Column(
            children: [
              if (_failure != null)
                Container(
                  key: MerchantAddressScreen.errorKey,
                  width: double.infinity,
                  color: colors.danger.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(
                    switch (_failure!) {
                      OfflineFailure() => LuqmaStrings.of(context).errorOffline,
                      PermissionFailure() => 'معندكش صلاحية لتعديل عنوان المطعم.',
                      _ => LuqmaStrings.of(context).errorUnknown,
                    },
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.danger),
                  ),
                ),
              if (_saving) const LinearProgressIndicator(),
              Expanded(
                child: AddressPicker(
                  initial: initialAddress,
                  lockZone: true,
                  showUnitDetails: false,
                  saving: _saving,
                  onSaved: (addr) => _save(merchant, addr),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
