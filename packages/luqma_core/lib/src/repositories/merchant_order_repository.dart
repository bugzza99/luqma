// `Order` here would be Firestore's index-definition enum, not ours.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

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

const _live = [
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

class FirestoreMerchantOrderRepository implements MerchantOrderRepository {
  FirestoreMerchantOrderRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _firestore.collection('orders');

  @override
  Stream<List<Order>> watchIncoming(String merchantId) {
    return _byStatus(merchantId, _needsAnswer).map(
      // Ascending: the order that has been waiting longest is the one about to time out,
      // and it belongs at the top of the screen.
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<Order>> watchLive(String merchantId) {
    return _byStatus(merchantId, _live).map(
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  Stream<List<Order>> _byStatus(String merchantId, List<OrderStatus> statuses) {
    return _orders
        .where('merchantId', isEqualTo: merchantId)
        .where('status', whereIn: [for (final s in statuses) s.name])
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toOrder).toList());
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) throw const NotFoundFailure();
      return _toOrder(doc);
    });
  }

  @override
  Future<Result<void>> accept(String orderId, {required int prepMinutes}) {
    return Result.guard(() async {
      if (prepMinutes < _minPrepMinutes || prepMinutes > _maxPrepMinutes) {
        throw const ConflictFailure();
      }

      final order = await _require(orderId);
      // A merchant tapping accept on an order the customer cancelled a second ago would
      // otherwise start cooking food nobody is coming for.
      if (!_needsAnswer.contains(order.status)) throw const ConflictFailure();

      await _orders.doc(orderId).update({
        'status': OrderStatus.accepted.name,
        'prepMinutes': prepMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Result<void>> reject(String orderId, {required String reason}) {
    return Result.guard(() async {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) throw const ConflictFailure();

      final order = await _require(orderId);
      if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.merchant)) {
        throw const ConflictFailure();
      }

      await _orders.doc(orderId).update({
        'status': OrderStatus.cancelled.name,
        'cancelReason': trimmed,
        'cancelledBy': OrderActor.merchant.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Result<void>> advance(String orderId, {required OrderStatus to}) {
    return Result.guard(() async {
      final order = await _require(orderId);
      // Asked here as well as in the rules, so the app can hide a button rather than
      // offer an action that is about to be refused. Delivery is not on this list: the
      // courier marks it, because the courier is the one standing at the door with the
      // cash, and a merchant marking it from the kitchen is a guess.
      if (!order.status.canMoveTo(to, by: OrderActor.merchant)) {
        throw const ConflictFailure();
      }

      await _orders.doc(orderId).update({
        'status': to.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Order> _require(String orderId) async {
    final doc = await _orders.doc(orderId).get();
    if (!doc.exists) throw const NotFoundFailure();
    return _toOrder(doc);
  }

  Order _toOrder(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromJson({...doc.data()!, 'id': doc.id});
}

/// In-memory orders for the kitchen, for tests and for building screens without a
/// backend. It re-applies the same transition rules — a fake that is more permissive
/// than production hides exactly the bugs it exists to catch.
class FakeMerchantOrderRepository implements MerchantOrderRepository {
  FakeMerchantOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Failure? failure;

  @override
  Stream<List<Order>> watchIncoming(String merchantId) =>
      _stream(merchantId, _needsAnswer);

  @override
  Stream<List<Order>> watchLive(String merchantId) => _stream(merchantId, _live);

  Stream<List<Order>> _stream(String merchantId, List<OrderStatus> statuses) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _orders.values
          .where((o) => o.merchantId == merchantId && statuses.contains(o.status))
          .toList()
        ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    if (failure != null) return Stream.error(failure!);
    final order = _orders[orderId];
    if (order == null) return Stream.error(const NotFoundFailure());
    return Stream.value(order);
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
    return const Result.ok(null);
  }
}
