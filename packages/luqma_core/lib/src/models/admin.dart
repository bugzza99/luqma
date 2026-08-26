import '../data/column_names.dart';

/// A customer, as AdminApp sees them.
///
/// Not a `freezed` model, and deliberately missing what the customer app writes: this is
/// a *read* of a person for support and moderation. The two fields an admin may move —
/// `isBlocked` and the refusal count — go through server functions, never through a
/// model's `toJson`, because a client that could serialize them could also forge them.
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.isBlocked,
    required this.rejectedOrdersCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;

  /// Blocked customers fail at sign-in; the flag is the whole mechanism.
  final bool isBlocked;

  /// Orders refused after being accepted. Grown by the server when a merchant rejects.
  final int rejectedOrdersCount;

  final DateTime? createdAt;

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    isBlocked: json['isBlocked'] as bool? ?? false,
    rejectedOrdersCount: (json['rejectedOrdersCount'] as num?)?.toInt() ?? 0,
    createdAt: switch (json['createdAt']) {
      null => null,
      String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    },
  );

  static CustomerSummary fromRow(Map<String, dynamic> row) =>
      CustomerSummary.fromJson(ColumnNames.toModel(row));
}

/// One ticket raised from the customer app about one order.
///
/// Read-mostly by design: the customer raises it, and the only thing an admin ever
/// writes back is the note and the close. Modelling the whole row as writable would
/// invite editing somebody's complaint before answering it.
class OrderIssue {
  const OrderIssue({
    required this.id,
    required this.orderId,
    required this.customerUid,
    required this.merchantId,
    required this.reason,
    required this.status,
    this.adminNote,
    this.createdAt,
    this.updatedAt,
  });

  static const open = 'open';
  static const closed = 'closed';

  final String id;
  final String orderId;
  final String customerUid;
  final String merchantId;

  /// What the customer typed. Never edited by anyone.
  final String reason;

  /// [open] or [closed] — the database checks both spellings.
  final String status;
  final String? adminNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => status == open;

  factory OrderIssue.fromJson(Map<String, dynamic> json) => OrderIssue(
    id: json['id'] as String,
    orderId: json['orderId'] as String,
    customerUid: json['customerUid'] as String,
    merchantId: json['merchantId'] as String,
    reason: json['reason'] as String,
    status: json['status'] as String,
    adminNote: json['adminNote'] as String?,
    createdAt: switch (json['createdAt']) {
      null => null,
      String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    },
    updatedAt: switch (json['updatedAt']) {
      null => null,
      String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    },
  );

  static OrderIssue fromRow(Map<String, dynamic> row) =>
      OrderIssue.fromJson(ColumnNames.toModel(row));
}

/// One staff account — platform or bound to one shop.
class StaffMember {
  const StaffMember({
    required this.uid,
    required this.scope,
    required this.role,
    required this.isActive,
    this.merchantId,
    this.name,
    this.phone,
  });

  final String uid;

  /// 'platform' or 'merchant' — the database checks both spellings.
  final String scope;

  /// 'admin', 'moderator', 'owner' or 'courier'.
  final String role;
  final String? merchantId;
  final String? name;
  final String? phone;
  final bool isActive;

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    uid: json['uid'] as String,
    scope: json['scope'] as String,
    role: json['role'] as String,
    merchantId: json['merchantId'] as String?,
    name: json['name'] as String?,
    phone: json['phone'] as String?,
    isActive: json['isActive'] as bool? ?? true,
  );

  static StaffMember fromRow(Map<String, dynamic> row) =>
      StaffMember.fromJson(ColumnNames.toModel(row));
}
