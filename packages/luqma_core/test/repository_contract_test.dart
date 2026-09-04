import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// One write contract for an in-memory fake today and a seeded Supabase repository later.
///
/// The setup, read-back and cleanup stay outside the expectations because the live suite
/// owns credentials and fixtures; the meaning of success stays here so the two
/// implementations cannot quietly prove different things.
void repositoryContract<T>({
  required String name,
  required Future<T> Function() repository,
  required Future<Failure?> Function(T repository) writeExisting,
  required FutureOr<bool> Function(T repository) changed,
  required Future<Failure?> Function(T repository) writeMissing,
  FutureOr<void> Function(T repository)? dispose,
}) {
  test('$name changes an existing target and refuses a missing one', () async {
    final subject = await repository();
    try {
      expect(await writeExisting(subject), isNull);
      expect(await changed(subject), isTrue);
      expect(await writeMissing(subject), isA<NotFoundFailure>());
    } finally {
      await dispose?.call(subject);
    }
  });
}

const _address = Address(id: 'address-1', zoneId: 'zone-1', label: 'البيت');
const _otherAddress =
    Address(id: 'address-2', zoneId: 'zone-1', label: 'الشغل');
const _cuisine = Cuisine(id: 'cuisine-1', cityId: 'edku', name: 'سمك');
const _meal = DailyMeal(
  id: 'meal-1',
  merchantId: 'merchant-1',
  cityId: 'edku',
  name: 'صيادية',
  price: 12000,
  date: '2026-09-05',
  totalQty: 5,
  remainingQty: 5,
  pickupWindowStart: 720,
  pickupWindowEnd: 840,
);
const _zone = Zone(id: 'zone-1', cityId: 'edku', name: 'وسط البلد');
const _landmark = Landmark(
  id: 'landmark-1',
  cityId: 'edku',
  zoneId: 'zone-1',
  name: 'المسجد',
);
const _section = HomeSection(
  key: 'popular',
  type: 'merchantList',
  cityId: 'edku',
);
const _issue = OrderIssue(
  id: 'issue-1',
  orderId: 'order-1',
  customerUid: 'customer-1',
  merchantId: 'merchant-1',
  reason: 'ناقص',
  status: OrderIssue.open,
);
const _media = Media(
  id: 'media-1',
  kind: MediaKind.menuItem,
  url: 'https://example.test/item.jpg',
);
const _item = MenuItem(
  id: 'item-1',
  merchantId: 'merchant-1',
  categoryId: 'category-1',
  name: 'سمك',
  price: 10000,
);
const _merchant = Merchant(
  id: 'merchant-1',
  cityId: 'edku',
  type: MerchantType.restaurant,
  name: 'مطعم',
  zoneId: 'zone-1',
  phone: '01000000000',
);

Order _order(OrderStatus status) => Order(
      id: 'order-1',
      cityId: 'edku',
      orderNumber: 1,
      customerUid: 'customer-1',
      customerName: 'عميل',
      customerPhone: '01000000000',
      merchantId: 'merchant-1',
      merchantName: 'مطعم',
      zoneId: 'zone-1',
      type: OrderType.instant,
      items: const [],
      pricing: const OrderPricing(subtotal: 0, deliveryFee: 0, total: 0),
      status: status,
    );

Promotion _promotion() => Promotion(
      id: 'promotion-1',
      cityId: 'edku',
      merchantId: 'merchant-1',
      channel: PromotionChannel.homeBanner,
      title: 'عرض',
      startAt: DateTime.utc(2026, 10),
      endAt: DateTime.utc(2026, 11),
      requestedBy: 'owner-1',
    );

void main() {
  group('repository write contract', () {
    repositoryContract<FakeAddressRepository>(
      name: 'AddressRepository.saveAddress edit',
      repository: () async => FakeAddressRepository(seed: {
        'customer-1': [_address],
      }),
      writeExisting: (repository) async =>
          (await repository.saveAddress(
            'customer-1',
            _address.copyWith(label: 'البيت الجديد'),
          )).failureOrNull,
      changed: (repository) async =>
          (await repository.addresses('customer-1')).valueOrNull!.single.label ==
          'البيت الجديد',
      writeMissing: (repository) async =>
          (await repository.saveAddress(
            'customer-1',
            _address.copyWith(id: 'missing'),
          )).failureOrNull,
    );

    repositoryContract<FakeAddressRepository>(
      name: 'AddressRepository.deleteAddress',
      repository: () async => FakeAddressRepository(seed: {
        'customer-1': [_address, _otherAddress],
      }),
      writeExisting: (repository) async =>
          (await repository.deleteAddress('customer-1', _address.id)).failureOrNull,
      changed: (repository) async =>
          (await repository.addresses('customer-1')).valueOrNull!.length == 1,
      writeMissing: (repository) async =>
          (await repository.deleteAddress('customer-1', 'missing')).failureOrNull,
    );

    repositoryContract<FakeAddressRepository>(
      name: 'AddressRepository.setDefaultAddress',
      repository: () async => FakeAddressRepository(seed: {
        'customer-1': [_address, _otherAddress],
      }),
      writeExisting: (repository) async =>
          (await repository.setDefaultAddress('customer-1', _otherAddress.id))
              .failureOrNull,
      changed: (repository) async =>
          (await repository.defaultAddressId('customer-1')).valueOrNull ==
          _otherAddress.id,
      writeMissing: (repository) async =>
          (await repository.setDefaultAddress('customer-1', 'missing')).failureOrNull,
    );

    repositoryContract<FakeCuisineRepository>(
      name: 'CuisineRepository.save edit',
      repository: () async => FakeCuisineRepository(seed: [_cuisine]),
      writeExisting: (repository) async =>
          (await repository.save(_cuisine.copyWith(name: 'مشويات'))).failureOrNull,
      changed: (repository) => repository.all.single.name == 'مشويات',
      writeMissing: (repository) async =>
          (await repository.save(_cuisine.copyWith(id: 'missing'))).failureOrNull,
    );

    repositoryContract<FakeCuisineRepository>(
      name: 'CuisineRepository.delete',
      repository: () async => FakeCuisineRepository(seed: [_cuisine]),
      writeExisting: (repository) async =>
          (await repository.delete(_cuisine.id)).failureOrNull,
      changed: (repository) => repository.all.isEmpty,
      writeMissing: (repository) async =>
          (await repository.delete('missing')).failureOrNull,
    );

    repositoryContract<FakeDailyMealRepository>(
      name: 'DailyMealRepository.saveMeal edit',
      repository: () async => FakeDailyMealRepository(seed: [_meal]),
      writeExisting: (repository) async =>
          (await repository.saveMeal(_meal.copyWith(name: 'كفتة'))).failureOrNull,
      changed: (repository) => repository[_meal.id]?.name == 'كفتة',
      writeMissing: (repository) async =>
          (await repository.saveMeal(_meal.copyWith(id: 'missing'))).failureOrNull,
      dispose: (repository) => repository.dispose(),
    );

    repositoryContract<FakeDailyMealRepository>(
      name: 'DailyMealRepository.setStatus',
      repository: () async => FakeDailyMealRepository(seed: [_meal]),
      writeExisting: (repository) async =>
          (await repository.setStatus(_meal.id, DailyMealStatus.published))
              .failureOrNull,
      changed: (repository) =>
          repository[_meal.id]?.status == DailyMealStatus.published,
      writeMissing: (repository) async =>
          (await repository.setStatus('missing', DailyMealStatus.closed))
              .failureOrNull,
      dispose: (repository) => repository.dispose(),
    );

    repositoryContract<FakeGeographyRepository>(
      name: 'GeographyRepository.saveZone edit',
      repository: () async => FakeGeographyRepository(zones: [_zone]),
      writeExisting: (repository) async =>
          (await repository.saveZone(_zone.copyWith(name: 'المعدية'))).failureOrNull,
      changed: (repository) async =>
          (await repository.zones(cityId: 'edku', includeInactive: true))
              .valueOrNull!
              .single
              .name ==
          'المعدية',
      writeMissing: (repository) async =>
          (await repository.saveZone(_zone.copyWith(id: 'missing'))).failureOrNull,
    );

    repositoryContract<FakeGeographyRepository>(
      name: 'GeographyRepository.setZoneActive',
      repository: () async => FakeGeographyRepository(zones: [_zone]),
      writeExisting: (repository) async =>
          (await repository.setZoneActive(_zone.id, false)).failureOrNull,
      changed: (repository) async =>
          (await repository.zones(cityId: 'edku', includeInactive: true))
              .valueOrNull!
              .single
              .isActive ==
          false,
      writeMissing: (repository) async =>
          (await repository.setZoneActive('missing', false)).failureOrNull,
    );

    repositoryContract<FakeGeographyRepository>(
      name: 'GeographyRepository.saveLandmark edit',
      repository: () async => FakeGeographyRepository(landmarks: [_landmark]),
      writeExisting: (repository) async =>
          (await repository.saveLandmark(_landmark.copyWith(name: 'المدرسة')))
              .failureOrNull,
      changed: (repository) async =>
          (await repository.landmarks(cityId: 'edku')).valueOrNull!.single.name ==
          'المدرسة',
      writeMissing: (repository) async =>
          (await repository.saveLandmark(_landmark.copyWith(id: 'missing')))
              .failureOrNull,
    );

    repositoryContract<FakeGeographyRepository>(
      name: 'GeographyRepository.deleteLandmark',
      repository: () async => FakeGeographyRepository(landmarks: [_landmark]),
      writeExisting: (repository) async =>
          (await repository.deleteLandmark(_landmark.id)).failureOrNull,
      changed: (repository) async =>
          (await repository.landmarks(cityId: 'edku')).valueOrNull!.isEmpty,
      writeMissing: (repository) async =>
          (await repository.deleteLandmark('missing')).failureOrNull,
    );

    repositoryContract<FakeHomeSectionRepository>(
      name: 'HomeSectionRepository.setVisible',
      repository: () async => FakeHomeSectionRepository(seed: [_section]),
      writeExisting: (repository) async =>
          (await repository.setVisible(_section.key, false, cityId: 'edku'))
              .failureOrNull,
      changed: (repository) => repository[_section.key]?.isVisible == false,
      writeMissing: (repository) async =>
          (await repository.setVisible('missing', false, cityId: 'edku'))
              .failureOrNull,
      dispose: (repository) => repository.dispose(),
    );

    repositoryContract<FakeIssueRepository>(
      name: 'IssueRepository.close',
      repository: () async => FakeIssueRepository(seed: [_issue]),
      writeExisting: (repository) async =>
          (await repository.close(_issue.id, adminNote: 'اتصلنا')).failureOrNull,
      changed: (repository) async =>
          (await repository.watchIssues().first).single.status == OrderIssue.closed,
      writeMissing: (repository) async =>
          (await repository.close('missing')).failureOrNull,
    );

    repositoryContract<FakeMediaRepository>(
      name: 'MediaRepository.setStatus',
      repository: () async => FakeMediaRepository(seed: [_media]),
      writeExisting: (repository) async =>
          (await repository.setStatus(_media.id, MediaStatus.approved))
              .failureOrNull,
      changed: (repository) async =>
          (await repository.get(_media.id)).valueOrNull?.status == MediaStatus.approved,
      writeMissing: (repository) async =>
          (await repository.setStatus('missing', MediaStatus.rejected)).failureOrNull,
    );

    repositoryContract<FakeMenuRepository>(
      name: 'MenuRepository.saveItem edit',
      repository: () async => FakeMenuRepository(items: [_item]),
      writeExisting: (repository) async =>
          (await repository.saveItem(_item.copyWith(name: 'جمبري'))).failureOrNull,
      changed: (repository) async =>
          (await repository.watchItems('merchant-1').first).single.name == 'جمبري',
      writeMissing: (repository) async =>
          (await repository.saveItem(_item.copyWith(id: 'missing'))).failureOrNull,
    );

    repositoryContract<FakeMenuRepository>(
      name: 'MenuRepository.deleteItem',
      repository: () async => FakeMenuRepository(items: [_item]),
      writeExisting: (repository) async =>
          (await repository.deleteItem(_item.id)).failureOrNull,
      changed: (repository) async =>
          (await repository.watchItems('merchant-1').first).isEmpty,
      writeMissing: (repository) async =>
          (await repository.deleteItem('missing')).failureOrNull,
    );

    repositoryContract<FakeMerchantRepository>(
      name: 'MerchantRepository.setPausedUntil',
      repository: () async => FakeMerchantRepository(seed: [_merchant]),
      writeExisting: (repository) async =>
          (await repository.setPausedUntil(
            _merchant.id,
            DateTime.utc(2026, 9, 5, 18),
          )).failureOrNull,
      changed: (repository) => repository.all.single.pausedUntil != null,
      writeMissing: (repository) async =>
          (await repository.setPausedUntil('missing', null)).failureOrNull,
    );

    repositoryContract<FakeMerchantRepository>(
      name: 'MerchantRepository.saveMerchant edit',
      repository: () async => FakeMerchantRepository(seed: [_merchant]),
      writeExisting: (repository) async =>
          (await repository.saveMerchant(_merchant.copyWith(name: 'مطعم جديد')))
              .failureOrNull,
      changed: (repository) => repository.all.single.name == 'مطعم جديد',
      writeMissing: (repository) async =>
          (await repository.saveMerchant(_merchant.copyWith(id: 'missing')))
              .failureOrNull,
    );

    repositoryContract<FakeMerchantRepository>(
      name: 'MerchantRepository.setStatus',
      repository: () async => FakeMerchantRepository(seed: [_merchant]),
      writeExisting: (repository) async =>
          (await repository.setStatus(_merchant.id, MerchantStatus.approved))
              .failureOrNull,
      changed: (repository) =>
          repository.all.single.status == MerchantStatus.approved,
      writeMissing: (repository) async =>
          (await repository.setStatus('missing', MerchantStatus.suspended))
              .failureOrNull,
    );

    repositoryContract<FakeMerchantRepository>(
      name: 'MerchantRepository.deleteMerchant',
      repository: () async => FakeMerchantRepository(seed: [_merchant]),
      writeExisting: (repository) async =>
          (await repository.deleteMerchant(_merchant.id)).failureOrNull,
      changed: (repository) => repository.all.isEmpty,
      writeMissing: (repository) async =>
          (await repository.deleteMerchant('missing')).failureOrNull,
    );

    repositoryContract<FakeOrderRepository>(
      name: 'OrderRepository.raiseIssue',
      repository: () async => FakeOrderRepository(seed: [_order(OrderStatus.placed)]),
      writeExisting: (repository) async =>
          (await repository.raiseIssue(
            orderId: 'order-1',
            customerUid: 'customer-1',
            merchantId: 'merchant-1',
            reason: 'ناقص',
          )).failureOrNull,
      changed: (repository) => repository.issues.length == 1,
      writeMissing: (repository) async =>
          (await repository.raiseIssue(
            orderId: 'missing',
            customerUid: 'customer-1',
            merchantId: 'merchant-1',
            reason: 'ناقص',
          )).failureOrNull,
    );

    _merchantOrderContracts();
    _courierOrderContracts();
    _promotionContracts();
    _profileContracts();
  });
}

void _merchantOrderContracts() {
  repositoryContract<FakeMerchantOrderRepository>(
    name: 'MerchantOrderRepository.accept',
    repository: () async =>
        FakeMerchantOrderRepository(seed: [_order(OrderStatus.placed)]),
    writeExisting: (repository) async =>
        (await repository.accept('order-1', prepMinutes: 20)).failureOrNull,
    changed: (repository) => repository['order-1']?.status == OrderStatus.accepted,
    writeMissing: (repository) async =>
        (await repository.accept('missing', prepMinutes: 20)).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakeMerchantOrderRepository>(
    name: 'MerchantOrderRepository.reject',
    repository: () async =>
        FakeMerchantOrderRepository(seed: [_order(OrderStatus.placed)]),
    writeExisting: (repository) async =>
        (await repository.reject('order-1', reason: 'مغلق')).failureOrNull,
    changed: (repository) => repository['order-1']?.status == OrderStatus.cancelled,
    writeMissing: (repository) async =>
        (await repository.reject('missing', reason: 'مغلق')).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakeMerchantOrderRepository>(
    name: 'MerchantOrderRepository.advance',
    repository: () async =>
        FakeMerchantOrderRepository(seed: [_order(OrderStatus.accepted)]),
    writeExisting: (repository) async =>
        (await repository.advance('order-1', to: OrderStatus.preparing)).failureOrNull,
    changed: (repository) => repository['order-1']?.status == OrderStatus.preparing,
    writeMissing: (repository) async =>
        (await repository.advance('missing', to: OrderStatus.preparing)).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );
}

void _courierOrderContracts() {
  repositoryContract<FakeCourierOrderRepository>(
    name: 'CourierOrderRepository.markOnTheWay',
    repository: () async =>
        FakeCourierOrderRepository(seed: [_order(OrderStatus.preparing)]),
    writeExisting: (repository) async =>
        (await repository.markOnTheWay('order-1', courierUid: 'courier-1'))
            .failureOrNull,
    changed: (repository) =>
        repository['order-1']?.status == OrderStatus.outForDelivery,
    writeMissing: (repository) async =>
        (await repository.markOnTheWay('missing', courierUid: 'courier-1'))
            .failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakeCourierOrderRepository>(
    name: 'CourierOrderRepository.markDelivered',
    repository: () async =>
        FakeCourierOrderRepository(seed: [_order(OrderStatus.outForDelivery)]),
    writeExisting: (repository) async =>
        (await repository.markDelivered('order-1')).failureOrNull,
    changed: (repository) => repository['order-1']?.status == OrderStatus.delivered,
    writeMissing: (repository) async =>
        (await repository.markDelivered('missing')).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakeCourierOrderRepository>(
    name: 'CourierOrderRepository.markFailed',
    repository: () async =>
        FakeCourierOrderRepository(seed: [_order(OrderStatus.outForDelivery)]),
    writeExisting: (repository) async =>
        (await repository.markFailed('order-1', reason: 'العنوان غلط'))
            .failureOrNull,
    changed: (repository) => repository['order-1']?.status == OrderStatus.cancelled,
    writeMissing: (repository) async =>
        (await repository.markFailed('missing', reason: 'العنوان غلط'))
            .failureOrNull,
    dispose: (repository) => repository.dispose(),
  );
}

void _promotionContracts() {
  FakePromotionRepository repository() => FakePromotionRepository(
        seed: [_promotion()],
        clock: () => DateTime.utc(2026, 9),
      );

  repositoryContract<FakePromotionRepository>(
    name: 'PromotionRepository.editRequest',
    repository: () async => repository(),
    writeExisting: (repository) async =>
        (await repository.editRequest(_promotion().copyWith(title: 'عرض جديد')))
            .failureOrNull,
    changed: (repository) => repository['promotion-1']?.title == 'عرض جديد',
    writeMissing: (repository) async =>
        (await repository.editRequest(_promotion().copyWith(id: 'missing')))
            .failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakePromotionRepository>(
    name: 'PromotionRepository.reschedule',
    repository: () async => repository(),
    writeExisting: (repository) async =>
        (await repository.reschedule(
          'promotion-1',
          startAt: DateTime.utc(2026, 12),
          endAt: DateTime.utc(2027),
        )).failureOrNull,
    changed: (repository) =>
        repository['promotion-1']?.startAt == DateTime.utc(2026, 12),
    writeMissing: (repository) async =>
        (await repository.reschedule(
          'missing',
          startAt: DateTime.utc(2026, 12),
          endAt: DateTime.utc(2027),
        )).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakePromotionRepository>(
    name: 'PromotionRepository.approve',
    repository: () async => repository(),
    writeExisting: (repository) async =>
        (await repository.approve('promotion-1', approvedBy: 'admin-1'))
            .failureOrNull,
    changed: (repository) =>
        repository['promotion-1']?.status == PromotionStatus.approved,
    writeMissing: (repository) async =>
        (await repository.approve('missing', approvedBy: 'admin-1')).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );

  repositoryContract<FakePromotionRepository>(
    name: 'PromotionRepository.reject',
    repository: () async => repository(),
    writeExisting: (repository) async =>
        (await repository.reject(
          'promotion-1',
          reason: 'الصورة غير واضحة',
          by: 'admin-1',
        )).failureOrNull,
    changed: (repository) =>
        repository['promotion-1']?.status == PromotionStatus.rejected,
    writeMissing: (repository) async =>
        (await repository.reject(
          'missing',
          reason: 'الصورة غير واضحة',
          by: 'admin-1',
        )).failureOrNull,
    dispose: (repository) => repository.dispose(),
  );
}

void _profileContracts() {
  repositoryContract<FakeProfileRepository>(
    name: 'ProfileRepository.savePhone',
    repository: () async => FakeProfileRepository(accountId: 'customer-1'),
    writeExisting: (repository) async =>
        (await repository.savePhone(
          uid: 'customer-1',
          phone: '01012345678',
        )).failureOrNull,
    changed: (repository) => repository.phones['customer-1'] == '01012345678',
    writeMissing: (repository) async =>
        (await repository.savePhone(uid: 'missing', phone: '01012345678'))
            .failureOrNull,
  );

  repositoryContract<FakeProfileRepository>(
    name: 'ProfileRepository.setMarketingPush',
    repository: () async => FakeProfileRepository(accountId: 'customer-1'),
    writeExisting: (repository) async =>
        (await repository.setMarketingPush(uid: 'customer-1', on: false))
            .failureOrNull,
    changed: (repository) => repository.marketing['customer-1'] == false,
    writeMissing: (repository) async =>
        (await repository.setMarketingPush(uid: 'missing', on: false)).failureOrNull,
  );
}
