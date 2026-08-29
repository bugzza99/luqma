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

/// The four numbers the owner opens AdminApp to see, in one server round trip.
///
/// Not `freezed`: read-only, computed by `admin_today`, and never written back. A model
/// with a `toJson` would invite a client to write what only the server should answer.
/// What is waiting for the admin, by module.
///
/// The AdminApp home is a grid of every module, and a grid of eleven identical tiles
/// answers the one question somebody opens this app with — "what needs me today?" — with
/// nothing at all. These are the numbers that turn that grid into a list of jobs.
///
/// Every one is a small filtered count. None is an aggregate over orders: `AdminToday`
/// owns those, and `docs/16` is explicit that counting must not mean reading every order
/// in the city.
class AdminAttention {
  const AdminAttention({
    this.pendingMedia = 0,
    this.openIssues = 0,
    this.requestedPromotions = 0,
    this.pendingMerchants = 0,
    this.ordersNeedingAttention = 0,
  });

  /// Photographs nobody has reviewed. Every one of them is a merchant waiting.
  final int pendingMedia;

  /// Tickets a customer raised that nobody has closed.
  final int openIssues;

  /// Campaigns a merchant asked for and nobody has answered. A merchant who paid for a
  /// placement and heard nothing is the loudest kind of unhappy.
  final int requestedPromotions;

  final int pendingMerchants;

  /// Orders that ran out their accept deadline. The escalator's queue.
  final int ordersNeedingAttention;

  factory AdminAttention.fromJson(Map<String, dynamic> json) {
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AdminAttention(
      pendingMedia: at('pendingMedia'),
      openIssues: at('openIssues'),
      requestedPromotions: at('requestedPromotions'),
      pendingMerchants: at('pendingMerchants'),
      ordersNeedingAttention: at('ordersNeedingAttention'),
    );
  }
}

class AdminToday {
  const AdminToday({
    required this.ordersToday,
    required this.moneyToday,
    required this.needsAttention,
    required this.openIssues,
  });

  /// Orders placed today that were not refused or cancelled.
  final int ordersToday;

  /// Piastres, and deliberately *not* counted on the same rule as [ordersToday].
  ///
  /// This is the cash that came in: orders actually handed over, dated by when they were
  /// handed over rather than by when they were placed. [ordersToday] answers a different
  /// question — how much was asked for today — so an order still on the stove is in one
  /// figure and not the other, and that is the point.
  ///
  /// The owner chose this reading. The alternative, the value of everything ordered, is
  /// highest at the moment the least is certain and falls through the evening as orders
  /// resolve, which reads as a bad night rather than as a number correcting itself.
  final int moneyToday;

  /// The escalator's queue: orders nobody answered in time.
  final List<NeedsAttentionItem> needsAttention;

  /// Tickets a customer has raised that nobody has closed.
  final int openIssues;

  factory AdminToday.fromJson(Map<String, dynamic> json) => AdminToday(
    ordersToday: (json['ordersToday'] as num?)?.toInt() ?? 0,
    moneyToday: (json['moneyToday'] as num?)?.toInt() ?? 0,
    needsAttention: [
      for (final item in (json['needsAttention'] as List? ?? const []))
        NeedsAttentionItem.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    openIssues: (json['openIssues'] as num?)?.toInt() ?? 0,
  );
}

/// One order waiting on the escalator's queue.
class NeedsAttentionItem {
  const NeedsAttentionItem({
    required this.id,
    required this.number,
    required this.merchantId,
    required this.merchantName,
  });

  final String id;
  final int number;
  final String merchantId;
  final String merchantName;

  factory NeedsAttentionItem.fromJson(Map<String, dynamic> json) =>
      NeedsAttentionItem(
    id: json['id'] as String,
    number: (json['number'] as num).toInt(),
    merchantId: json['merchantId'] as String,
    merchantName: json['merchantName'] as String? ?? '',
  );
}

/// Wider than a day: who is on the platform and how it is moving. Read-only.
class AdminStatistics {
  const AdminStatistics({
    required this.customers,
    required this.merchantsByStatus,
    required this.ordersTotal,
    required this.avgOrderValue,
    required this.byWeek,
    required this.byMonth,
  });

  final int customers;
  final Map<String, int> merchantsByStatus;
  final int ordersTotal;

  /// Piastres, averaged over every non-cancelled order.
  final int avgOrderValue;
  final List<SeriesPoint> byWeek;
  final List<SeriesPoint> byMonth;

  factory AdminStatistics.fromJson(Map<String, dynamic> json) => AdminStatistics(
    customers: (json['customers'] as num?)?.toInt() ?? 0,
    merchantsByStatus: {
      for (final entry
          in (json['merchantsByStatus'] as Map? ?? const {}).entries)
        entry.key as String: (entry.value as num).toInt(),
    },
    ordersTotal: (json['ordersTotal'] as num?)?.toInt() ?? 0,
    avgOrderValue: (json['avgOrderValue'] as num?)?.toInt() ?? 0,
    byWeek: [
      for (final item in (json['byWeek'] as List? ?? const []))
        SeriesPoint.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    byMonth: [
      for (final item in (json['byMonth'] as List? ?? const []))
        SeriesPoint.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
  );
}

/// One bucket in a growth series: a starting date and how many orders it covers.
class SeriesPoint {
  const SeriesPoint({required this.starting, required this.count});

  final DateTime starting;
  final int count;

  factory SeriesPoint.fromJson(Map<String, dynamic> json) => SeriesPoint(
    starting: DateTime.parse(json['starting'] as String).toLocal(),
    count: (json['count'] as num?)?.toInt() ?? 0,
  );
}
