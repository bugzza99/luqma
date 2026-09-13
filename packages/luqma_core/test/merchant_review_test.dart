import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  const order = Order(id: 'o', cityId: 'edku', orderNumber: 1,
    customerName: 'Customer', customerPhone: '01012345678', merchantId: 'shop',
    merchantName: 'Shop', zoneId: 'z', type: OrderType.instant, items: [],
    pricing: OrderPricing(subtotal: 10000, deliveryFee: 1000, total: 11000),
    status: OrderStatus.delivered, courierUid: 'rider');
  test('a roster fake cannot invent an account for an unknown phone', () async {
    final repo = FakeCourierRosterRepository();
    addTearDown(repo.dispose);
    final result = await repo.attachCourier(merchantId: 'shop', phone: '01012345678');
    expect(result.failureOrNull, isA<NotFoundFailure>());
    expect(repo.all, isEmpty);
  });
  test('merchant screens use palette tokens for every colour', () {
    final files = Directory('../../apps/merchant_app/lib/src')
        .listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final literal = RegExp(r'\bColors\.|\bColor\s*\(|0x[0-9a-fA-F]{8}');
    expect(files.where((f) => literal.hasMatch(f.readAsStringSync()))
        .map((f) => f.path).toList(), isEmpty);
  });
  test('the application fake rejects a pending review like the RPC', () async {
    final repo = FakeStaffApplicationRepository();
    addTearDown(repo.dispose);
    await repo.apply(kind: StaffApplicationKind.courier, name: 'Rider', phone: '01012345678');
    final result = await repo.review(repo.all.single.id, status: StaffApplicationStatus.pending);
    expect(result.isOk, isFalse);
    expect(repo.all.single.reviewedAt, isNull);
  });
  test('the application fake enforces the database field limits', () async {
    final repo = FakeStaffApplicationRepository();
    addTearDown(repo.dispose);
    for (final input in [
      (name: 'x', phone: '01012345678', note: ''),
      (name: 'Rider', phone: '12345', note: ''),
      (name: 'Rider', phone: '01012345678', note: 'x' * 501),
    ]) {
      expect((await repo.apply(kind: StaffApplicationKind.courier,
        name: input.name, phone: input.phone, note: input.note)).isOk, isFalse);
    }
    expect(repo.all, isEmpty);
  });
  test('sales use Cairo calendar days even when given UTC instants', () {
    final instant = DateTime.utc(2026, 9, 12, 22);
    final sales = MerchantSales.of([order.copyWith(placedAt: instant)],
      merchantId: 'shop', days: 1, now: () => instant);
    expect(sales.byDay.single.day, '2026-09-13');
    expect(sales.byDay.single.sales, 10000);
  });
  test('a courier fake without an identity cannot count every riders cash', () async {
    final repo = FakeCourierOrderRepository(seed: [order]);
    addTearDown(repo.dispose);
    expect((await repo.daySummary()).valueOrThrow.cash, 0);
  });
  test('a return counts on the day it happened, not the day it was ordered', () async {
    final now = DateTime.utc(2026, 9, 13, 10);
    final repo = FakeCourierOrderRepository(courierUid: 'rider', now: () => now,
      seed: [order.copyWith(status: OrderStatus.outForDelivery,
        placedAt: now.subtract(const Duration(days: 1)))]);
    addTearDown(repo.dispose);
    expect((await repo.markFailed('o', reason: 'No answer')).isOk, isTrue);
    expect((await repo.daySummary()).valueOrThrow.returned, 1);
  });
  test('sales preserve the frozen name groups of a renamed dish like SQL', () {
    final now = DateTime.utc(2026, 9, 13, 10);
    final sales = MerchantSales.of([
      for (final name in ['Old name', 'New name']) order.copyWith(placedAt: now,
        items: [OrderLine(itemId: 'dish', name: name, quantity: 2, unitPrice: 5000)]),
    ], merchantId: 'shop', now: () => now);
    expect(sales.topItems.map((i) => (i.name, i.quantity)).toList(),
      [('New name', 2), ('Old name', 2)]);
  });
}
