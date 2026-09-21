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

    /// Arrives approved rather than waiting in the queue. Only an admin's upload may: the
    /// `media` policies refuse an approved row from anybody else, so a merchant passing it
    /// is refused rather than trusted.
    bool approved,
  });

  /// Everything waiting for review, oldest first — a photo that has been waiting three
  /// days is the one holding a merchant up.
  Stream<List<Media>> watchPending();

  Future<Result<Media>> get(String id);

  /// Records a decision, and who made it.
  ///
  /// There is no `reviewedBy` parameter, for the reason `MediaPicker` has no
  /// `uploadedBy`: the server stamps it from `auth.uid()`, so there was only ever one
  /// correct value — and a parameter is somewhere a caller can put a different one. The
  /// fake stamps the identity it was built with, so a screen tested against it cannot
  /// pass a reviewer the server would refuse to believe.
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? note,
  });

  /// Whose each picture is — the shop, the dish or meal it shows, who uploaded it — for
  /// the moderation queue, in one call. Ids the server cannot name are simply absent.
  Future<Result<Map<String, MediaContext>>> contextOf(List<String> ids);
}

/// What the moderation card says about a picture besides the picture itself.
class MediaContext {
  const MediaContext({this.shop, this.item, this.uploader});

  final String? shop;
  final String? item;
  final String? uploader;
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
      model['createdAt'] = DateTime.parse(
        model['createdAt'] as String,
      ).toLocal();
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
    bool approved = false,
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
        final row = await _db
            .from('media')
            .insert({
              'kind': kind.name,
              'url': storage.getPublicUrl(path),
              'status':
                  (approved ? MediaStatus.approved : MediaStatus.pending).name,
              'uploaded_by': uploadedBy,
              'owner_id': _uuidOrNull(ownerId),
              'width': width,
              'height': height,
            })
            .select()
            .single();
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
  Future<Result<Map<String, MediaContext>>> contextOf(List<String> ids) {
    return Result.guard(() async {
      if (ids.isEmpty) return const <String, MediaContext>{};
      final rows =
          await _db.rpc('admin_media_context', params: {'p_ids': ids}) as List;
      return {
        for (final row in rows.cast<Map<String, dynamic>>())
          row['media_id'] as String: MediaContext(
            shop: row['shop'] as String?,
            item: row['item'] as String?,
            uploader: row['uploader'] as String?,
          ),
      };
    });
  }

  @override
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? note,
  }) {
    return Result.guard(() async {
      // The RPC owns both halves: the decision and its evidence. The reviewer is never
      // sent — the server takes it from `auth.uid()`, so nobody can sign somebody else's
      // name to a rejection. An empty note is no note.
      final reviewNote = (note == null || note.isEmpty) ? null : note;
      await _db.rpc(
        'admin_review_media',
        params: {'p_id': id, 'p_status': status.name, 'p_note': reviewNote},
      );
    });
  }
}

/// In-memory media, for tests and for building screens before anyone uploads anything.
class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({
    List<Media> seed = const [],
    this.failure,

    /// Who the fake believes is signed in. Stamped onto a decision the way the server
    /// stamps `auth.uid()`, so «who reviewed this» is still answerable in a widget test
    /// without a caller being able to name somebody else.
    this.signedInUid,
  }) : _media = {for (final m in seed) m.id: m};

  final String? signedInUid;

  final Map<String, Media> _media;
  Failure? failure;

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
    bool approved = false,
  }) async {
    if (failure != null) return Result.err(failure!);

    _counter++;
    final media = Media(
      id: 'fake-media-$_counter',
      kind: kind,
      // Distinct per upload, like the real one: a screen that shows two photos must not
      // be handed one URL twice and pass.
      url: 'https://fake.luqma/${kind.name}/$_counter.jpg',
      status: approved ? MediaStatus.approved : MediaStatus.pending,
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

  /// What [contextOf] answers, keyed by media id. Seeded by a test.
  final contexts = <String, MediaContext>{};

  @override
  Future<Result<Map<String, MediaContext>>> contextOf(List<String> ids) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok({
      for (final id in ids)
        if (contexts[id] != null) id: contexts[id]!,
    });
  }

  @override
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? note,
  }) async {
    if (failure != null) return Result.err(failure!);
    final media = _media[id];
    if (media == null) return const Result.err(NotFoundFailure());
    _media[id] = media.copyWith(
      status: status,
      reviewedBy: signedInUid ?? media.reviewedBy,
      reviewNote: note ?? media.reviewNote,
    );
    return const Result.ok(null);
  }
}
