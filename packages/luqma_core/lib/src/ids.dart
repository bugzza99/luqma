import 'dart:math';

/// A v4 uuid, from the platform's secure generator.
///
/// One copy, because there were two — `SupabaseMediaRepository` and
/// `SupabaseStaffDocumentsRepository` each carried a private `_uuid()`, and a third was
/// about to be written for the merchant form. Identical code in three places is three
/// places to fix the day one of them turns out to be wrong.
///
/// `Random.secure()` rather than `Random()`: these become storage paths and primary keys,
/// and a predictable one is a path somebody else can guess at.
///
/// It is not a random string. The version and variant bits are set, so what comes out is
/// a uuid Postgres will accept in a `uuid` column rather than reject at the boundary.
String luqmaUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}
