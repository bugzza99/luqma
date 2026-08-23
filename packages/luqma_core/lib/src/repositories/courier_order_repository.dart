import 'dart:async';

// `Order` here would be Firestore's index-definition enum, not ours.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/order.dart';
import '../result.dart';

/// Orders as the person carrying them sees them.
///
/// A third view of the same collection, because a courier asks a third set of questions:
/// what have I got to take out, where does it go, and how much cash do I collect. The
/// transitions barely overlap with the merchant's, which is why this is its own
/// interface rather than more methods on theirs.
abstract interface class CourierOrderRepository {
  /// For a courier who belongs to one merchant. Live.
  Stream<List<Order>> watchForMerchant(String merchantId);

  /// For Luqma's own courier: home kitchens, and merchants that do not deliver. Live.
  Stream<List<Order>> watchForPlatform(String cityId);

  Stream<Order> watchOrder(String orderId);

  /// Takes the order out, and puts this courier's name on it.
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid});

  Future<Result<void>> markDelivered(String orderId);

  /// Nobody at the door, wrong address, order refused. Needs a reason: it is what the
  /// admin reads, and what eventually blocks a customer who does this repeatedly.
  Future<Result<void>> markFailed(String orderId, {required String reason});
}

/// What a courier has on their hands: ready to collect, or already out.
const _onTheRun = [OrderStatus.preparing, OrderStatus.outForDelivery];

class FirestoreCourierOrderRepository implements CourierOrderRepository {
  FirestoreCourierOrderRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _firestore.collection('orders');

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) => _sorted(
        _orders
            .where('merchantId', isEqualTo: merchantId)
            .where('status', whereIn: [for (final s in _onTheRun) s.name]),
      );

  @override
  Stream<List<Order>> watchForPlatform(String cityId) => _sorted(
        _orders
            .where('cityId', isEqualTo: cityId)
            // Frozen on the order, not looked up on the merchant: a merchant who stops
            // delivering their own orders next week must not change who was answerable
            // for last week's.
            .where('deliveryBy', isEqualTo: DeliveryBy.platform.name)
            .where('status', whereIn: [for (final s in _onTheRun) s.name]),
      );

  Stream<List<Order>> _sorted(Query<Map<String, dynamic>> query) {
    return query.snapshots().map(
          (snapshot) => snapshot.docs.map(_toOrder).toList()
            // Oldest first: the order that has been sitting longest is the one whose
            // food is going cold.
            ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
        );
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) throw const NotFoundFailure();
      return _toOrder(doc);
    });
  }

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) {
    return _move(orderId, OrderStatus.outForDelivery, (_) => {
          // Written in the same breath as the status. It is what keeps a platform
          // courier able to read the order afterwards, and what tells a customer who
          // is holding their food.
          'courierUid': courierUid,
        });
  }

  @override
  Future<Result<void>> markDelivered(String orderId) {
    return _move(orderId, OrderStatus.delivered, (_) => {
          // What the revenue engine and every report key off.
          'deliveredAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) {
    final trimmed = reason.trim();
    return _move(orderId, OrderStatus.cancelled, (_) {
      if (trimmed.isEmpty) throw const ConflictFailure();
      return {
        'cancelReason': trimmed,
        'cancelledBy': OrderActor.courier.name,
      };
    });
  }

  Future<Result<void>> _move(
    String orderId,
    OrderStatus to,
    Map<String, Object?> Function(Order order) extra,
  ) {
    return Result.guard(() async {
      final doc = await _orders.doc(orderId).get();
      if (!doc.exists) throw const NotFoundFailure();

      final order = _toOrder(doc);
      // Asked here as well as in the rules, so a screen can hide a button rather than
      // offer an action about to be refused. Marking an order delivered before it left
      // is how cash goes missing.
      if (!order.status.canMoveTo(to, by: OrderActor.courier)) {
        throw const ConflictFailure();
      }

      await _orders.doc(orderId).update({
        'status': to.name,
        ...extra(order),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Order _toOrder(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromJson({...doc.data()!, 'id': doc.id});
}

/// In-memory deliveries, for tests and for building the courier screens without a
/// backend. Re-applies the same transition rules as the real one.
class FakeCourierOrderRepository implements CourierOrderRepository {
  FakeCourierOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Everything held right now. A widget test runs on a fake clock and cannot await one
  /// of the streams below, so this is what lets it assert on what a screen wrote.
  List<Order> get all => List.unmodifiable(_orders.values);

  Order? operator [](String orderId) => _orders[orderId];

  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
        listener.add(read());
        final sub = _changed.stream.listen((_) => listener.add(read()));
        listener.onCancel = sub.cancel;
      });

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _orders.values
          .where((o) => o.merchantId == merchantId && _onTheRun.contains(o.status))
          .toList()
        ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<Order>> watchForPlatform(String cityId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _orders.values
          .where((o) =>
              o.cityId == cityId &&
              o.deliveryBy == DeliveryBy.platform &&
              _onTheRun.contains(o.status))
          .toList()
        ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    if (failure != null) return Stream.error(failure!);
    if (!_orders.containsKey(orderId)) {
      return Stream.error(const NotFoundFailure());
    }
    return _live(() => _orders[orderId]!);
  }

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) =>
      _move(orderId, OrderStatus.outForDelivery,
          (o) => o.copyWith(courierUid: courierUid));

  @override
  Future<Result<void>> markDelivered(String orderId) => _move(
        orderId,
        OrderStatus.delivered,
        (o) => o.copyWith(deliveredAt: DateTime.now()),
      );

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) async {
    if (reason.trim().isEmpty) return const Result.err(ConflictFailure());
    return _move(
      orderId,
      OrderStatus.cancelled,
      (o) => o.copyWith(
        cancelReason: reason.trim(),
        cancelledBy: OrderActor.courier,
      ),
    );
  }

  Future<Result<void>> _move(
    String orderId,
    OrderStatus to,
    Order Function(Order order) apply,
  ) async {
    if (failure != null) return Result.err(failure!);

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    if (!order.status.canMoveTo(to, by: OrderActor.courier)) {
      return const Result.err(ConflictFailure());
    }

    _orders[orderId] = apply(order).copyWith(status: to);
    _notify();
    return const Result.ok(null);
  }
}
