import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
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
class SupabaseCourierOrderRepository implements CourierOrderRepository {
  SupabaseCourierOrderRepository(this._db);

  final SupabaseClient _db;

  Order _toOrder(Map<String, dynamic> row) {
    final model = ColumnNames.toModel(row);
    // Local, as Firestore's Timestamp.toDate() always handed back.
    for (final key in ['placedAt', 'acceptDeadlineAt', 'deliveredAt']) {
      if (model[key] is String) {
        model[key] = DateTime.parse(model[key] as String).toLocal();
      }
    }
    return Order.fromJson(model);
  }

  Stream<List<Order>> _run(String column, String value) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [RowFilter(column, value)],
      ins: [RowIn('status', [for (final s in _onTheRun) s.name])],
    ).map(
      // Oldest first: the order that has been sitting longest is the one whose food is
      // going cold.
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) =>
      _run('merchant_id', merchantId);

  @override
  Stream<List<Order>> watchForPlatform(String cityId) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [
        RowFilter('city_id', cityId),
        // Frozen on the order, not looked up on the merchant: a merchant who stops
        // delivering their own orders next week must not change who was answerable for
        // last week's.
        RowFilter('delivery_by', DeliveryBy.platform.name),
      ],
      ins: [RowIn('status', [for (final s in _onTheRun) s.name])],
    ).map(
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [RowFilter('id', orderId)],
    ).map((orders) {
      if (orders.isEmpty) throw const NotFoundFailure();
      return orders.single;
    });
  }

  Future<Map<String, dynamic>?> _rowOf(String orderId) async =>
      await _db.from('orders').select().eq('id', orderId).maybeSingle();

  /// Reads the order and checks the move as a courier would make it. The same rules are
  /// enforced again in the policies; this copy exists so the app can hide a button
  /// rather than offer an action that is about to be refused.
  Future<Order> _checked(String orderId, OrderStatus to) async {
    final row = await _rowOf(orderId);
    if (row == null) throw const NotFoundFailure();

    final order = _toOrder(row);
    if (!order.status.canMoveTo(to, by: OrderActor.courier)) {
      throw const ConflictFailure();
    }
    return order;
  }

  @override
  Future<Result<void>> markOnTheWay(
    String orderId, {
    required String courierUid,
  }) {
    return Result.guard(() async {
      await _checked(orderId, OrderStatus.outForDelivery);

      // Written in the same breath as the status. It is what keeps a platform courier
      // able to read the order afterwards, and what tells a customer who is holding
      // their dinner.
      await _db.from('orders').update({
        'status': OrderStatus.outForDelivery.name,
        'courier_uid': courierUid,
      }).eq('id', orderId);
    });
  }

  @override
  Future<Result<void>> markDelivered(String orderId) {
    return Result.guard(() async {
      await _checked(orderId, OrderStatus.delivered);

      await _db.from('orders').update({
        'status': OrderStatus.delivered.name,
        'delivered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);
    });
  }

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) {
    return Result.guard(() async {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) throw const ConflictFailure();

      await _checked(orderId, OrderStatus.cancelled);

      await _db.from('orders').update({
        'status': OrderStatus.cancelled.name,
        'cancel_reason': trimmed,
        'cancelled_by': OrderActor.courier.name,
      }).eq('id', orderId);
    });
  }
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