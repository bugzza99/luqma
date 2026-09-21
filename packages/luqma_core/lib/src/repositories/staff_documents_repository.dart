import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/staff_documents.dart';
import '../result.dart';

/// A courier's identity papers: handing them in, and an admin looking at them.
///
/// The bucket is private, unlike `media`. A menu photograph is public by design and what
/// keeps an unapproved one out of the product is its `media` row; a national ID is not
/// something a uuid in a path is allowed to be the only guard on. So nothing here returns
/// a URL — a path becomes viewable by asking for a signed link that expires, and only for
/// somebody the policy already lets read the object.
///
/// **When the papers go is the database's decision** (`purge_after`, one writer, a nightly
/// sweep), not a screen's: a courier who could delete their own papers could also delete
/// them the morning a dispute started. So there is no delete a courier can reach, and
/// [removeFor] is an admin's act with a reason attached — see its own comment.
abstract interface class StaffDocumentsRepository {
  /// Uploads the three photographs and files them against the signed-in person.
  ///
  /// Three or none. A set with a missing selfie is not a weaker set — it is an
  /// application the owner cannot act on — so the server refuses a partial one and this
  /// does not offer a way to send it.
  ///
  /// [idFront], [idBack] and [selfie] should already be downscaled; see `ImageCompressor`.
  Future<Result<StaffDocuments>> handIn({
    required Uint8List idFront,
    required Uint8List idBack,
    required Uint8List selfie,
  });

  /// The signed-in person's own papers, or null when they have handed none in.
  Future<Result<StaffDocuments?>> mine();

  /// One person's papers, for the admin reviewing their application.
  ///
  /// Returns null when there are none — which an admin needs to be able to tell from a
  /// refusal, because "this applicant has uploaded nothing" is a thing to say on the
  /// telephone and "you may not look" is a bug.
  Future<Result<StaffDocuments?>> forPerson(String uid);

  /// A link to one photograph that stops working after [expiresIn].
  ///
  /// Short by default: the link is for the seconds it takes to look at the picture, and a
  /// long-lived one for a national ID is a public URL with extra steps.
  Future<Result<String>> signedUrl(String path, {Duration expiresIn});

  /// An admin removes somebody's papers, saying why.
  ///
  /// All three, because a row means three photographs on file and the approval guard asks
  /// whether the row exists — there is no state in the product for two. So this is what an
  /// admin does when a photograph is of the wrong thing, of somebody else, or of something
  /// that should not be stored: the papers are not acceptable and are handed in again.
  ///
  /// [reason] is required by the server, not merely by this signature. The audit row exists
  /// to answer «why are this courier's papers gone», and one that may be blank does not.
  Future<Result<void>> removeFor(String uid, {required String reason});
}

class SupabaseStaffDocumentsRepository implements StaffDocumentsRepository {
  SupabaseStaffDocumentsRepository(this._db);

  final SupabaseClient _db;

  static const _bucket = 'staff-docs';
  static const _table = 'staff_documents';

  @override
  Future<Result<StaffDocuments>> handIn({
    required Uint8List idFront,
    required Uint8List idBack,
    required Uint8List selfie,
  }) {
    return Result.guard(() async {
      // Read here rather than taken as a parameter. The storage policy compares the first
      // path segment to `auth.uid()` and `set_my_staff_documents` checks it again, so
      // there has only ever been one correct value — and a parameter is somewhere a
      // caller can put a different one. The same reasoning as `MediaPicker`'s
      // `uploadedBy`, reached from the other side.
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw const PermissionFailure();

      final storage = _db.storage.from(_bucket);
      final written = <String>[];

      try {
        Future<String> put(String slot, Uint8List bytes) async {
          // A uuid rather than a fixed name per slot, so replacing a bad photograph
          // cannot leave a reviewer looking at a cached copy of the old one.
          final path = '$uid/$slot-${_uuid()}.jpg';
          await storage.uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
          written.add(path);
          return path;
        }

        final front = await put('id-front', idFront);
        final back = await put('id-back', idBack);
        final face = await put('selfie', selfie);

        final row = await _db.rpc('set_my_staff_documents', params: {
          'p_id_front': front,
          'p_id_back': back,
          'p_selfie': face,
        });

        return StaffDocuments.fromRow(
          (row is List ? row.first : row) as Map<String, dynamic>,
        );
      } catch (_) {
        // The row is what the admin's queue reads and what retention counts down on.
        // Bytes with no row are reachable by nobody and swept by nothing here, so the
        // hand-in undoes itself rather than leaving a stranger's ID in the bucket for
        // ever. Best effort: a failure to clean up must not replace the real error.
        if (written.isNotEmpty) {
          try {
            await _db.storage.from(_bucket).remove(written);
          } catch (_) {
            // Swallowed on purpose — see above.
          }
        }
        rethrow;
      }
    });
  }

  @override
  Future<Result<StaffDocuments?>> mine() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return Future.value(const Err(PermissionFailure()));
    return forPerson(uid);
  }

  @override
  Future<Result<StaffDocuments?>> forPerson(String uid) {
    return Result.guard(() async {
      // `maybeSingle`, because no papers is an ordinary answer here and `single` would
      // turn it into an error the screen would have to translate back.
      final row = await _db.from(_table).select().eq('uid', uid).maybeSingle();
      return row == null ? null : StaffDocuments.fromRow(row);
    });
  }

  @override
  Future<Result<String>> signedUrl(
    String path, {
    Duration expiresIn = const Duration(minutes: 5),
  }) {
    return Result.guard(
      () => _db.storage.from(_bucket).createSignedUrl(path, expiresIn.inSeconds),
    );
  }

  @override
  Future<Result<void>> removeFor(String uid, {required String reason}) {
    // An RPC rather than a delete against storage, and the storage policy no longer
    // grants an admin one (`20261025000000`). The bytes, the row and the audit entry move
    // together or not at all, which a client making two calls cannot promise.
    return Result.guard(
      () => _db.rpc<void>(
        'admin_delete_staff_documents',
        params: {'p_uid': uid, 'p_reason': reason},
      ),
    );
  }

  /// A v4 uuid, from the same generator `SupabaseMediaRepository` uses.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// In-memory papers, for widget tests and for the apps running against fakes.
///
/// It is deliberately *not* more permissive than the database on the one rule that
/// matters: there is no way to clear `purgeAfter` from here either, because the fakes
/// being more permissive than Postgres plus the policies is how this repository's
/// predecessor shipped a feature nobody could use.
class FakeStaffDocumentsRepository implements StaffDocumentsRepository {
  FakeStaffDocumentsRepository({
    String? signedInUid,
    Map<String, StaffDocuments>? seed,
  })  : _uid = signedInUid,
        _byUid = {...?seed};

  final String? _uid;
  final Map<String, StaffDocuments> _byUid;

  /// Set to make the next call fail, the way the real one does when the line drops.
  Failure? failWith;

  /// Whoever is not [_uid] and is not in [readable] sees nothing, the way RLS decides it.
  final Set<String> readable = {};

  int handIns = 0;

  @override
  Future<Result<StaffDocuments>> handIn({
    required Uint8List idFront,
    required Uint8List idBack,
    required Uint8List selfie,
  }) async {
    if (failWith case final failure?) return Err(failure);
    final uid = _uid;
    if (uid == null) return const Err(PermissionFailure());

    handIns++;
    final now = DateTime.now();
    final papers = StaffDocuments(
      uid: uid,
      idFrontPath: '$uid/id-front.jpg',
      idBackPath: '$uid/id-back.jpg',
      selfiePath: '$uid/selfie.jpg',
      uploadedAt: now,
      // Carried over, never restarted and never cleared.
      //
      // The database decides retention from things this fake cannot see — whether there
      // is a pending application, whether there is an active staff row — so it does not
      // pretend to compute it. What it does guarantee is the half a screen can get
      // wrong: handing papers in again does not buy a reprieve, so no widget test here
      // can pass while promising one. A test that needs a clock already running seeds it.
      purgeAfter: _byUid[uid]?.purgeAfter,
    );
    _byUid[uid] = papers;
    return Ok(papers);
  }

  @override
  Future<Result<StaffDocuments?>> mine() async {
    if (failWith case final failure?) return Err(failure);
    final uid = _uid;
    if (uid == null) return const Err(PermissionFailure());
    return Ok(_byUid[uid]);
  }

  @override
  Future<Result<StaffDocuments?>> forPerson(String uid) async {
    if (failWith case final failure?) return Err(failure);
    if (uid != _uid && !readable.contains(uid)) return const Ok(null);
    return Ok(_byUid[uid]);
  }

  @override
  Future<Result<String>> signedUrl(
    String path, {
    Duration expiresIn = const Duration(minutes: 5),
  }) async {
    if (failWith case final failure?) return Err(failure);
    return Ok('https://example.test/signed/$path?expires=${expiresIn.inSeconds}');
  }

  /// What was removed and why, so a test can assert the reason reached the server.
  final removals = <({String uid, String reason})>[];

  @override
  Future<Result<void>> removeFor(String uid, {required String reason}) async {
    if (failWith case final failure?) return Err(failure);
    // The server requires a reason and refuses a blank one. A fake that accepted one
    // would let a screen ship a control the database will refuse.
    if (reason.trim().isEmpty) return const Err(ValidationFailure());
    if (!_byUid.containsKey(uid)) return const Err(NotFoundFailure());
    _byUid.remove(uid);
    removals.add((uid: uid, reason: reason));
    return const Ok(null);
  }
}
