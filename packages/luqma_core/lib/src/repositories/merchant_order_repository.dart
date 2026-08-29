import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/order.dart';
import '../result.dart';

/// Orders as the kitchen sees them.
///
/// A separate interface from the customer's, not a bigger one: the two ask different
/// questions of the same collection, and the transitions each is allowed to make barely
/// overlap. One interface carrying both would be an interface where half the methods
/// throw for half the callers.
abstract interface class MerchantOrderRepository {
  /// Orders waiting for an answer. Oldest first — that one is closest to running out
  /// of time. Live.
  Stream<List<Order>> watchIncoming(String merchantId);

  /// Accepted, being prepared, or on the road. Live.
  Stream<List<Order>> watchLive(String merchantId);

  Stream<Order> watchOrder(String orderId);

  /// Takes the order, promising [prepMinutes]. The customer is shown that number, so it
  /// is checked before it is written rather than trusted because a finger hit it.
  Future<Result<void>> accept(String orderId, {required int prepMinutes});

  /// Refuses it. The reason is required: without one the customer is told nothing and
  /// the admin has nothing to look at.
  Future<Result<void>> reject(String orderId, {required String reason});

  /// Moves an order one step. Only the steps a merchant is allowed to make.
  Future<Result<void>> advance(String orderId, {required OrderStatus to});
}

/// What the merchant sees on the "answer this" screen.
///
/// `needsAttention` is here on purpose. It means nobody answered in time and the admin
/// was told — but it is still a customer waiting for food, not a closed case, and a
/// merchant who comes back to their phone has to be able to deal with it.
const _needsAnswer = [OrderStatus.placed, OrderStatus.needsAttention];

/// What is already being cooked or carried. The "live orders" board.
const _onTheStove = [
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.outForDelivery,
];

/// The floor and ceiling on a promised preparation time, in minutes.
///
/// Zero is a promise nobody can keep and three hours is a merchant who meant three
/// minutes. Either one reaches the customer as a time they plan their evening around.
const _minPrepMinutes = 3;
const _maxPrepMinutes = 180;

class SupabaseMerchantOrderRepository implements MerchantOrderRepository {
  SupabaseMerchantOrderRepository(this._db);

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

  Stream<List<Order>> _byStatus(String merchantId, List<OrderStatus> statuses) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [RowFilter('merchant_id', merchantId)],
      ins: [RowIn('status', [for (final s in statuses) s.name])],
    ).map(
      // Ascending: the order that has been waiting longest is the one about to time
      // out, and it belongs at the top of the screen.
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<Order>> watchIncoming(String merchantId) =>
      _byStatus(merchantId, _needsAnswer);

  @override
  Stream<List<Order>> watchLive(String merchantId) =>
      _byStatus(merchantId, _onTheStove);

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

  @override
  Future<Result<void>> accept(String orderId, {required int prepMinutes}) {
    return Result.guard(() async {
      // The count checks come first; a merchant tapping accept on an order the customer
      // cancelled a second ago would otherwise start cooking food nobody is coming for.
      final row = await _rowOf(orderId);
      if (row == null) throw const NotFoundFailure();
      final order = _toOrder(row);
      if (!_needsAnswer.contains(order.status)) throw const ConflictFailure();

      await _db.from('orders').update({
        'status': OrderStatus.accepted.name,
        'prep_minutes': prepMinutes,
      }).eq('id', orderId);
    });
  }

  @override
  Future<Result<void>> reject(String orderId, {required String reason}) {
    return Result.guard(() async {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) throw const ConflictFailure();

      final row = await _rowOf(orderId);
      if (row == null) throw const NotFoundFailure();
      final order = _toOrder(row);
      if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.merchant)) {
        throw const ConflictFailure();
      }

      await _db.from('orders').update({
        'status': OrderStatus.cancelled.name,
        'cancel_reason': trimmed,
        'cancelled_by': OrderActor.merchant.name,
      }).eq('id', orderId);
    });
  }

  @override
  Future<Result<void>> advance(String orderId, {required OrderStatus to}) {
    return Result.guard(() async {
      final row = await _rowOf(orderId);
      if (row == null) throw const NotFoundFailure();
      final order = _toOrder(row);
      if (!order.status.canMoveTo(to, by: OrderActor.merchant)) {
        throw const ConflictFailure();
      }

      await _db.from('orders').update({'status': to.name}).eq('id', orderId);
    });
  }
}

/// In-memory orders, for tests and for building the kitchen screens without a backend.
///
/// Its streams are live the way Firestore's are: accepting an order pushes a new list to
/// whoever is watching. A fake that emits once and stops would let a screen pass its
/// tests while leaving an answered order sitting on the inbox — which is precisely the
/// bug the fake exists to catch.
class FakeMerchantOrderRepository implements MerchantOrderRepository {
  FakeMerchantOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Everything held right now. A widget test runs on a fake clock and cannot await one
  /// of the streams below.
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

  /// Puts an order in and tells everyone watching — a new order landing, as Firestore
  /// delivered it.
  Future<void> add(Order order) async {
    _orders[order.id] = order;
    _notify();
  }

  /// Re-emits every watch without changing anything. Firestore does this: a snapshot
  /// fires for reasons of its own — a field written by another client still counts as
  /// a reason to deliver the list again.
  Future<void> touch() async => _notify();

  @override
  Stream<List<Order>> watchIncoming(String merchantId) =>
      _stream(merchantId, _needsAnswer);

  @override
  Stream<List<Order>> watchLive(String merchantId) =>
      _stream(merchantId, _onTheStove);

  Stream<List<Order>> _stream(String merchantId, List<OrderStatus> statuses) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _orders.values
          .where((o) => o.merchantId == merchantId && statuses.contains(o.status))
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
  Future<Result<void>> accept(String orderId, {required int prepMinutes}) async {
    if (failure != null) return Result.err(failure!);
    if (prepMinutes < _minPrepMinutes || prepMinutes > _maxPrepMinutes) {
      return const Result.err(ConflictFailure());
    }

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    if (!_needsAnswer.contains(order.status)) return const Result.err(ConflictFailure());

    _orders[orderId] = order.copyWith(
      status: OrderStatus.accepted,
      prepMinutes: prepMinutes,
    );
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reject(String orderId, {required String reason}) async {
    if (failure != null) return Result.err(failure!);
    if (reason.trim().isEmpty) return const Result.err(ConflictFailure());

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.merchant)) {
      return const Result.err(ConflictFailure());
    }

    _orders[orderId] = order.copyWith(
      status: OrderStatus.cancelled,
      cancelReason: reason.trim(),
      cancelledBy: OrderActor.merchant,
    );
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> advance(String orderId, {required OrderStatus to}) async {
    if (failure != null) return Result.err(failure!);

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    if (!order.status.canMoveTo(to, by: OrderActor.merchant)) {
      return const Result.err(ConflictFailure());
    }

    _orders[orderId] = order.copyWith(status: to);
    _notify();
    return const Result.ok(null);
  }
}