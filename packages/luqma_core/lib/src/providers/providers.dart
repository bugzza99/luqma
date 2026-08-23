import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/luqma_config.dart';
import '../config/remote_config_service.dart';
import '../models/geography.dart';
import '../models/home_section.dart';
import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../repositories/geography_repository.dart';
import '../repositories/home_section_repository.dart';
import '../repositories/media_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/merchant_repository.dart';

part 'providers.g.dart';

/// The Firestore instance. Overridden in tests and in the emulator harness, which is why
/// it is a provider rather than a static reference reached for from wherever.
@Riverpod(keepAlive: true)
FirebaseFirestore firestore(Ref ref) => FirebaseFirestore.instance;

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
    FirestoreGeographyRepository(ref.watch(firestoreProvider));

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
