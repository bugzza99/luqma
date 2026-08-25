// The backend exports names this file already uses; neither is wanted here, and letting
// either through would shadow the model this file is about.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
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
    required this.items,
    required this.type,
    this.addressId,
    this.dailyMealId,
    this.couponCode,
    this.note,
  });

  final String merchantId;

  /// Null for a pre-order the customer is collecting themselves — there is nowhere to
  /// deliver it to, and demanding an address for a meal somebody is walking to would be
  /// a step invented for the sake of a required field.
  final String? addressId;

  /// Which meal's counter to decrement, for a pre-order.
  ///
  /// The server does the decrement in a transaction. Two people tapping the last portion
  /// at the same moment is the one thing the whole `dailyMeals` collection exists to get
  /// right, and no client can do it correctly.
  final String? dailyMealId;

  final List<OrderLine> items;
  final OrderType type;
  final String? couponCode;
  final String? note;

  Map<String, dynamic> toJson() => {
        'merchantId': merchantId,
        if (addressId != null) 'addressId': addressId,
        if (dailyMealId != null) 'dailyMealId': dailyMealId,
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

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository(this._db);

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

  @override
  Future<Result<Order>> placeOrder(OrderDraft draft) {
    return Result.guard(() async {
      // One function owns the whole act: prices read from the menu, the coupon judged
      // against its own counters, the portion taken inside the same transaction. What
      // comes back is the order as the server wrote it.
      final row = await _db.rpc('place_order', params: {'p_draft': draft.toJson()});
      return _toOrder(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [RowFilter('id', orderId)],
      // The tracking screen holds one order; when it disappears so does the watch,
      // and NotFound is what arrives.
    ).map((orders) {
      if (orders.isEmpty) throw const NotFoundFailure();
      return orders.single;
    });
  }

  @override
  Stream<List<Order>> watchMyOrders(String uid) {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      filters: [RowFilter('customer_uid', uid)],
      // By order number rather than by timestamp: the number is assigned by the server
      // in sequence, while `placed_at` is null for the moment between the write landing
      // and the clock resolving.
      orderBy: 'order_number',
      ascending: false,
    );
  }

  @override
  Future<Result<void>> cancel(String orderId, {required String reason}) {
    return Result.guard(() async {
      final row =
          await _db.from('orders').select().eq('id', orderId).maybeSingle();
      if (row == null) throw const NotFoundFailure();

      final order = _toOrder(row);
      // Asked here as well as in the policies, so the app can hide the button rather
      // than offer an action that is about to be refused.
      if (!order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer)) {
        throw const ConflictFailure();
      }

      await _db.from('orders').update({
        'status': OrderStatus.cancelled.name,
        'cancel_reason': reason,
        'cancelled_by': OrderActor.customer.name,
      }).eq('id', orderId);
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
      () => _db.from('order_issues').insert({
        'order_id': orderId,
        'customer_uid': customerUid,
        'merchant_id': merchantId,
        'reason': reason,
        'status': 'open',
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
      () => _db.from('ratings').upsert({
        'order_id': orderId,
        'customer_uid': customerUid,
        'merchant_id': merchantId,
        'stars': stars,
        'comment': (comment == null || comment.isEmpty) ? null : comment,
      }, onConflict: 'order_id'),
    );
  }
}

/// In-memory orders, for tests and for the screens above before the server exists.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Failure? failure;

  /// Every draft, issue and rating this repository was handed, so a test can assert on
  /// what a screen produced rather than on what it displayed.
  final List<OrderDraft> drafts = [];
  final List<Map<String, dynamic>> issues = [];
  final List<Map<String, dynamic>> ratings = [];

  @override
  Future<Result<Order>> placeOrder(OrderDraft draft) async {
    drafts.add(draft);
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
