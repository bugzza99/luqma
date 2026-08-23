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

/// The same conversion for a date that must be there.
///
/// A separate class rather than a flag, because `json_serializable` matches a converter
/// by its exact type: a `JsonConverter<DateTime?, …>` is silently *not applied* to a
/// non-nullable `DateTime` field, which falls through to a raw cast and fails at run time
/// with "Timestamp is not a subtype of String". Nothing warns at build time.
///
/// A missing or unreadable value throws rather than guessing. These are dates a
/// subscription expires on; inventing one would either give away a month or take one.
class RequiredTimestampConverter implements JsonConverter<DateTime, Object?> {
  const RequiredTimestampConverter();

  @override
  DateTime fromJson(Object? json) {
    final date = const TimestampConverter().fromJson(json);
    if (date == null) {
      throw FormatException('Expected a date, got ${json.runtimeType}', json);
    }
    return date;
  }

  @override
  Object? toJson(DateTime value) => Timestamp.fromDate(value);
}
