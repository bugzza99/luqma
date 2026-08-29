import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Merchants, against a real Postgres with realtime on.
///
/// The port of `test/merchant_repository_test.dart` and the admin half of
/// `test/merchant_admin_test.dart`, which ran against an in-memory Firestore. What only
/// a real database can prove lives here too: that an edit cannot zero a wallet, that
/// categories and served zones survive in their own tables across a merchant edit, and
/// that an approval reaches an already-open customer watch.
void main() {
  late LiveDatabase live;
  late SupabaseMerchantRepository repository;
  late SupabaseMerchantRepository adminRepository;
  late SupabaseClient adminDb;
  late String cityId;
  late String zoneId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseMerchantRepository(live.client);
    adminDb = await live.openAsAdmin();
    adminRepository = SupabaseMerchantRepository(adminDb);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  Merchant merchant(
    String name, {
    MerchantStatus status = MerchantStatus.approved,
    int prepMinutes = 30,
  }) =>
      Merchant(
        id: '',
        cityId: cityId,
        type: MerchantType.restaurant,
        name: name,
        zoneId: zoneId,
        phone: '01000000000',
        status: status,
        prepMinutes: prepMinutes,
      );

  Future<String> saveRaw(
    String name, {
    MerchantStatus status = MerchantStatus.approved,
  }) async =>
      await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': name,
        'zone_id': zoneId,
        'phone': '01000000000',
        'status': status.name,
      }).select().single().then((row) => row['id'] as String);

  group('the customer list', () {
    test('returns approved merchants in the requested city', () async {
      await adminRepository.saveMerchant(merchant('أ'));
      await adminRepository.saveMerchant(merchant('ب'));

      final merchants = await repository.watchMerchants(cityId: cityId).first;

      expect(merchants.map((m) => m.name), containsAll(['أ', 'ب']));
    });

    // The approval queue is the entire reason pending exists; customers never see it.
    test('hides merchants awaiting approval from customers', () async {
      await adminRepository.saveMerchant(merchant('معتمد'));
      await adminRepository.saveMerchant(
        merchant('منتظر', status: MerchantStatus.pending),
      );

      final merchants = await repository.watchMerchants(cityId: cityId).first;

      expect(merchants.map((m) => m.name), ['معتمد']);
    });

    test('hides suspended merchants', () async {
      await adminRepository.saveMerchant(merchant('شغال'));
      await adminRepository.saveMerchant(
        merchant('موقوف', status: MerchantStatus.suspended),
      );

      final merchants = await repository.watchMerchants(cityId: cityId).first;

      expect(merchants.map((m) => m.name), ['شغال']);
    });

    // The model carries cityId everywhere precisely so this filter exists from day one
    // and a second city is a data change rather than a migration.
    test('does not leak merchants from another city', () async {
      final other = await live.makeCity();
      final otherZone = await live.client
          .from('zones')
          .insert({'city_id': other, 'name': 'جنوب'})
          .select()
          .single()
          .then((row) => row['id'] as String);
      await adminRepository.saveMerchant(
        merchant('برّه').copyWith(cityId: other, zoneId: otherZone),
      );
      await adminRepository.saveMerchant(merchant('هنا'));

      final merchants = await repository.watchMerchants(cityId: cityId).first;

      expect(merchants.map((m) => m.name), ['هنا']);
      addTearDown(() => live.dropCity(other));
    });
  });

  group('the admin list', () {
    test('includes pending and suspended, so they can be brought back', () async {
      await adminRepository.saveMerchant(
        merchant('موقوف', status: MerchantStatus.suspended),
      );
      await adminRepository.saveMerchant(
        merchant('منتظر', status: MerchantStatus.pending),
      );
      await adminRepository.saveMerchant(merchant('معتمد'));

      final all = await adminRepository.watchAllMerchants(cityId: cityId).first;

      expect(all.map((m) => m.name), containsAll(['موقوف', 'منتظر', 'معتمد']));
    });

    // Pending first: the queue is the reason to open this screen, and a merchant waiting
    // on approval is waiting on a person, not on a system.
    test('puts the ones needing a decision at the top', () async {
      await adminRepository.saveMerchant(merchant('معتمد'));
      await adminRepository.saveMerchant(
        merchant('منتظر', status: MerchantStatus.pending),
      );
      await adminRepository.saveMerchant(
        merchant('موقوف', status: MerchantStatus.suspended),
      );

      final all = await adminRepository.watchAllMerchants(cityId: cityId).first;

      expect(all.first.name, 'منتظر');
    });
  });

  group('saving', () {
    test('a new merchant gets an id and comes back', () async {
      final saved = await adminRepository.saveMerchant(merchant('الشاطئ'));

      expect(saved.valueOrNull?.id, isNotEmpty);
      expect(saved.valueOrNull?.name, 'الشاطئ');
    });

    test('editing does not create a second one', () async {
      final created = (await adminRepository.saveMerchant(merchant('قديم'))).valueOrNull!;

      await adminRepository.saveMerchant(created.copyWith(name: 'الاسم الجديد'));

      final all = await adminRepository.watchAllMerchants(cityId: cityId).first;
      expect(all, hasLength(1));
      expect(all.single.name, 'الاسم الجديد');
    });

    // The failure mode this guards against is an admin form built from a stale load:
    // the server moved the wallet during the day, the form saves a zero, and a prepaid
    // merchant keeps selling on air. Firestore's merged set had the same hazard.
    test('an edit cannot touch the wallet or the ratings', () async {
      final id = await saveRaw('مطعم');
      await adminDb
          .from('merchants')
          .update({'wallet_balance': 5000, 'rating_avg': 4.5, 'rating_count': 12})
          .eq('id', id);

      final loaded = (await repository.getMerchant(id)).valueOrNull!;
      await adminRepository.saveMerchant(loaded.copyWith(name: 'مطعم جديد'));

      final read = (await repository.getMerchant(id)).valueOrNull!;
      expect(read.name, 'مطعم جديد');
      expect(read.walletBalance, 5000);
      expect(read.ratingAvg, 4.5);
      expect(read.ratingCount, 12);
    });

    // Categories live in their own table now; they are read back through it and an edit
    // to the merchant neither drops nor rewrites them.
    test('menu categories survive in their own table across an edit', () async {
      final created =
          (await adminRepository.saveMerchant(merchant('مطعم'))).valueOrNull!;
      await live.client.from('menu_categories').insert({
        'merchant_id': created.id,
        'name': 'مشويات',
        'sort_order': 0,
      });

      await adminRepository.saveMerchant(created.copyWith(phone: '01111111111'));

      final read = (await repository.getMerchant(created.id)).valueOrNull!;
      expect(read.menuCategories.single.name, 'مشويات');
      expect(read.phone, '01111111111');
    });

    // Served zones are queried from both ends — checkout asks whether a merchant will
    // deliver to a zone — so what is saved must be what comes back.
    test('served zones ride along on reads', () async {
      final otherZone = await live.client
          .from('zones')
          .insert({'city_id': cityId, 'name': 'جنوب'})
          .select()
          .single()
          .then((row) => row['id'] as String);
      final created =
          (await adminRepository.saveMerchant(merchant('مطعم'))).valueOrNull!;
      await live.client.from('merchant_served_zones').insert({
        'merchant_id': created.id,
        'zone_id': otherZone,
      });

      final read = (await repository.getMerchant(created.id)).valueOrNull!;

      expect(read.servedZones, [otherZone]);
    });

    // Opening hours arrive as jsonb whose inner keys the app itself wrote, and a wrong
    // mapping here reads as a shop that never opens.
    test('opening hours survive the round trip', () async {
      const window = OpeningWindow(
          weekday: DateTime.tuesday, openMinute: 600, closeMinute: 1380);
      final created = (await adminRepository.saveMerchant(
        merchant('مطعم').copyWith(openingHours: const [window]),
      )).valueOrNull!;

      final read = (await repository.getMerchant(created.id)).valueOrNull!;

      expect(read.openingHours.single.weekday, DateTime.tuesday);
      expect(read.openingHours.single.openMinute, 600);
      expect(read.openingHours.single.closeMinute, 1380);
    });

    // An empty media id means "none"; the uuid column would refuse the empty string.
    test('empty media and owner ids save as none', () async {
      final created = (await adminRepository.saveMerchant(
        merchant('مطعم').copyWith(logoMediaId: '', ownerUid: ''),
      )).valueOrNull!;

      expect(created.logoMediaId, isNull);
      expect(created.ownerUid, isNull);
    });
  });

  group('getMerchant', () {
    // If the timestamp mapping is wrong the failure is a merchant that never reopens
    // after a busy pause — invisible at rush hour with nobody able to say why.
    test('a pause comes back as the same moment it was set', () async {
      final until = DateTime(2026, 8, 18, 14, 30);
      final created = (await adminRepository.saveMerchant(
        merchant('مطعم').copyWith(pausedUntil: until),
      )).valueOrNull!;

      final read = (await repository.getMerchant(created.id)).valueOrNull!;

      expect(read.pausedUntil, until);
    });

    test('a missing merchant is a not-found failure, not an empty merchant', () async {
      final result =
          await repository.getMerchant('00000000-0000-0000-0000-000000000000');

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('pause', () {
    test('setting a pause is visible on the next read', () async {
      final created = (await adminRepository.saveMerchant(merchant('مطعم'))).valueOrNull!;
      final until = DateTime(2026, 8, 18, 15, 0);

      await repository.setPausedUntil(created.id, until);

      expect((await repository.getMerchant(created.id)).valueOrNull?.pausedUntil, until);
    });

    test('clearing a pause removes it', () async {
      final created = (await adminRepository.saveMerchant(
        merchant('مطعم').copyWith(pausedUntil: DateTime(2026, 8, 18, 15)),
      )).valueOrNull!;

      await repository.setPausedUntil(created.id, null);

      expect((await repository.getMerchant(created.id)).valueOrNull?.pausedUntil, isNull);
    });
  });

  group('approving and suspending', () {
    // And the realtime half of it: the approval happens in AdminApp, but the list that
    // must move is on phones already open.
    test('approving reaches an already-open customer watch', () async {
      final created = (await adminRepository.saveMerchant(
        merchant('مطعم', status: MerchantStatus.pending),
      )).valueOrNull!;

      final emissions = <List<Merchant>>[];
      repository.watchMerchants(cityId: cityId).listen(emissions.add);
      await waitFor(() => emissions.isNotEmpty,
          because: 'the customer watch never produced its first emission');
      expect(emissions.first, isEmpty,
          reason: 'a pending merchant must not reach customers');

      await adminRepository.setStatus(created.id, MerchantStatus.approved);

      await waitFor(
        () => emissions.any((e) => e.any((m) => m.id == created.id)),
        because: 'the approval never reached the open watch',
        timeout: const Duration(seconds: 15),
      );
    });

    test('suspending takes them back out of the customer watch', () async {
      final created = (await adminRepository.saveMerchant(merchant('مطعم'))).valueOrNull!;

      final emissions = <List<Merchant>>[];
      repository.watchMerchants(cityId: cityId).listen(emissions.add);
      await waitFor(() => emissions.isNotEmpty,
          because: 'the customer watch never produced its first emission');

      await adminRepository.setStatus(created.id, MerchantStatus.suspended);

      // The row that left the result is the hard case for hand-merged patches — exactly
      // why the helper refetches rather than merges.
      await waitFor(
        () => emissions.any((e) => e.every((m) => m.id != created.id)),
        because: 'the suspension never reached the open watch',
        timeout: const Duration(seconds: 15),
      );
    });
  });

  group('the fake repository behaves like the real one', () {
    test('it filters by status and city the same way', () async {
      final fake = FakeMerchantRepository(seed: [
        // Distinct ids: the fake keys its map by id, and two blank ids are one entry.
        merchant('أ').copyWith(id: 'a'),
        merchant('ب', status: MerchantStatus.pending).copyWith(id: 'b'),
      ]);

      final merchants = await fake.watchMerchants(cityId: cityId).first;

      expect(merchants.map((m) => m.name), ['أ']);
    });

    test('it reports a missing merchant as not found', () async {
      final fake = FakeMerchantRepository();
      expect((await fake.getMerchant('nobody')).failureOrNull, isA<NotFoundFailure>());
    });

    // A fake that always succeeds only ever tests the happy path, and the failure
    // branches are exactly the ones that reach a customer standing in the street.
    test('it can be told to fail, so error paths are testable', () async {
      final fake = FakeMerchantRepository(failure: const OfflineFailure());
      expect((await fake.getMerchant('a')).failureOrNull, isA<OfflineFailure>());
    });
  });

  // `_row` did not carry `prep_minutes`, so the column kept its default of 30 whatever
  // anybody set. The customer reads the consequence on every merchant card in the city —
  // "٣٠ دقيقة تقريباً" under every shop, including the one that takes an hour. Its own
  // fake had no opinion about it, so nothing in the suite noticed.
  group('how long the food takes', () {
    test('the number that was saved is the number that comes back', () async {
      final saved =
          await adminRepository.saveMerchant(merchant('بطيء', prepMinutes: 55));

      final read = await repository.getMerchant(saved.valueOrThrow.id);

      expect(read.valueOrThrow.prepMinutes, 55);
    });

    test('and an edit moves it', () async {
      final saved =
          (await adminRepository.saveMerchant(merchant('سريع'))).valueOrThrow;

      await adminRepository.saveMerchant(saved.copyWith(prepMinutes: 15));
      final read = await repository.getMerchant(saved.id);

      expect(read.valueOrThrow.prepMinutes, 15);
    });
  });
}
