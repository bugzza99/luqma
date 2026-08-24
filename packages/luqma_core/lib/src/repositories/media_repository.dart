import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/media.dart';
import '../result.dart';

/// The moderation queue and the decisions taken on it.
abstract interface class MediaRepository {
  /// Everything waiting for review, oldest first — a photo that has been waiting three
  /// days is the one holding a merchant up.
  Stream<List<Media>> watchPending();

  Future<Result<Media>> get(String id);

  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? reviewedBy,
    String? note,
  });
}

class SupabaseMediaRepository implements MediaRepository {
  SupabaseMediaRepository(this._db);

  final SupabaseClient _db;

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  Media _toMedia(Map<String, dynamic> row) {
    final model = ColumnNames.toModel(row);
    // Local, like Firestore's Timestamp.toDate() handed back: Dart's DateTime equality
    // insists on the same zone, not merely the same moment.
    if (model['createdAt'] is String) {
      model['createdAt'] = DateTime.parse(model['createdAt'] as String).toLocal();
    }
    return Media.fromJson(model);
  }

  @override
  Stream<List<Media>> watchPending() {
    return watchRows(
      db: _db,
      table: 'media',
      map: _toMedia,
      filters: [RowFilter('status', MediaStatus.pending.name)],
      // Oldest first: a photo that has been waiting three days is the one holding a
      // merchant up.
      orderBy: 'created_at',
    );
  }

  @override
  Future<Result<Media>> get(String id) {
    return Result.guard(() async {
      final row = await _db.from('media').select().eq('id', id).maybeSingle();
      if (row == null) throw const NotFoundFailure();
      return _toMedia(row);
    });
  }

  @override
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? reviewedBy,
    String? note,
  }) {
    return Result.guard(() {
      // Recorded even when there is no note: knowing a decision was made, and by whom,
      // is what separates "reviewed and refused" from "nobody has looked yet". An empty
      // note is no note.
      final reviewNote = (note == null || note.isEmpty) ? null : note;
      return _db.from('media').update({
        'status': status.name,
        'reviewed_by': _uuidOrNull(reviewedBy),
        'review_note': reviewNote,
      }).eq('id', id);
    });
  }
}

/// In-memory media, for tests and for building screens before anyone uploads anything.
class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({List<Media> seed = const [], this.failure})
      : _media = {for (final m in seed) m.id: m};

  final Map<String, Media> _media;
  final Failure? failure;

  @override
  Stream<List<Media>> watchPending() {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _media.values.where((m) => m.status == MediaStatus.pending).toList(),
    );
  }

  @override
  Future<Result<Media>> get(String id) async {
    if (failure != null) return Result.err(failure!);
    final media = _media[id];
    if (media == null) return const Result.err(NotFoundFailure());
    return Result.ok(media);
  }

  @override
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? reviewedBy,
    String? note,
  }) async {
    if (failure != null) return Result.err(failure!);
    final media = _media[id];
    if (media == null) return const Result.err(NotFoundFailure());
    _media[id] = media.copyWith(
      status: status,
      reviewedBy: reviewedBy ?? media.reviewedBy,
      reviewNote: note ?? media.reviewNote,
    );
    return const Result.ok(null);
  }
}
