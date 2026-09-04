import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/media.dart';
import '../result.dart';

/// Getting an image in, and the moderation queue that decides whether it is ever seen.
abstract interface class MediaRepository {
  /// Stores [bytes] and files the `media` row that makes them reviewable.
  ///
  /// Two writes that have to agree: the object in Storage, and the row. The row is what
  /// the whole product reads — a URL with no row is invisible everywhere and would be
  /// swept away as an orphan, so this cleans up after itself when the second write
  /// fails rather than leaving bytes nobody can reach or delete.
  ///
  /// [bytes] should already be downscaled; see `ImageCompressor`. The bucket refuses
  /// anything over 2 MiB, which is a backstop against a caller that forgot, not the
  /// working size.
  Future<Result<Media>> upload({
    required MediaKind kind,
    required Uint8List bytes,
    required String uploadedBy,
    String? ownerId,
    int width,
    int height,
  });

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
  Future<Result<Media>> upload({
    required MediaKind kind,
    required Uint8List bytes,
    required String uploadedBy,
    String? ownerId,
    int width = 0,
    int height = 0,
  }) {
    return Result.guard(() async {
      final storage = _db.storage.from(_bucket);
      // A uuid, not the file name somebody's phone chose. Two uploads of one picture are
      // two images, and a shared path would mean approving one photo silently approves
      // another merchant's — while `DSC_0001.jpg` from two phones is one collision.
      //
      // The uploader's id leads, because `media_upload` requires it to: the bucket is
      // public, so without a prefix any signed-in customer could write any name in it.
      // The policy compares the first segment to `auth.uid()`, which means a caller that
      // passes somebody else's `uploadedBy` is refused here rather than one statement
      // later at the row — the same refusal, arriving before the bytes are stored.
      final path = '$uploadedBy/${kind.name}/${_uuid()}.jpg';

      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

      try {
        final row = await _db.from('media').insert({
          'kind': kind.name,
          'url': storage.getPublicUrl(path),
          'status': MediaStatus.pending.name,
          'uploaded_by': uploadedBy,
          'owner_id': _uuidOrNull(ownerId),
          'width': width,
          'height': height,
        }).select().single();
        return _toMedia(row);
      } catch (_) {
        // The row is what everything reads. Bytes with no row are invisible to the
        // product and to the admin, and only the nightly sweep would ever find them —
        // so the upload undoes itself rather than leaving that behind.
        await storage.remove([path]);
        rethrow;
      }
    });
  }

  static const _bucket = 'media';

  /// A v4 uuid, from the same generator the database uses for everything else.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
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
    return Result.guardWrite(() {
      // Recorded even when there is no note: knowing a decision was made, and by whom,
      // is what separates "reviewed and refused" from "nobody has looked yet". An empty
      // note is no note.
      final reviewNote = (note == null || note.isEmpty) ? null : note;
      return _db.from('media').update({
        'status': status.name,
        'reviewed_by': _uuidOrNull(reviewedBy),
        'review_note': reviewNote,
      }).eq('id', id).select('id');
    }, (_) {});
  }
}

/// In-memory media, for tests and for building screens before anyone uploads anything.
class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({List<Media> seed = const [], this.failure})
      : _media = {for (final m in seed) m.id: m};

  final Map<String, Media> _media;
  final Failure? failure;

  /// What was uploaded, in order, for assertions.
  final List<Media> uploads = [];

  var _counter = 0;

  @override
  Future<Result<Media>> upload({
    required MediaKind kind,
    required Uint8List bytes,
    required String uploadedBy,
    String? ownerId,
    int width = 0,
    int height = 0,
  }) async {
    if (failure != null) return Result.err(failure!);

    _counter++;
    final media = Media(
      id: 'fake-media-$_counter',
      kind: kind,
      // Distinct per upload, like the real one: a screen that shows two photos must not
      // be handed one URL twice and pass.
      url: 'https://fake.luqma/${kind.name}/$_counter.jpg',
      status: MediaStatus.pending,
      ownerId: ownerId,
      uploadedBy: uploadedBy,
      width: width,
      height: height,
      bytes: bytes.length,
    );
    _media[media.id] = media;
    uploads.add(media);
    return Result.ok(media);
  }

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
