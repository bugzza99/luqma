import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/admin.dart';
import '../models/courier_roster.dart';
import '../result.dart';
import '../util/phone.dart';

/// Which couriers carry for a given shop.
///
/// An owner sees and manages their own shop's roster. Attaching goes through the
/// `attach_courier_by_phone` RPC — never by inserting directly, because the policy
/// would let an owner attach any arbitrary uid, and the function is what verifies
/// the phone number belongs to an active courier on the platform.
/// Detaching sets `is_active = false` rather than deleting the row, preserving the
/// attachment identity for when the rider returns.
abstract interface class CourierRosterRepository {
  /// Watches the active couriers carrying for this shop.
  Stream<List<CourierRosterItem>> watchRoster(String merchantId);

  /// Fetches the active couriers carrying for this shop.
  Future<Result<List<CourierRosterItem>>> getRoster(String merchantId);

  /// Attaches an active courier to this shop by their phone number.
  Future<Result<CourierRosterItem>> attachCourier({
    required String merchantId,
    required String phone,
  });

  /// Detaches a courier from this shop's roster by deactivating the row.
  Future<Result<void>> detachCourier({
    required String merchantId,
    required String courierUid,
  });
}

class SupabaseCourierRosterRepository implements CourierRosterRepository {
  SupabaseCourierRosterRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<CourierRosterItem>> watchRoster(String merchantId) {
    return watchRows(
      db: _db,
      table: 'courier_merchants',
      columns:
          'id, courier_uid, merchant_id, is_active, attached_at, staff:courier_uid(uid, name, phone, paused_until)',
      map: CourierRosterItem.fromRow,
      filters: [
        RowFilter('merchant_id', merchantId),
        RowFilter('is_active', 'true'),
      ],
      orderBy: 'attached_at',
      ascending: true,
    );
  }

  @override
  Future<Result<List<CourierRosterItem>>> getRoster(String merchantId) {
    return Result.guard(() async {
      final rows = await _db
          .from('courier_merchants')
          .select(
              'id, courier_uid, merchant_id, is_active, attached_at, staff:courier_uid(uid, name, phone, paused_until)')
          .eq('merchant_id', merchantId)
          .eq('is_active', true)
          .order('attached_at', ascending: true);

      return [for (final row in rows) CourierRosterItem.fromRow(row)];
    });
  }

  @override
  Future<Result<CourierRosterItem>> attachCourier({
    required String merchantId,
    required String phone,
  }) {
    return Result.guard(() async {
      final result = await _db.rpc<Map<String, dynamic>>(
        'attach_courier_by_phone',
        params: {
          'p_merchant_id': merchantId,
          'p_phone': phone,
        },
      );

      final attachment = Map<String, dynamic>.from(result['attachment'] as Map);
      final name = result['name'] as String?;

      return CourierRosterItem(
        id: attachment['id'] as String,
        courierUid: attachment['courier_uid'] as String,
        merchantId: attachment['merchant_id'] as String?,
        isActive: attachment['is_active'] as bool? ?? true,
        attachedAt: switch (attachment['attached_at']) {
          null => null,
          String s => DateTime.tryParse(s)?.toLocal(),
          DateTime d => d,
          _ => null,
        },
        name: name,
        phone: phone,
      );
    });
  }

  @override
  Future<Result<void>> detachCourier({
    required String merchantId,
    required String courierUid,
  }) {
    return Result.guardWrite(
      () => _db
          .from('courier_merchants')
          .update({'is_active': false})
          .eq('merchant_id', merchantId)
          .eq('courier_uid', courierUid)
          .select('id'),
      (_) {},
    );
  }
}

/// In-memory courier roster, for widget tests and screens above it.
class FakeCourierRosterRepository implements CourierRosterRepository {
  FakeCourierRosterRepository({
    List<CourierRosterItem> seed = const [],
    Map<String, StaffMember>? staffByPhone,
    this.failure,
    this.attachFailure,
    this.detachFailure,
  })  : _items = List.of(seed),
        _staffByPhone = staffByPhone != null ? Map.of(staffByPhone) : null;

  final List<CourierRosterItem> _items;
  final Map<String, StaffMember>? _staffByPhone;

  Failure? failure;
  Failure? attachFailure;
  Failure? detachFailure;

  final _changed = StreamController<void>.broadcast();

  List<CourierRosterItem> get all => List.unmodifiable(_items);

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
  Stream<List<CourierRosterItem>> watchRoster(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(() => _items
        .where((item) => item.merchantId == merchantId && item.isActive)
        .toList());
  }

  @override
  Future<Result<List<CourierRosterItem>>> getRoster(String merchantId) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_items
        .where((item) => item.merchantId == merchantId && item.isActive)
        .toList());
  }

  @override
  Future<Result<CourierRosterItem>> attachCourier({
    required String merchantId,
    required String phone,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (attachFailure != null) return Result.err(attachFailure!);

    final normalized = Phone.normalize(phone);

    StaffMember? staff;
    if (_staffByPhone != null) {
      staff = _staffByPhone[normalized] ??
          _staffByPhone.values.cast<StaffMember?>().firstWhere(
                (s) =>
                    s?.phone != null && Phone.normalize(s!.phone!) == normalized,
                orElse: () => null,
              );
      if (staff == null || !staff.isActive || staff.role != 'courier') {
        return const Result.err(NotFoundFailure());
      }
    }

    final courierUid = staff?.uid ?? 'courier-$normalized';
    final name = staff?.name ?? 'محمود';
    final pausedUntil = staff?.pausedUntil;

    final index = _items.indexWhere(
      (item) => item.merchantId == merchantId && item.courierUid == courierUid,
    );

    final CourierRosterItem item;
    if (index >= 0) {
      item = CourierRosterItem(
        id: _items[index].id,
        courierUid: courierUid,
        merchantId: merchantId,
        isActive: true,
        attachedAt: DateTime.now(),
        name: name,
        phone: phone,
        pausedUntil: pausedUntil,
      );
      _items[index] = item;
    } else {
      item = CourierRosterItem(
        id: 'cm-${_items.length + 1}',
        courierUid: courierUid,
        merchantId: merchantId,
        isActive: true,
        attachedAt: DateTime.now(),
        name: name,
        phone: phone,
        pausedUntil: pausedUntil,
      );
      _items.add(item);
    }

    _notify();
    return Result.ok(item);
  }

  @override
  Future<Result<void>> detachCourier({
    required String merchantId,
    required String courierUid,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (detachFailure != null) return Result.err(detachFailure!);

    final index = _items.indexWhere(
      (item) => item.merchantId == merchantId && item.courierUid == courierUid,
    );
    if (index < 0) return const Result.err(NotFoundFailure());

    final existing = _items[index];
    _items[index] = CourierRosterItem(
      id: existing.id,
      courierUid: existing.courierUid,
      merchantId: existing.merchantId,
      isActive: false,
      attachedAt: existing.attachedAt,
      name: existing.name,
      phone: existing.phone,
      pausedUntil: existing.pausedUntil,
    );

    _notify();
    return const Result.ok(null);
  }
}
