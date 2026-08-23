import 'package:cloud_firestore/cloud_firestore.dart';

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

class FirestoreMediaRepository implements MediaRepository {
  FirestoreMediaRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _media =>
      _firestore.collection('media');

  @override
  Stream<List<Media>> watchPending() {
    return _media
        .where('status', isEqualTo: MediaStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toMedia).toList()
          ..sort((a, b) {
            final left = a.createdAt;
            final right = b.createdAt;
            if (left == null || right == null) return 0;
            return left.compareTo(right);
          }));
  }

  @override
  Future<Result<Media>> get(String id) {
    return Result.guard(() async {
      final doc = await _media.doc(id).get();
      if (!doc.exists) throw const NotFoundFailure();
      return _toMedia(doc);
    });
  }

  @override
  Future<Result<void>> setStatus(
    String id,
    MediaStatus status, {
    String? reviewedBy,
    String? note,
  }) {
    return Result.guard(
      () => _media.doc(id).update({
        'status': status.name,
        // Recorded even when there is no note: knowing a decision was made, and by whom,
        // is what separates "reviewed and refused" from "nobody has looked yet".
        if (reviewedBy != null) 'reviewedBy': reviewedBy,
        if (note != null && note.isNotEmpty) 'reviewNote': note,
      }),
    );
  }

  Media _toMedia(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Media.fromJson({...doc.data()!, 'id': doc.id});
}

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
