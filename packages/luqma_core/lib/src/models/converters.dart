import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

/// Firestore hands dates back as [Timestamp], which `json_serializable` knows nothing
/// about. Without this every date field would arrive as a type error at runtime — and
/// the one that matters most is `pausedUntil`, where the failure mode is a merchant
/// that never reopens.
///
/// Reads are lenient because the same documents are written by Cloud Functions, by the
/// Firestore console, and by seed scripts, which do not all produce a [Timestamp].
/// Writes are strict: always a [Timestamp], so queries and ordering work.
class TimestampConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampConverter();

  @override
  DateTime? fromJson(Object? json) {
    return switch (json) {
      null => null,
      Timestamp() => json.toDate(),
      DateTime() => json,
      int() => DateTime.fromMillisecondsSinceEpoch(json),
      String() => DateTime.tryParse(json),
      _ => null,
    };
  }

  @override
  Object? toJson(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);
}
