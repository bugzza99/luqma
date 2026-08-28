import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'merchants_controller.g.dart';

/// Every merchant in the city, whatever their status.
///
/// Deliberately not the customer-facing list: the ones waiting for approval are the
/// reason this screen exists, and a suspended merchant hidden here would have nowhere
/// left to be reinstated from.
@riverpod
Stream<List<Merchant>> allMerchants(Ref ref) => ref
    .watch(merchantRepositoryProvider)
    .watchAllMerchants(cityId: ref.watch(currentCityProvider));

/// How many orders one merchant has taken — the real query the delete control is
/// decided on. Delete is offered only while this is zero.
@riverpod
Future<int> merchantOrderCount(Ref ref, String merchantId) async {
  final result =
      await ref.watch(merchantRepositoryProvider).orderCount(merchantId);
  return result.valueOrThrow;
}

/// Which merchant the detail pane is showing. Null on a wide screen means the list is
/// waiting for a choice; on a phone it means the list is what is on screen.
///
/// Kept alive so the selection survives the list rebuilding after a save.
@Riverpod(keepAlive: true)
class SelectedMerchant extends _$SelectedMerchant {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Commands rather than state.
///
/// Kept alive because it is auto-disposed otherwise: nothing ever *watches* an actions
/// object, so it would be created by the `read` that invokes a command and disposed again
/// while that command was still in flight — the write silently never lands.
@Riverpod(keepAlive: true)
class MerchantActions extends _$MerchantActions {
  @override
  void build() {}

  Future<void> setStatus(String id, MerchantStatus status) async {
    await ref.read(merchantRepositoryProvider).setStatus(id, status);
    ref.invalidate(allMerchantsProvider);
  }

  /// Creates a merchant from what the owner typed while sitting in the restaurant.
  ///
  /// Left pending on purpose. Entering the data and deciding the merchant is ready to
  /// take orders are two different moments, often days apart — a menu is usually half
  /// finished when the first visit ends.
  Future<Merchant?> create({
    required String name,
    required String phone,
    required String zoneId,
    required MerchantType type,
  }) async {
    final result = await ref.read(merchantRepositoryProvider).saveMerchant(
          Merchant(
            id: '',
            cityId: ref.read(currentCityProvider),
            type: type,
            name: name,
            zoneId: zoneId,
            phone: phone,
            status: MerchantStatus.pending,
          ),
        );
    ref.invalidate(allMerchantsProvider);
    return result.valueOrNull;
  }

  Future<void> update(Merchant merchant) async {
    await ref.read(merchantRepositoryProvider).saveMerchant(merchant);
    ref.invalidate(allMerchantsProvider);
  }

  /// Deletes a merchant that never traded. The screen checks the count first; the
  /// database's foreign key is what makes that promise keepable rather than remembered.
  Future<Result<void>> delete(String id) async {
    final result = await ref.read(merchantRepositoryProvider).deleteMerchant(id);
    ref.invalidate(allMerchantsProvider);
    return result;
  }
}
