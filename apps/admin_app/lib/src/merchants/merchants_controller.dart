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
///
/// Deliberately still per merchant. `orders.merchant_id` is `on delete restrict`, so this
/// number is a decision rather than a label, and it has to be true at the moment the
/// control is offered — not when the list behind it was built.
@riverpod
Future<int> merchantOrderCount(Ref ref, String merchantId) async {
  final result =
      await ref.watch(merchantRepositoryProvider).orderCount(merchantId);
  return result.valueOrThrow;
}

/// The same figure for every shop in the city, fetched once for the whole list.
///
/// Each card used to watch `merchantOrderCount` for its own shop, so the screen cost one
/// round trip per merchant — invisible with two shops, and the screen the owner lives on
/// during the launch.
///
/// A card reads this and draws nothing while it is loading or if it fails: the count is a
/// detail under a shop's name, and a list that refuses to render because a label could
/// not be fetched is worse than a list with no labels.
@riverpod
Future<Map<String, int>> merchantOrderCounts(Ref ref) async {
  final result = await ref
      .watch(merchantRepositoryProvider)
      .orderCounts(cityId: ref.watch(currentCityProvider));
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

  Future<Result<void>> setStatus(String id, MerchantStatus status) async {
    final result = await ref.read(merchantRepositoryProvider).setStatus(id, status);
    ref.invalidate(allMerchantsProvider);
    return result;
  }

  /// Creates a merchant from what the owner typed while sitting in the restaurant.
  ///
  /// Left pending on purpose. Entering the data and deciding the merchant is ready to
  /// take orders are two different moments, often days apart — a menu is usually half
  /// finished when the first visit ends.
  /// Adds a shop under an id the form minted when it opened.
  ///
  /// Returns the [Result] rather than a nullable merchant: the dialog has to tell the
  /// three failures apart — no connection, not allowed, a name the server refused — and
  /// a null says only that something went wrong. It used to return null and the dialog
  /// closed anyway, so a failed create looked exactly like a successful one and took the
  /// owner's typing with it.
  ///
  /// [id] is the idempotency. The same id on a retry cannot make a second shop.
  Future<Result<Merchant>> create({
    required String id,
    required String name,
    required String phone,
    required String zoneId,
    required MerchantType type,
  }) async {
    final result = await ref.read(merchantRepositoryProvider).createMerchant(
          Merchant(
            id: id,
            cityId: ref.read(currentCityProvider),
            type: type,
            name: name,
            zoneId: zoneId,
            phone: phone,
            status: MerchantStatus.pending,
          ),
        );
    ref.invalidate(allMerchantsProvider);
    ref.invalidate(merchantOrderCountsProvider);
    return result;
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
