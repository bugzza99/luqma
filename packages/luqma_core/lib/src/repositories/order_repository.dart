import 'dart:math';

// The backend exports names this file already uses; neither is wanted here, and letting
// either through would shadow the model this file is about.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/coupon.dart' show CouponAccepted, CouponEvaluation, CouponRejection, CouponRejected;
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
    this.clientOrderId,
    this.addressId,
    this.dailyMealId,
    this.couponCode,
    this.note,
  });

  final String merchantId;

  /// One checkout's identity, generated once by the screen and kept through retries.
  ///
  /// Null is the old-client path. The server deliberately keeps accepting it, because
  /// an APK already installed cannot learn a new required argument.
  final String? clientOrderId;

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
        if (clientOrderId != null) 'clientOrderId': clientOrderId,
        if (addressId != null) 'addressId': addressId,
        if (dailyMealId != null) 'dailyMealId': dailyMealId,
        'items': items.map((i) => i.toJson()).toList(),
        'type': type.name,
        if (couponCode != null) 'couponCode': couponCode,
        if (note != null) 'note': note,
      };
}

/// A v4 uuid made without adding a package for sixteen random bytes.
String newClientOrderId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
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

    /// Stars per dish, keyed by `menu_items.id`.
    ///
    /// Optional, and empty is the ordinary case: somebody who rates the shop and skips
    /// the food has rated the shop. A dish left out is not a zero — it is silence, and
    /// writing a zero would drag the item's average down for not being commented on.
    Map<String, int> items,
  });

  /// Prices one coupon against one basket, placing nothing. The verdict is what the
  /// server will enforce again at placement, so the total shown is a promise kept -
  /// computed by the same arithmetic that will judge it at the door.
  Future<Result<CouponEvaluation>> evaluateCoupon({
    required String code,
    required String merchantId,
    required int subtotal,
    required int deliveryFee,
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
      final row = await _db.rpc('place_order', params: {
        'p_draft': draft.toJson(),
        if (draft.clientOrderId != null)
          'p_client_order_id': draft.clientOrderId,
      });
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
      // One conditional statement rather than a read-then-write. The old shape read the
      // order, decided it was cancellable, and wrote - and a merchant accepting inside
      // that gap turned into a generic failure instead of a sentence about the world
      // having moved on. Zero rows now means either of two things, named below.
      final updated = await _db
          .from('orders')
          .update({
            'status': OrderStatus.cancelled.name,
            'cancel_reason': reason,
            'cancelled_by': OrderActor.customer.name,
          })
          .eq('id', orderId)
          // Only while nobody has answered. Once a kitchen has started, cancelling
          // costs somebody food they already cooked.
          .eq('status', OrderStatus.placed.name)
          .select();
      if (updated.isNotEmpty) return;

      // Nothing moved: either the order never existed, or somebody got there first.
      final row =
          await _db.from('orders').select('id').eq('id', orderId).maybeSingle();
      if (row == null) throw const NotFoundFailure();
      throw const ConflictFailure();
    });
  }

  @override
  Future<Result<void>> raiseIssue({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required String reason,
  }) {
    return Result.guardWrite(
      () => _db.from('order_issues').insert({
        'order_id': orderId,
        'customer_uid': customerUid,
        'merchant_id': merchantId,
        'reason': reason,
        'status': 'open',
      }).select('id'),
      (_) {},
    );
  }

  @override
  Future<Result<void>> rate({
    required String orderId,
    required String customerUid,
    required String merchantId,
    required int stars,
    String? comment,
    Map<String, int> items = const {},
  }) {
    return Result.guard(() async {
      // Keyed by the order, so rating again corrects the first rating instead of
      // letting one customer move a merchant's average as far as they like.
      await _db.from('ratings').upsert({
        'order_id': orderId,
        'customer_uid': customerUid,
        'merchant_id': merchantId,
        'stars': stars,
        'comment': (comment == null || comment.isEmpty) ? null : comment,
      }, onConflict: 'order_id');

      if (items.isEmpty) return;

      // The shop's rating is written first and on its own. If the dishes fail — a menu
      // item deleted since the order, a policy that refuses one of them — the verdict
      // the customer typed is already saved rather than lost with them.
      await _db.from('item_ratings').upsert([
        for (final entry in items.entries)
          {
            'order_id': orderId,
            'item_id': entry.key,
            'merchant_id': merchantId,
            'customer_uid': customerUid,
            'stars': entry.value,
          },
      ], onConflict: 'order_id,item_id');
    });
  }
  @override
  Future<Result<CouponEvaluation>> evaluateCoupon({
    required String code,
    required String merchantId,
    required int subtotal,
    required int deliveryFee,
  }) {
    return Result.guard(() async {
      // The same function place_order trusts; the preview cannot promise a discount
      // the placement would refuse.
      final row = await _db.rpc('evaluate_coupon', params: {
        'p_code': code,
        'p_merchant_id': merchantId,
        'p_subtotal': subtotal,
        'p_delivery_fee': deliveryFee,
      });
      final map = Map<String, dynamic>.from(row as Map);
      if (map['status'] == 'accepted') {
        return CouponAccepted(
          subtotalDiscount: map['subtotalDiscount'] as int,
          deliveryDiscount: map['deliveryDiscount'] as int,
          platformOwesMerchant: map['platformOwesMerchant'] as int,
        );
      }
      return CouponRejected(
        CouponRejection.values.firstWhere(
          (r) => r.name == map['reason'],
          orElse: () => CouponRejection.notFound,
        ),
      );
    });
  }
}

/// In-memory orders, for tests and for the screens above before the server exists.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({List<Order> seed = const [], this.failure})
      : _orders = {for (final o in seed) o.id: o};

  final Map<String, Order> _orders;
  final Map<String, String> _clientOrders = {};
  final Failure? failure;

  /// Every draft, issue and rating this repository was handed, so a test can assert on
  /// what a screen produced rather than on what it displayed.
  final List<OrderDraft> drafts = [];
  final List<Map<String, dynamic>> issues = [];
  final List<Map<String, dynamic>> ratings = [];

  /// What [evaluateCoupon] answers. Set by a test; a fake with no coupons on file
  /// rejects everything as unknown.
  CouponEvaluation couponEvaluation =
      const CouponRejected(CouponRejection.notFound);

  @override
  Future<Result<CouponEvaluation>> evaluateCoupon({
    required String code,
    required String merchantId,
    required int subtotal,
    required int deliveryFee,
  }) async =>
      Result.ok(couponEvaluation);

  @override
  Future<Result<Order>> placeOrder(OrderDraft draft) async {
    drafts.add(draft);
    if (failure != null) return Result.err(failure!);

    final existingId = draft.clientOrderId == null
        ? null
        : _clientOrders[draft.clientOrderId!];
    if (existingId != null) return Result.ok(_orders[existingId]!);

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
    if (draft.clientOrderId != null) {
      _clientOrders[draft.clientOrderId!] = id;
    }
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
    if (!_orders.containsKey(orderId)) return const Result.err(NotFoundFailure());
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
    Map<String, int> items = const {},
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
        'items': Map<String, int>.from(items),
      });
    return const Result.ok(null);
  }
}
