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

  /// Watches all active merchant attachments for a specific courier.
  /// A null merchantId represents the platform row.
  Stream<List<CourierRosterItem>> watchCourierAttachments(String courierUid);

  /// Fetches all active merchant attachments for a specific courier.
  Future<Result<List<CourierRosterItem>>> getCourierAttachments(String courierUid);

  /// Attaches a courier to a shop, or to the platform if [merchantId] is null.
  /// If an inactive attachment already exists, re-activates it rather than duplicating.
  Future<Result<CourierRosterItem>> attachCourierToMerchant({
    required String courierUid,
    String? merchantId,
  });

  /// Detaches a courier from a shop, or from the platform if [merchantId] is null,
  /// by setting is_active = false.
  Future<Result<void>> detachCourierFromMerchant({
    required String courierUid,
    String? merchantId,
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

  @override
  Stream<List<CourierRosterItem>> watchCourierAttachments(String courierUid) {
    return watchRows(
      db: _db,
      table: 'courier_merchants',
      columns:
          'id, courier_uid, merchant_id, is_active, attached_at, merchants:merchant_id(name)',
      map: CourierRosterItem.fromRow,
      filters: [
        RowFilter('courier_uid', courierUid),
        RowFilter('is_active', 'true'),
      ],
      orderBy: 'attached_at',
      ascending: true,
    );
  }

  @override
  Future<Result<List<CourierRosterItem>>> getCourierAttachments(
    String courierUid,
  ) {
    return Result.guard(() async {
      final rows = await _db
          .from('courier_merchants')
          .select(
            'id, courier_uid, merchant_id, is_active, attached_at, merchants:merchant_id(name)',
          )
          .eq('courier_uid', courierUid)
          .eq('is_active', true)
          .order('attached_at', ascending: true);

      return [for (final row in rows) CourierRosterItem.fromRow(row)];
    });
  }

  @override
  Future<Result<CourierRosterItem>> attachCourierToMerchant({
    required String courierUid,
    String? merchantId,
  }) {
    return Result.guard(() async {
      var query = _db
          .from('courier_merchants')
          .select('id, is_active')
          .eq('courier_uid', courierUid);

      if (merchantId != null) {
        query = query.eq('merchant_id', merchantId);
      } else {
        query = query.filter('merchant_id', 'is', 'null');
      }

      final existing = await query.maybeSingle();

      final Map<String, dynamic> row;
      if (existing != null) {
        row = await _db
            .from('courier_merchants')
            // Who and when are stamped by the `courier_merchants_stamp` trigger from
            // `auth.uid()` and the server's clock. Sending them would be a claim the row
            // overwrites, and a line of code that looks like it decides something.
            .update({'is_active': true})
            .eq('id', existing['id'] as String)
            .select(
              'id, courier_uid, merchant_id, is_active, attached_at, merchants:merchant_id(name)',
            )
            .single();
      } else {
        row = await _db
            .from('courier_merchants')
            .insert({
              'courier_uid': courierUid,
              'merchant_id': merchantId,
              'is_active': true,
            })
            .select(
              'id, courier_uid, merchant_id, is_active, attached_at, merchants:merchant_id(name)',
            )
            .single();
      }

      return CourierRosterItem.fromRow(row);
    });
  }

  @override
  Future<Result<void>> detachCourierFromMerchant({
    required String courierUid,
    String? merchantId,
  }) {
    return Result.guardWrite(
      () {
        var query = _db
            .from('courier_merchants')
            .update({'is_active': false})
            .eq('courier_uid', courierUid);

        if (merchantId != null) {
          query = query.eq('merchant_id', merchantId);
        } else {
          query = query.filter('merchant_id', 'is', 'null');
        }

        return query.select('id');
      },
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
    this.actorRole = 'admin',
    this.actorMerchantId,
  })  : _items = List.of(seed),
        _staffByPhone = Map.of(staffByPhone ?? const {});

  final List<CourierRosterItem> _items;
  final Map<String, StaffMember> _staffByPhone;

  Failure? failure;
  Failure? attachFailure;
  Failure? detachFailure;

  /// Role of the actor calling the repository in tests ('admin', 'owner', etc.).
  /// Enforces policy boundary: owners cannot manage other shops or the platform row.
  String? actorRole;

  /// The shop the actor owns, when [actorRole] is 'owner'.
  String? actorMerchantId;

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
  Stream<List<CourierRosterItem>> watchCourierAttachments(String courierUid) {
    if (failure != null) return Stream.error(failure!);
    return _live(() => _items
        .where((item) => item.courierUid == courierUid && item.isActive)
        .toList());
  }

  @override
  Future<Result<List<CourierRosterItem>>> getCourierAttachments(
    String courierUid,
  ) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_items
        .where((item) => item.courierUid == courierUid && item.isActive)
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
    {
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

    final courierUid = staff.uid;
    final name = staff.name;
    final pausedUntil = staff.pausedUntil;

    final index = _items.indexWhere(
      (item) => item.merchantId == merchantId && item.courierUid == courierUid,
    );

    final CourierRosterItem item;
    if (index >= 0) {
      item = CourierRosterItem(
        id: _items[index].id,
        courierUid: courierUid,
        merchantId: merchantId,
        merchantName: _items[index].merchantName,
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
  Future<Result<CourierRosterItem>> attachCourierToMerchant({
    required String courierUid,
    String? merchantId,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (attachFailure != null) return Result.err(attachFailure!);

    // Policy check: owner cannot attach to another shop or to the platform
    if (actorRole == 'owner') {
      if (merchantId == null || merchantId != actorMerchantId) {
        return const Result.err(PermissionFailure());
      }
    } else if (actorRole != null && actorRole != 'admin') {
      return const Result.err(PermissionFailure());
    }

    final index = _items.indexWhere(
      (item) => item.courierUid == courierUid && item.merchantId == merchantId,
    );

    final CourierRosterItem item;
    if (index >= 0) {
      final existing = _items[index];
      item = CourierRosterItem(
        id: existing.id,
        courierUid: courierUid,
        merchantId: merchantId,
        merchantName: existing.merchantName,
        isActive: true,
        attachedAt: DateTime.now(),
        name: existing.name,
        phone: existing.phone,
        pausedUntil: existing.pausedUntil,
      );
      _items[index] = item;
    } else {
      item = CourierRosterItem(
        id: 'cm-${_items.length + 1}',
        courierUid: courierUid,
        merchantId: merchantId,
        isActive: true,
        attachedAt: DateTime.now(),
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
    return detachCourierFromMerchant(
      courierUid: courierUid,
      merchantId: merchantId,
    );
  }

  @override
  Future<Result<void>> detachCourierFromMerchant({
    required String courierUid,
    String? merchantId,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (detachFailure != null) return Result.err(detachFailure!);

    // Policy check: owner cannot detach from another shop or from the platform
    if (actorRole == 'owner') {
      if (merchantId == null || merchantId != actorMerchantId) {
        return const Result.err(PermissionFailure());
      }
    } else if (actorRole != null && actorRole != 'admin') {
      return const Result.err(PermissionFailure());
    }

    final index = _items.indexWhere(
      (item) => item.courierUid == courierUid && item.merchantId == merchantId,
    );
    if (index < 0) return const Result.err(NotFoundFailure());

    final existing = _items[index];
    _items[index] = CourierRosterItem(
      id: existing.id,
      courierUid: existing.courierUid,
      merchantId: existing.merchantId,
      merchantName: existing.merchantName,
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
