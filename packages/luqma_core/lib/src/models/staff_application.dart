import '../data/column_names.dart';

/// Which role an applicant is asking to join as.
///
/// Answered by the first question on the way-in screen: courier, restaurant, or home kitchen.
enum StaffApplicationKind {
  courier,
  restaurant,
  homeKitchen;

  static StaffApplicationKind fromString(String value) => switch (value) {
        'courier' => StaffApplicationKind.courier,
        'restaurant' => StaffApplicationKind.restaurant,
        'homeKitchen' => StaffApplicationKind.homeKitchen,
        _ => throw ArgumentError.value(
            value, 'kind', 'unknown staff application kind'),
      };
}

/// The decision state of an application.
///
/// An application arrives `pending` and moves to `approved` or `rejected`.
enum StaffApplicationStatus {
  pending,
  approved,
  rejected;

  static StaffApplicationStatus fromString(String value) => switch (value) {
        'pending' => StaffApplicationStatus.pending,
        'approved' => StaffApplicationStatus.approved,
        'rejected' => StaffApplicationStatus.rejected,
        _ => throw ArgumentError.value(
            value, 'status', 'unknown staff application status'),
      };
}

/// Somebody asking to join as a courier, restaurant, or home kitchen.
///
/// Carries no privileges and is joined to by nothing in the security boundary. The owner
/// reads it in AdminApp, telephones the applicant, and records a decision. Approval marks
/// the application decided; the actual account is created through the staff screen.
class StaffApplication {
  const StaffApplication({
    required this.id,
    required this.kind,
    required this.name,
    required this.phone,
    this.note,
    this.status = StaffApplicationStatus.pending,
    this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewNote,
    this.staffUid,
  });

  final String id;
  final StaffApplicationKind kind;
  final String name;
  final String phone;

  /// What the person typed about themselves: covered areas for a courier, shop location
  /// and hours for a merchant.
  final String? note;

  final StaffApplicationStatus status;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? reviewNote;

  /// Set on approval when linked to what it became, null otherwise.
  final String? staffUid;

  bool get isPending => status == StaffApplicationStatus.pending;
  bool get isApproved => status == StaffApplicationStatus.approved;
  bool get isRejected => status == StaffApplicationStatus.rejected;

  factory StaffApplication.fromJson(Map<String, dynamic> json) => StaffApplication(
        id: json['id'] as String,
        kind: StaffApplicationKind.fromString(json['kind'] as String),
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        note: json['note'] as String?,
        status: json['status'] != null
            ? StaffApplicationStatus.fromString(json['status'] as String)
            : StaffApplicationStatus.pending,
        createdAt: switch (json['createdAt']) {
          null => null,
          String s => DateTime.tryParse(s)?.toLocal(),
          _ => null,
        },
        reviewedAt: switch (json['reviewedAt']) {
          null => null,
          String s => DateTime.tryParse(s)?.toLocal(),
          _ => null,
        },
        reviewedBy: json['reviewedBy'] as String?,
        reviewNote: json['reviewNote'] as String?,
        staffUid: json['staffUid'] as String?,
      );

  static StaffApplication fromRow(Map<String, dynamic> row) =>
      StaffApplication.fromJson(ColumnNames.toModel(row));
}
