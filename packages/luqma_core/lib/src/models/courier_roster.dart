import 'admin.dart';

/// One attachment of a courier to a merchant's roster.
///
/// Models the `courier_merchants` join table, augmented with the rider's name, phone,
/// and availability from `staff`.
class CourierRosterItem {
  const CourierRosterItem({
    required this.id,
    required this.courierUid,
    required this.merchantId,
    required this.isActive,
    this.attachedAt,
    this.name,
    this.phone,
    this.pausedUntil,
  });

  final String id;
  final String courierUid;
  final String? merchantId;
  final bool isActive;
  final DateTime? attachedAt;
  final String? name;
  final String? phone;
  final DateTime? pausedUntil;

  /// Derived: null or in the past means available.
  ///
  /// Evaluated through [StaffMember.isAvailableAt] — never recomputed at a call site,
  /// so a courier's availability is judged identically across all three apps.
  bool isAvailableAt(DateTime time) => StaffMember(
        uid: courierUid,
        scope: 'merchant',
        role: 'courier',
        isActive: isActive,
        pausedUntil: pausedUntil,
      ).isAvailableAt(time);

  factory CourierRosterItem.fromJson(Map<String, dynamic> json) =>
      CourierRosterItem(
        id: json['id'] as String,
        courierUid: (json['courierUid'] ?? json['courier_uid']) as String,
        merchantId: (json['merchantId'] ?? json['merchant_id']) as String?,
        isActive: (json['isActive'] ?? json['is_active']) as bool? ?? true,
        attachedAt: switch (json['attachedAt'] ?? json['attached_at']) {
          null => null,
          String s => DateTime.tryParse(s)?.toLocal(),
          DateTime d => d,
          _ => null,
        },
        name: json['name'] as String?,
        phone: json['phone'] as String?,
        pausedUntil: switch (json['pausedUntil'] ?? json['paused_until']) {
          null => null,
          String s => DateTime.tryParse(s)?.toLocal(),
          DateTime d => d,
          _ => null,
        },
      );

  factory CourierRosterItem.fromRow(Map<String, dynamic> row) {
    final staff = row['staff'] is Map<String, dynamic>
        ? row['staff'] as Map<String, dynamic>
        : (row['courier'] is Map<String, dynamic>
            ? row['courier'] as Map<String, dynamic>
            : null);

    return CourierRosterItem(
      id: row['id'] as String,
      courierUid: (row['courier_uid'] ?? row['courierUid']) as String,
      merchantId: (row['merchant_id'] ?? row['merchantId']) as String?,
      isActive: (row['is_active'] ?? row['isActive']) as bool? ?? true,
      attachedAt: switch (row['attached_at'] ?? row['attachedAt']) {
        null => null,
        String s => DateTime.tryParse(s)?.toLocal(),
        DateTime d => d,
        _ => null,
      },
      name: (staff?['name'] ?? row['name']) as String?,
      phone: (staff?['phone'] ?? row['phone']) as String?,
      pausedUntil: switch (staff?['paused_until'] ??
          row['paused_until'] ??
          row['pausedUntil']) {
        null => null,
        String s => DateTime.tryParse(s)?.toLocal(),
        DateTime d => d,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courierUid': courierUid,
        'merchantId': merchantId,
        'isActive': isActive,
        'attachedAt': attachedAt?.toUtc().toIso8601String(),
        'name': name,
        'phone': phone,
        'pausedUntil': pausedUntil?.toUtc().toIso8601String(),
      };
}
