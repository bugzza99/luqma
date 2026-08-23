// Both Firebase packages export a name we already use: cloud_firestore has an `Order`
// enum for index definitions, and cloud_functions has its own `Result`. Neither is
// wanted here, and letting either through would shadow the model this file is about.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../result.dart';

/// What the phone sends when it asks for an order to be created.
///
/// Deliberately not an [Order]: no total, no fee, no coupon discount, no order number.
/// The server recomputes every one of those from the merchant's own menu. With cash, the
/// figure on the screen is the money a person hands over — so the phone gets to say what
/// was wanted, and the server says what it costs.
@immutable
class OrderDraft {
  const OrderDraft({
    required this.merchantId,
    required this.addressId,
    required this.items,
    required this.type,
    this.couponCode,
    this.note,
  });

  final String merchantId;
  final String addressId;
  final List<OrderLine> items;
  final OrderType type;
  final String? couponCode;
  final String? note;

  Map<String, dynamic> toJson() => {
        'merchantId': merchantId,
        'addressId': addressId,
        'items': items.map((i) => i.toJson()).toList(),
        'type': type.name,
        if (couponCode != null) 'couponCode': couponCode,
        if (note != null) 'note': note,
      };
}

/// Orders, from the customer's side.
abstract interface class OrderRepository {
  /// Asks the server to create the order. Returns it as the server wrote it — including
  /// the total, which may not be the one the phone had in mind.
  Future<Result<Order>> placeOrder(OrderDraft draft);

  /// Live. Errors with [NotFoundFailure] rather than hanging on an order that is gone.
  Stream<Order> watchOrder(String orderId);

  /// Live, newest first.
  Stream<List<Order>> watchMyOrders(String uid);

  /// Only while the merchant has not answered yet. Once a kitchen has started, cancelling
  /// costs somebody food they already cooked.
  Future<Result<void>> cancel(String orderId, {required String reason});

  Future<Result<void>> raiseIssue({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required String reason,
  });

  /// One rating per order — a second one replaces the first rather than counting twice.
  Future<Result<void>> rate({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required int stars,
    String? comment,
  });
}

/// Sends the draft to the server and returns the id of the order it created.
typedef PlaceOrderCall = Future<String> Function(OrderDraft draft);

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._firestore, {PlaceOrderCall? placeOrderCall})
      : _placeOrderCall = placeOrderCall ?? _callable;

  final FirebaseFirestore _firestore;
  final PlaceOrderCall _placeOrderCall;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _firestore.collection('orders');

  static Future<String> _callable(OrderDraft draft) async {
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('placeOrder')
        .call<Map<String, dynamic>>(draft.toJson());
    return result.data['orderId'] as String;
  }

  @override
  Future<Result<Order>> placeOrder(OrderDraft draft) {
    return Result.guard(() async {
      final orderId = await _placeOrderCall(draft);
      final doc = await _orders.doc(orderId).get();
      if (!doc.exists) throw const NotFoundFailure();
      return _toOrder(doc);
    });
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) throw const NotFoundFailure();
      return _toOrder(doc);
    });
  }

  @override
  Stream<List<Order>> watchMyOrders(String uid) {
    return _orders
        .where('customerUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toOrder).toList()
          // By order number rather than by timestamp: the number is assigned by the
          // server in sequence, while `placedAt` is null for the moment between the
          // write landing and the server timestamp resolving.
          ..sort((a, b) => b.orderNumber.compareTo(a.orderNumber)));
  }

  @override
  Future<Result<void>> cancel(String orderId, {required String reason}) {
    return Result.guard(() async {
      final doc = await _orders.doc(orderId).get();
      if (!doc.exists) throw const NotFoundFailure();

      final order = _toOrder(doc);
      // Asked here as well as in the rules, so the app can hide the button rather than
      // offer an action that is about to be refused.
      if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer)) {
        throw const ConflictFailure();
      }

      await _orders.doc(orderId).update({
        'status': OrderStatus.cancelled.name,
        'cancelReason': reason,
        'cancelledBy': OrderActor.customer.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Result<void>> raiseIssue({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required String reason,
  }) {
    return Result.guard(
      () => _firestore.collection('orderIssues').add({
        'orderId': orderId,
        'customerUid': customerUid,
        'merchantId': merchantId,
        'reason': reason,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<Result<void>> rate({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required int stars,
    String? comment,
  }) {
    return Result.guard(
      // Keyed by the order, so rating again corrects the first rating instead of
      // letting one customer move a merchant's average as far as they like.
      () => _firestore.collection('ratings').doc(orderId).set({
        'orderId': orderId,
        'customerUid': customerUid,
        'merchantId': merchantId,
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  Order _toOrder(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromJson({...doc.data()!, 'id': doc.id});
}

/// In-memory orders, for tests and for the screens above before the server exists.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Failure? failure;

  /// Every issue and rating filed, so a test can assert on what a screen produced.
  final List<Map<String, dynamic>> issues = [];
  final List<Map<String, dynamic>> ratings = [];

  @override
  Future<Result<Order>> placeOrder(OrderDraft draft) async {
    if (failure != null) return Result.err(failure!);

    final id = 'order-${_orders.length + 1}';
    final order = Order(
      id: id,
      cityId: 'edku',
      orderNumber: 100 + _orders.length + 1,
      customerUid: 'fake-uid',
      customerName: 'عميل تجريبي',
      customerPhone: '01000000000',
      merchantId: draft.merchantId,
      merchantName: 'مطعم',
      zoneId: 'z1',
      type: draft.type,
      items: draft.items,
      pricing: OrderPricing.compute(items: draft.items, deliveryFee: 1000),
      couponCode: draft.couponCode,
      placedAt: DateTime.now(),
    );
    _orders[id] = order;
    return Result.ok(order);
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    if (failure != null) return Stream.error(failure!);
    final order = _orders[orderId];
    if (order == null) return Stream.error(const NotFoundFailure());
    return Stream.value(order);
  }

  @override
  Stream<List<Order>> watchMyOrders(String uid) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _orders.values.where((o) => o.customerUid == uid).toList()
        ..sort((a, b) => b.orderNumber.compareTo(a.orderNumber)),
    );
  }

  @override
  Future<Result<void>> cancel(String orderId, {required String reason}) async {
    if (failure != null) return Result.err(failure!);

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer)) {
      return const Result.err(ConflictFailure());
    }

    _orders[orderId] = order.copyWith(
      status: OrderStatus.cancelled,
      cancelReason: reason,
      cancelledBy: OrderActor.customer,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> raiseIssue({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required String reason,
  }) async {
    if (failure != null) return Result.err(failure!);
    issues.add({
      'orderId': orderId,
      'customerUid': customerUid,
      'merchantId': merchantId,
      'reason': reason,
    });
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> rate({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required int stars,
    String? comment,
  }) async {
    if (failure != null) return Result.err(failure!);
    ratings
      ..removeWhere((r) => r['orderId'] == orderId)
      ..add({
        'orderId': orderId,
        'customerUid': customerUid,
        'merchantId': merchantId,
        'stars': stars,
        'comment': comment,
      });
    return const Result.ok(null);
  }
}
