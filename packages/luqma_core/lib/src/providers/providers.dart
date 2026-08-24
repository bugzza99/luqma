// `Order` here would be Firestore's index-definition enum, not ours.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/auth_service.dart';
import '../auth/staff_identity.dart';
import '../config/luqma_config.dart';
import '../config/remote_config_service.dart';
import '../models/geography.dart';
import '../models/home_section.dart';
import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../models/billing.dart';
import '../models/daily_meal.dart';
import '../models/order.dart';
import '../models/promotion.dart';
import '../repositories/address_repository.dart';
import '../repositories/billing_repository.dart';
import '../repositories/courier_order_repository.dart';
import '../repositories/daily_meal_repository.dart';
import '../repositories/feedback_repository.dart';
import '../repositories/geography_repository.dart';
import '../repositories/home_section_repository.dart';
import '../repositories/media_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/merchant_order_repository.dart';
import '../repositories/merchant_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/promotion_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';

part 'providers.g.dart';

/// The Firestore instance. Overridden in tests and in the emulator harness, which is why
/// it is a provider rather than a static reference reached for from wherever.
///
/// Being replaced, one repository at a time. When the last thing reading it has moved,
/// this and the package behind it go with it.
@Riverpod(keepAlive: true)
FirebaseFirestore firestore(Ref ref) => FirebaseFirestore.instance;

/// The Supabase client. A provider for the same reason: the live tests hand it a client
/// pointed at the local stack, and nothing below has to know which one it got.
@Riverpod(keepAlive: true)
SupabaseClient supabase(Ref ref) => Supabase.instance.client;

/// The city this build is serving.
///
/// A provider rather than a constant so opening a second city is a value change, not a
/// migration — every query downstream is already scoped by it.
@Riverpod(keepAlive: true)
String currentCity(Ref ref) => 'edku';

@Riverpod(keepAlive: true)
MerchantRepository merchantRepository(Ref ref) =>
    FirestoreMerchantRepository(ref.watch(firestoreProvider));

@Riverpod(keepAlive: true)
GeographyRepository geographyRepository(Ref ref) =>
    SupabaseGeographyRepository(ref.watch(supabaseProvider));

/// The city's zones. Kept alive because they change about once a month and every address
/// screen needs them.
@Riverpod(keepAlive: true)
Future<List<Zone>> zones(Ref ref) async {
  final result = await ref.watch(geographyRepositoryProvider).zones(
        cityId: ref.watch(currentCityProvider),
      );
  return result.valueOrThrow;
}

@Riverpod(keepAlive: true)
Future<List<Landmark>> landmarks(Ref ref) async {
  final result = await ref.watch(geographyRepositoryProvider).landmarks(
        cityId: ref.watch(currentCityProvider),
      );
  return result.valueOrThrow;
}

@Riverpod(keepAlive: true)
HomeSectionRepository homeSectionRepository(Ref ref) =>
    FirestoreHomeSectionRepository(ref.watch(firestoreProvider));

/// The customer home screen's arrangement, live.
@riverpod
Stream<List<HomeSection>> homeSections(Ref ref) => ref
    .watch(homeSectionRepositoryProvider)
    .watchSections(cityId: ref.watch(currentCityProvider));

@Riverpod(keepAlive: true)
MediaRepository mediaRepository(Ref ref) =>
    FirestoreMediaRepository(ref.watch(firestoreProvider));

@Riverpod(keepAlive: true)
MenuRepository menuRepository(Ref ref) =>
    FirestoreMenuRepository(ref.watch(firestoreProvider));

@riverpod
Stream<List<MenuCategory>> menuCategories(Ref ref, String merchantId) =>
    ref.watch(menuRepositoryProvider).watchCategories(merchantId);

@riverpod
Stream<List<MenuItem>> menuItems(Ref ref, String merchantId) =>
    ref.watch(menuRepositoryProvider).watchItems(merchantId);

/// Merchants a customer may see in [cityId]. Live.
@riverpod
Stream<List<Merchant>> merchants(Ref ref, String cityId) =>
    ref.watch(merchantRepositoryProvider).watchMerchants(cityId: cityId);

/// One merchant, by id.
///
/// Throws the [Failure] rather than surfacing a `Result`, so the screen above reads it
/// as an `AsyncValue` and gets loading, data and error from one `switch` — the same
/// shape every other read on the screen already has.
@riverpod
Future<Merchant> merchant(Ref ref, String id) async {
  final result = await ref.watch(merchantRepositoryProvider).getMerchant(id);
  return result.valueOrThrow;
}

// ------------------------------------------------------------------ identity

/// Where a session comes from.
///
/// Deliberately has no default. Google's SDK lives in the app, not here, so a default
/// would either drag that dependency into every package or quietly hand back a service
/// that can never sign anybody in. Overridden once, in `main`.
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) => throw UnimplementedError(
      'Override authServiceProvider in main(). The Google credential source lives in '
      'the app, so luqma_core cannot build one.',
    );

/// Who is signed in right now, or null.
///
/// Seeded with whatever the session already resolved to before following changes: the
/// change stream is a broadcast, so a listener attaching after sign-in would otherwise
/// hear nothing until the next sign-out.
@Riverpod(keepAlive: true)
Stream<LuqmaIdentity?> currentIdentity(Ref ref) async* {
  final auth = ref.watch(authServiceProvider);
  await auth.restore();
  yield auth.identity;
  yield* auth.changes;
}

/// What the signed-in staff account is allowed to be.
///
/// Collapses "still resolving" into "nobody", so it is for screens *behind* a gate that
/// has already made that distinction — never for the gate itself, which has to tell the
/// two apart or it flashes a sign-in screen at somebody already signed in.
@Riverpod(keepAlive: true)
StaffIdentity staffIdentity(Ref ref) => switch (ref.watch(currentIdentityProvider)) {
      AsyncData(:final value) => StaffIdentity.from(value),
      _ => StaffIdentity.none,
    };

@Riverpod(keepAlive: true)
PromotionRepository promotionRepository(Ref ref) =>
    FirestorePromotionRepository(ref.watch(firestoreProvider));

/// Placements that should be on screen right now, best first. Live.
@riverpod
Stream<List<Promotion>> livePromotions(Ref ref) =>
    ref.watch(promotionRepositoryProvider).watchLive(
          cityId: ref.watch(currentCityProvider),
          now: ref.watch(clockProvider)(),
        );

/// Merchants who have paid for a lift right now.
///
/// Derived rather than stored on the merchant: a boost is a promotion with dates, and a
/// flag on the merchant would be a second thing to expire and a second thing to forget.
@riverpod
Set<String> boostedMerchants(Ref ref) {
  final live = ref.watch(livePromotionsProvider).value ?? const <Promotion>[];
  return {
    for (final promotion in live)
      if (promotion.channel == PromotionChannel.boost) promotion.merchantId,
  };
}

/// What is waiting for an admin decision. Live.
@riverpod
Stream<List<Promotion>> promotionQueue(Ref ref) =>
    ref.watch(promotionRepositoryProvider).watchQueue(ref.watch(currentCityProvider));

/// One merchant's own campaigns, whatever became of them. Live.
@riverpod
Stream<List<Promotion>> merchantPromotions(Ref ref, String merchantId) =>
    ref.watch(promotionRepositoryProvider).watchForMerchant(merchantId);

/// Whether the city has any marketing push left this week.
///
/// A cap on the *city*, not on one merchant. The thing being rationed is a customer's
/// patience, and it does not care which shop the third notification came from — three
/// pushes in a week from three merchants is still three notifications on one phone.
@riverpod
Future<bool> pushSlotAvailable(Ref ref) async {
  final config = ref.watch(appConfigProvider);
  final now = ref.watch(clockProvider)();

  final sent = await ref.watch(promotionRepositoryProvider).pushesSentSince(
        cityId: ref.watch(currentCityProvider),
        since: now.subtract(const Duration(days: 7)),
      );

  // Unreadable means unknown, and unknown must not open the gate: the cost of one push
  // too many is customers turning notifications off for good.
  return (sent.valueOrNull ?? config.marketingPushPerWeek) <
      config.marketingPushPerWeek;
}

@Riverpod(keepAlive: true)
BillingRepository billingRepository(Ref ref) =>
    FirestoreBillingRepository(ref.watch(firestoreProvider));

/// The plans on offer. Kept alive: three documents that change a few times a year, and
/// every merchant screen wants them.
@Riverpod(keepAlive: true)
Future<List<Plan>> plans(Ref ref) async {
  final result = await ref.watch(billingRepositoryProvider).plans();
  return result.valueOrThrow;
}

/// One merchant's most recent term, expired or not. Live.
@riverpod
Stream<Subscription?> subscription(Ref ref, String merchantId) =>
    ref.watch(billingRepositoryProvider).watchSubscription(merchantId);

@Riverpod(keepAlive: true)
CourierOrderRepository courierOrderRepository(Ref ref) =>
    FirestoreCourierOrderRepository(ref.watch(firestoreProvider));

/// What one merchant's own courier has to take out. Live.
@riverpod
Stream<List<Order>> merchantDeliveries(Ref ref, String merchantId) =>
    ref.watch(courierOrderRepositoryProvider).watchForMerchant(merchantId);

/// What Luqma's courier has to take out: home kitchens, and merchants that do not
/// deliver for themselves. Live.
@riverpod
Stream<List<Order>> platformDeliveries(Ref ref, String cityId) =>
    ref.watch(courierOrderRepositoryProvider).watchForPlatform(cityId);

@Riverpod(keepAlive: true)
DailyMealRepository dailyMealRepository(Ref ref) =>
    FirestoreDailyMealRepository(ref.watch(firestoreProvider));

/// What time it is.
///
/// A seam rather than `DateTime.now()` scattered through widgets. Home kitchens are the
/// reason: whether a meal can still be reserved depends on the day *and* the collection
/// window, so a test that cannot move the clock can only be written by waiting for a
/// Tuesday afternoon. It also keeps every screen agreeing on the same instant, which a
/// dozen separate `now()` calls do not.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// The day the app is showing, derived from [clock].
@riverpod
String today(Ref ref) => DailyMeal.dayKeyOf(ref.watch(clockProvider)());

/// Today's home-cooked meals in this city. Live.
@riverpod
Stream<List<DailyMeal>> todaysMeals(Ref ref) =>
    ref.watch(dailyMealRepositoryProvider).watchToday(
          cityId: ref.watch(currentCityProvider),
          day: ref.watch(todayProvider),
        );

/// One kitchen's own meals, drafts included. Live.
@riverpod
Stream<List<DailyMeal>> merchantMeals(Ref ref, String merchantId) =>
    ref.watch(dailyMealRepositoryProvider).watchForMerchant(merchantId);

@Riverpod(keepAlive: true)
FeedbackRepository feedbackRepository(Ref ref) =>
    FirestoreFeedbackRepository(ref.watch(firestoreProvider));

/// What customers said about one merchant. Live.
@riverpod
Stream<List<CustomerRating>> merchantFeedback(Ref ref, String merchantId) =>
    ref.watch(feedbackRepositoryProvider).watchFeedback(merchantId);

@Riverpod(keepAlive: true)
MerchantOrderRepository merchantOrderRepository(Ref ref) =>
    FirestoreMerchantOrderRepository(ref.watch(firestoreProvider));

/// Orders waiting for this kitchen to answer. Live, oldest first.
@riverpod
Stream<List<Order>> incomingOrders(Ref ref, String merchantId) =>
    ref.watch(merchantOrderRepositoryProvider).watchIncoming(merchantId);

/// Accepted, cooking, or on the road. Live.
@riverpod
Stream<List<Order>> liveOrders(Ref ref, String merchantId) =>
    ref.watch(merchantOrderRepositoryProvider).watchLive(merchantId);

/// One order, from the kitchen's side.
@riverpod
Stream<Order> merchantOrder(Ref ref, String orderId) =>
    ref.watch(merchantOrderRepositoryProvider).watchOrder(orderId);

@Riverpod(keepAlive: true)
AddressRepository addressRepository(Ref ref) =>
    SupabaseAddressRepository(ref.watch(supabaseProvider));

@Riverpod(keepAlive: true)
OrderRepository orderRepository(Ref ref) =>
    FirestoreOrderRepository(ref.watch(firestoreProvider));

/// The signed-in customer's addresses.
///
/// Keyed off the identity rather than passed a uid, so signing out empties it by
/// construction. An address list that outlived a sign-out would show one person another
/// person's home.
@riverpod
Future<List<Address>> myAddresses(Ref ref) async {
  final identity = await ref.watch(currentIdentityProvider.future);
  if (identity == null) return const [];

  final result = await ref.watch(addressRepositoryProvider).addresses(identity.uid);
  return result.valueOrThrow;
}

/// The address an order would go to: the default, or nothing at all.
@riverpod
Future<Address?> chosenAddress(Ref ref) async {
  final identity = await ref.watch(currentIdentityProvider.future);
  if (identity == null) return null;

  final addresses = await ref.watch(myAddressesProvider.future);
  if (addresses.isEmpty) return null;

  final chosenId =
      (await ref.watch(addressRepositoryProvider).defaultAddressId(identity.uid))
          .valueOrNull;

  // A default naming an address that is gone falls back to one that exists, rather than
  // rendering as nothing with no way for the customer to tell why.
  return addresses.where((a) => a.id == chosenId).firstOrNull ?? addresses.first;
}

/// Writing addresses. Kept alive so a command survives the screen that started it.
@Riverpod(keepAlive: true)
class AddressActions extends _$AddressActions {
  @override
  AddressActions build() => this;

  Future<Result<Address>> save(Address address) async {
    final identity = await ref.read(currentIdentityProvider.future);
    // Saving into nowhere would look like it worked and lose the address.
    if (identity == null) return const Result.err(PermissionFailure());

    final result = await ref.read(addressRepositoryProvider).saveAddress(
          identity.uid,
          address,
        );
    _refresh();
    return result;
  }

  Future<Result<void>> remove(String addressId) async {
    final identity = await ref.read(currentIdentityProvider.future);
    if (identity == null) return const Result.err(PermissionFailure());

    final result =
        await ref.read(addressRepositoryProvider).deleteAddress(identity.uid, addressId);
    _refresh();
    return result;
  }

  Future<Result<void>> choose(String addressId) async {
    final identity = await ref.read(currentIdentityProvider.future);
    if (identity == null) return const Result.err(PermissionFailure());

    final result = await ref
        .read(addressRepositoryProvider)
        .setDefaultAddress(identity.uid, addressId);
    _refresh();
    return result;
  }

  void _refresh() {
    ref.invalidate(myAddressesProvider);
    ref.invalidate(chosenAddressProvider);
  }
}

/// One customer's orders, newest first. Live.
///
/// Takes the uid rather than reaching for the session itself. A generator that awaits
/// the identity and then delegates with `yield*` swallows the delegate's error into a
/// loading state, and the screen above spins forever instead of saying "no connection".
/// The caller already knows who is signed in — it has to, to decide between this and the
/// signed-out view.
@riverpod
Stream<List<Order>> ordersFor(Ref ref, String uid) =>
    ref.watch(orderRepositoryProvider).watchMyOrders(uid);

/// One order, live. This is the tracking screen's whole data source: the merchant
/// accepting, the courier setting off, and delivery all arrive as document changes.
@riverpod
Stream<Order> order(Ref ref, String orderId) =>
    ref.watch(orderRepositoryProvider).watchOrder(orderId);

// ------------------------------------------------------------------ config

/// The one path from AdminApp to this phone.
///
/// Overridden in tests and at start-up; the app never constructs it inline, so there is
/// exactly one place a raw remote value becomes a value the app trusts.
@Riverpod(keepAlive: true)
RemoteConfigService remoteConfigService(Ref ref) =>
    RemoteConfigService(FirebaseConfigFetcher(FirebaseRemoteConfig.instance));

/// The values the owner controls from AdminApp.
///
/// Starts on whatever the service last loaded — the compiled-in defaults until a fetch
/// succeeds — so a cold start with no network renders a correct app rather than an
/// unconfigured one, and a failed refresh leaves the previous good values standing.
@Riverpod(keepAlive: true)
class AppConfig extends _$AppConfig {
  @override
  LuqmaConfig build() => ref.watch(remoteConfigServiceProvider).current;

  /// Fetches and republishes. Returns whether the server was reached, so a caller that
  /// wants to tell the user "couldn't reach the server" can, and one that does not can
  /// ignore it — this never throws.
  Future<bool> refresh() async {
    final service = ref.read(remoteConfigServiceProvider);
    final reached = await service.refresh();
    state = service.current;
    return reached;
  }

  /// Applies a source directly. For tests and for the emulator harness.
  @visibleForTesting
  void applySource(ConfigSource source) => state = LuqmaConfig.from(source);
}
