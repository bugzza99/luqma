import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/courier_money.dart';
import '../models/courier_summary.dart';
import '../models/order.dart';
import '../result.dart';
import '../util/cairo_day.dart';

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

  /// Everything this courier carries: all shops they are attached to, plus the
  /// platform when they hold the platform row. Live.
  Stream<List<Order>> watchCarried();

  /// Which shops this rider carries for: merchant IDs, with null meaning the platform. Live.
  Stream<List<String?>> watchCarriedMerchants();

  Stream<Order> watchOrder(String orderId);

  /// Takes the order out, and puts this courier's name on it.
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid});

  Future<Result<void>> markDelivered(String orderId);

  /// Nobody at the door, wrong address, order refused. Needs a reason: it is what the
  /// admin reads, and what eventually blocks a customer who does this repeatedly.
  Future<Result<void>> markFailed(String orderId, {required String reason});

  /// What this courier did today (or on [day]): delivered count, returned count,
  /// cash in hand, and the per-shop breakdown.
  Future<Result<CourierDaySummary>> daySummary({DateTime? day});

  /// Today, this week and this month: what was delivered, what came back, and what is
  /// theirs once the platform's share comes out.
  ///
  /// One call for all three spans. The person reading this is standing in the street, and
  /// three round trips is three chances for one of them not to arrive.
  Future<Result<CourierEarnings>> earnings();
}

/// What a courier has on their hands: ready to collect, or already out.
const _onTheRun = [OrderStatus.preparing, OrderStatus.outForDelivery];

/// Whether [order] is already where a write moving it [to] would put it, because
/// [courierUid] put it there.
///
/// A reply that dies on the way back — "Connection closed before full header was
/// received", a timeout — reaches the app as `OfflineFailure`, so the courier's queue
/// holds a write that has already committed. Its replay then finds the order at the
/// target status, and calling that a conflict told a courier with the cash in their
/// pocket «تحديث محصلش — الأوردر اتغيّر. كلّم الإدارة» about a delivery that went through.
///
/// "Put there by this courier" is read the way `is_courier_for_order` reads it: their
/// name on the order, or — on a shop's own order that the shop sent out with nobody's
/// name on it — no name at all, which any rider the shop has attached may deliver and
/// which the row does not tell apart afterwards. A platform order is never delivered
/// without a name (`20261101020000`), so a nameless one is nobody's to claim. Leaving
/// a finished order as it is, is all this ever does: nothing is written on its strength.
///
/// One rule, shared by the real repository and the fake, so the two cannot come to
/// disagree about which replay settles.
bool _alreadyLanded(Order order, OrderStatus to, {required String? courierUid}) {
  if (courierUid == null || order.status != to) return false;
  final carried = order.courierUid == courierUid ||
      (order.courierUid == null && order.deliveryBy == DeliveryBy.merchant);
  return switch (to) {
    // `markOnTheWay` writes the name in the same update, so its own write left the name.
    OrderStatus.outForDelivery => order.courierUid == courierUid,
    OrderStatus.delivered => carried,
    // A return somebody else recorded — the shop, an admin — is theirs, not a lost reply.
    OrderStatus.cancelled => carried && order.cancelledBy == OrderActor.courier,
    _ => false,
  };
}
class SupabaseCourierOrderRepository implements CourierOrderRepository {
  /// [currentUid] is who is signed in, and defaults to the session's user. It is a
  /// parameter only so a test with no session can say which courier is asking.
  SupabaseCourierOrderRepository(this._db, {this._currentUid});

  final SupabaseClient _db;
  final String? Function()? _currentUid;

  String? get _me => _currentUid != null ? _currentUid() : _db.auth.currentUser?.id;

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
  Stream<List<Order>> watchCarried() {
    return watchRows(
      db: _db,
      table: 'orders',
      map: _toOrder,
      ins: [RowIn('status', [for (final s in _onTheRun) s.name])],
    ).map(
      (orders) => orders..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<String?>> watchCarriedMerchants() {
    return watchRows(
      db: _db,
      table: 'courier_merchants',
      map: (row) => row['merchant_id'] as String?,
      filters: [RowFilter('is_active', 'true')],
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
  ///
  /// False when there is nothing to write because [courierUid]'s own earlier write of
  /// this move already landed — see [_alreadyLanded].
  Future<bool> _checked(
    String orderId,
    OrderStatus to, {
    required String? courierUid,
  }) async {
    final row = await _rowOf(orderId);
    if (row == null) throw const NotFoundFailure();

    final order = _toOrder(row);
    if (_alreadyLanded(order, to, courierUid: courierUid)) return false;
    if (!order.status.canMoveTo(to, by: OrderActor.courier)) {
      throw const ConflictFailure();
    }
    return true;
  }

  /// What `guardWrite` is handed when the write had already landed: the row it would
  /// have changed, so the answer is the success it is rather than "nothing matched".
  List<Map<String, dynamic>> _landed(String orderId) => [
        {'id': orderId},
      ];

  @override
  Future<Result<void>> markOnTheWay(
    String orderId, {
    required String courierUid,
  }) {
    return Result.guardWrite<void, Map<String, dynamic>>(() async {
      if (!await _checked(orderId, OrderStatus.outForDelivery,
          courierUid: courierUid)) {
        return _landed(orderId);
      }

      // Written in the same breath as the status. It is what keeps a platform courier
      // able to read the order afterwards, and what tells a customer who is holding
      // their dinner.
      return _db.from('orders').update({
        'status': OrderStatus.outForDelivery.name,
        'courier_uid': courierUid,
      }).eq('id', orderId).select('id');
    }, (_) {});
  }

  @override
  Future<Result<void>> markDelivered(String orderId) {
    return Result.guardWrite<void, Map<String, dynamic>>(() async {
      if (!await _checked(orderId, OrderStatus.delivered, courierUid: _me)) {
        return _landed(orderId);
      }

      return _db.from('orders').update({
        'status': OrderStatus.delivered.name,
        'delivered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId).select('id');
    }, (_) {});
  }

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) {
    return Result.guardWrite<void, Map<String, dynamic>>(() async {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) throw const ConflictFailure();

      if (!await _checked(orderId, OrderStatus.cancelled, courierUid: _me)) {
        return _landed(orderId);
      }

      return _db.from('orders').update({
        'status': OrderStatus.cancelled.name,
        'cancel_reason': trimmed,
        'cancelled_by': OrderActor.courier.name,
      }).eq('id', orderId).select('id');
    }, (_) {});
  }

  @override
  Future<Result<CourierDaySummary>> daySummary({DateTime? day}) {
    return Result.guard(() async {
      final data = await _db.rpc(
        'courier_day_summary',
        params: {
          if (day != null)
            'p_day':
                '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        },
      );
      if (data == null) return CourierDaySummary.empty;
      return CourierDaySummary.fromJson(Map<String, dynamic>.from(data as Map));
    });
  }

  @override
  Future<Result<CourierEarnings>> earnings() {
    return Result.guard(() async {
      final data = await _db.rpc('courier_earnings');
      if (data == null) return CourierEarnings.empty;
      return CourierEarnings.fromJson(Map<String, dynamic>.from(data as Map));
    });
  }
}

/// In-memory deliveries, for tests and for building the courier screens without a
/// backend. Re-applies the same transition rules as the real one.
class FakeCourierOrderRepository implements CourierOrderRepository {
  FakeCourierOrderRepository({
    List<Order> seed = const [],
    this.failure,
    Iterable<String?>? carriedMerchants,
    this.courierUid,
    DateTime Function()? now,
    Map<String, DateTime> updatedAt = const {},
  })  : _orders = {for (final o in seed) o.id: o},
        _carried = carriedMerchants != null
            ? Set<String?>.of(carriedMerchants)
            : <String?>{},
        _now = now ?? DateTime.now {
    for (final order in seed) {
      _updatedAt[order.id] = updatedAt[order.id] ?? _now();
    }
  }

  final Map<String, Order> _orders;

  /// The courier this repository acts as. Only this courier's work is counted
  /// in shift summaries.
  String? courierUid;

  final DateTime Function() _now;
  // Seeded rows default to their insertion time, just as orders.updated_at does.
  final Map<String, DateTime> _updatedAt = {};

  /// The shops this courier carries for, modeling the `courier_merchants` join table.
  /// Null is the platform row: home kitchens, and merchants that do not deliver for
  /// themselves.
  final Set<String?> _carried;

  /// Attaches this courier to [merchantId] (null means the platform).
  void attach(String? merchantId) {
    _carried.add(merchantId);
    _notify();
  }

  /// Detaches this courier from [merchantId] (null means the platform).
  void detach(String? merchantId) {
    _carried.remove(merchantId);
    _notify();
  }

  /// Whether this courier carries for [merchantId] (null means platform).
  bool carries(String? merchantId) => _carried.contains(merchantId);

  /// Mutable on purpose: a test takes the repository offline and back online, which is
  /// the exact transition the courier write queue exists to survive.
  Failure? failure;

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
  Stream<List<Order>> watchCarried() {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _orders.values
          .where((o) {
            if (!_onTheRun.contains(o.status)) return false;
            // The read policy on `orders`:
            // 1. Merchant order from a shop this courier carries:
            if (_carried.contains(o.merchantId)) {
              return true;
            }
            // 2. Platform delivery when holding the platform row (null):
            if (o.deliveryBy == DeliveryBy.platform && _carried.contains(null)) {
              return true;
            }
            return false;
          })
          .toList()
        ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber)),
    );
  }

  @override
  Stream<List<String?>> watchCarriedMerchants() {
    if (failure != null) return Stream.error(failure!);
    return _live(() => List<String?>.unmodifiable(_carried));
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
          (o) => o.copyWith(courierUid: courierUid),
          by: courierUid);

  @override
  Future<Result<void>> markDelivered(String orderId) => _move(
        orderId,
        OrderStatus.delivered,
        (o) => o.copyWith(deliveredAt: _now()),
        by: courierUid,
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
      by: courierUid,
    );
  }

  Future<Result<void>> _move(
    String orderId,
    OrderStatus to,
    Order Function(Order order) apply, {
    required String? by,
  }) async {
    if (failure != null) return Result.err(failure!);

    final order = _orders[orderId];
    if (order == null) return const Result.err(NotFoundFailure());
    // The same rule as the real pre-check: this courier's own write, landed already.
    if (_alreadyLanded(order, to, courierUid: by)) return const Result.ok(null);
    if (!order.status.canMoveTo(to, by: OrderActor.courier)) {
      return const Result.err(ConflictFailure());
    }
    // A platform order goes out and is delivered only with a courier on it. The server
    // refuses otherwise with a check violation, which reaches the app as a validation
    // failure — and a fake that allowed it would let a screen pass against a state
    // production cannot reach.
    final moved = apply(order);
    if (order.deliveryBy == DeliveryBy.platform &&
        (to == OrderStatus.outForDelivery || to == OrderStatus.delivered) &&
        moved.courierUid == null) {
      return const Result.err(ValidationFailure());
    }

    _orders[orderId] = moved.copyWith(status: to);
    _updatedAt[orderId] = _now();
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<CourierDaySummary>> daySummary({DateTime? day}) async {
    if (failure != null) return Result.err(failure!);

    final target = day == null ? cairoDay(_now()) : DateTime.utc(day.year, day.month, day.day);

    final matching = _orders.values.where((o) {
      if (courierUid == null || o.courierUid != courierUid) return false;

      final happenedAt = o.deliveredAt ?? _updatedAt[o.id];
      if (happenedAt == null || cairoDay(happenedAt) != target) return false;

      final isDelivered = o.status == OrderStatus.delivered;
      final isReturned = o.status == OrderStatus.cancelled &&
          o.cancelledBy == OrderActor.courier;
      return isDelivered || isReturned;
    });

    return Result.ok(CourierDaySummary.of(matching));
  }

  /// The rate this fake charges, so a test can put the screen under a real one.
  double commissionPercent = 10;

  @override
  Future<Result<CourierEarnings>> earnings() async {
    if (failure != null) return Result.err(failure!);

    final today = cairoDay(_now());
    // Saturday, the week somebody settles for. `DateTime.weekday` runs Monday 1 to
    // Sunday 7, so Saturday is 6 and the offset wraps through Sunday.
    final weekStart = today.subtract(Duration(days: (today.weekday + 1) % 7));
    final monthStart = DateTime.utc(today.year, today.month);

    CourierSpan span(DateTime from) {
      var delivered = 0, returned = 0, cash = 0, fees = 0, commission = 0;
      for (final order in _orders.values) {
        if (courierUid == null || order.courierUid != courierUid) continue;
        final happenedAt = order.deliveredAt ?? _updatedAt[order.id];
        if (happenedAt == null) continue;
        final day = cairoDay(happenedAt);
        if (day.isBefore(from) || day.isAfter(today)) continue;

        if (order.status == OrderStatus.delivered) {
          delivered++;
          cash += order.pricing.total;
          final cut = CourierCut.of(order, commissionPercent: commissionPercent);
          fees += cut.forCourier + cut.forPlatform;
          commission += cut.forPlatform;
        } else if (order.status == OrderStatus.cancelled &&
            order.cancelledBy == OrderActor.courier) {
          returned++;
        }
      }
      return CourierSpan(
        delivered: delivered,
        returned: returned,
        cash: cash,
        fees: fees,
        commission: commission,
        net: fees - commission,
      );
    }

    return Result.ok(CourierEarnings(
      today: span(today),
      week: span(weekStart),
      month: span(monthStart),
    ));
  }
}
