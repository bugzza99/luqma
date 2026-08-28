import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/alarm/alarm.dart';
import 'package:merchant_app/src/alarm/order_alarm.dart';

/// When the sound starts and — the harder half — when it stops.
///
/// The spec calls this the single most important feature in the app. A sound that stops
/// too early is a merchant who does not hear it; a sound that will not stop is a merchant
/// who turns notifications off, and then never hears any of them again.
void main() {
  Order order({String id = 'o1', int number = 101}) => Order(
        id: id,
        cityId: 'edku',
        orderNumber: number,
        customerUid: 'u1',
        customerName: 'أحمد',
        customerPhone: '0100',
        merchantId: 'm1',
        merchantName: 'مطعم',
        zoneId: 'z1',
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'فراخ', unitPrice: 12000, quantity: 1),
        ],
        pricing: const OrderPricing(subtotal: 12000, deliveryFee: 1000, total: 13000),
      );

  late FakeAlarm alarm;
  late FakeMerchantOrderRepository orders;
  late ProviderContainer container;

  ProviderContainer containerWith({List<Order> seed = const []}) {
    alarm = FakeAlarm();
    orders = FakeMerchantOrderRepository(seed: seed);

    final c = ProviderContainer(
      overrides: [
        alarmProvider.overrideWithValue(alarm),
        merchantOrderRepositoryProvider.overrideWithValue(orders),
        authServiceProvider.overrideWithValue(
          FakeAuthService(
            restoring: const LuqmaIdentity(
              uid: 'owner1',
              claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(c.listen(currentIdentityProvider, (_, _) {}).close);
    addTearDown(c.listen(orderAlarmProvider, (_, _) {}).close);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('starting', () {
    test('an order waiting when the app opens rings', () async {
      // A merchant coming back to a phone that was in a pocket has to hear it too.
      container = containerWith(seed: [order()]);
      await settle();

      expect(alarm.isPlaying, isTrue);
    });

    test('nothing waiting is silent', () async {
      container = containerWith();
      await settle();

      expect(alarm.isPlaying, isFalse);
      expect(alarm.starts, 0);
    });

    test('an order arriving later rings', () async {
      container = containerWith();
      await settle();

      await orders.add(order());
      await settle();

      expect(alarm.isPlaying, isTrue);
    });

    // Restarting it would clip the sound back to the beginning of the loop every time
    // a second order landed during a rush.
    test('a second order does not restart it', () async {
      container = containerWith(seed: [order()]);
      await settle();

      await orders.add(order(id: 'o2', number: 102));
      await settle();

      expect(alarm.starts, 1);
      expect(alarm.isPlaying, isTrue);
    });
  });

  group('stopping', () {
    test('the merchant saying they have it stops it', () async {
      container = containerWith(seed: [order()]);
      await settle();

      container.read(orderAlarmProvider.notifier).acknowledge();
      await settle();

      expect(alarm.isPlaying, isFalse);
    });

    // Somebody else answering — the other phone in the shop, or the deadline task —
    // has to silence it too. A sound with no cause is what gets an app muted.
    test('the order being answered elsewhere stops it', () async {
      container = containerWith(seed: [order()]);
      await settle();

      await orders.accept('o1', prepMinutes: 20);
      await settle();

      expect(alarm.isPlaying, isFalse);
    });

    test('one of two answered keeps it ringing for the other', () async {
      container = containerWith(seed: [order(), order(id: 'o2', number: 102)]);
      await settle();

      await orders.accept('o1', prepMinutes: 20);
      await settle();

      expect(alarm.isPlaying, isTrue);
    });
  });

  group('after it has been silenced', () {
    // The whole point. Acknowledging order 101 must not swallow the sound for 102.
    test('a new order rings again', () async {
      container = containerWith(seed: [order()]);
      await settle();
      container.read(orderAlarmProvider.notifier).acknowledge();
      await settle();

      await orders.add(order(id: 'o2', number: 102));
      await settle();

      expect(alarm.isPlaying, isTrue);
      expect(alarm.starts, 2);
    });

    test('the same order still sitting there does not ring again', () async {
      container = containerWith(seed: [order()]);
      await settle();
      container.read(orderAlarmProvider.notifier).acknowledge();
      await settle();

      // The list re-emits for reasons of its own; nothing about the order changed.
      await orders.touch();
      await settle();

      expect(alarm.isPlaying, isFalse);
      expect(alarm.starts, 1);
    });
  });

  group('what the screen can ask', () {
    test('it says whether it is ringing, so the screen can offer to stop it', () async {
      container = containerWith(seed: [order()]);
      await settle();

      expect(container.read(orderAlarmProvider), isTrue);

      container.read(orderAlarmProvider.notifier).acknowledge();
      await settle();

      expect(container.read(orderAlarmProvider), isFalse);
    });
  });
}
