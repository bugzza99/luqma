/// The identity papers somebody handed in to carry food and cash.
///
/// Three photographs — national ID front, ID back, and a selfie holding the ID — stored
/// in the private `staff-docs` bucket and keyed on the *person*, not on the application
/// they were handed in with. That is the whole design: an applicant owns their uid before
/// they apply and keeps it when approval makes them staff, so the papers never belong to
/// a row that might be deleted out from under them.
///
/// Nothing here is a URL. The bucket is private, so a path becomes viewable only by
/// asking for a signed link that expires — see `StaffDocumentsRepository.signedUrl`.
class StaffDocuments {
  const StaffDocuments({
    required this.uid,
    required this.idFrontPath,
    required this.idBackPath,
    required this.selfiePath,
    required this.uploadedAt,
    this.purgeAfter,
  });

  factory StaffDocuments.fromRow(Map<String, dynamic> row) => StaffDocuments(
        uid: row['uid'] as String,
        idFrontPath: row['id_front_path'] as String,
        idBackPath: row['id_back_path'] as String,
        selfiePath: row['selfie_path'] as String,
        uploadedAt: DateTime.parse(row['uploaded_at'] as String).toLocal(),
        purgeAfter: switch (row['purge_after']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
      );

  /// The person these belong to. Their `auth.users` id, and their `staff.uid` if they
  /// are approved.
  final String uid;

  final String idFrontPath;
  final String idBackPath;
  final String selfiePath;

  final DateTime uploadedAt;

  /// When these papers will be deleted, or null while they are being kept.
  ///
  /// Null means the person is working or is waiting to hear. Anything else is a countdown
  /// the database started and only the database can stop: `staff_documents` grants no
  /// write to anybody, because a retention rule the person it counts down for can edit is
  /// not a rule.
  final DateTime? purgeAfter;

  /// The three paths in the order a reviewer should be shown them.
  List<String> get paths => [idFrontPath, idBackPath, selfiePath];

  /// True while these papers are counting down to deletion.
  bool isExpiringAt(DateTime now) => purgeAfter != null;

  /// Whole days left before deletion, or null when they are being kept.
  ///
  /// Rounded up, because "0 days left" on papers that still exist reads as a bug. A
  /// countdown already past its end returns 0.
  int? daysLeftAt(DateTime now) {
    final at = purgeAfter;
    if (at == null) return null;
    final left = at.difference(now);
    if (left.isNegative) return 0;
    return left.inSeconds ~/ Duration.secondsPerDay +
        (left.inSeconds % Duration.secondsPerDay == 0 ? 0 : 1);
  }
}
