import 'package:json_annotation/json_annotation.dart';

/// Dates travel as ISO 8601 strings.
///
/// Reads are lenient because the same rows are written by server functions, by seed
/// scripts and by the apps themselves, which do not all produce a [DateTime]. Writes
/// are strict: always UTC, so every timestamp lands in one zone.
class TimestampConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampConverter();

  @override
  DateTime? fromJson(Object? json) {
    return switch (json) {
      null => null,
      DateTime() => json,
      int() => DateTime.fromMillisecondsSinceEpoch(json),
      String() => DateTime.tryParse(json)?.toLocal(),
      _ => null,
    };
  }

  @override
  Object? toJson(DateTime? value) => value?.toUtc().toIso8601String();
}

/// The same conversion for a date that must be there.
///
/// A separate class rather than a flag, because `json_serializable` matches a converter
/// by its exact type: a `JsonConverter<DateTime?, …>` is silently *not applied* to a
/// non-nullable `DateTime` field, which falls through to a raw cast and fails at run
/// time. Nothing warns at build time.
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
  Object? toJson(DateTime value) => value.toUtc().toIso8601String();
}
