import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which money movement an attempt belongs to. Part of the key *and* part of the record,
/// so a stored attempt cannot be replayed as a different kind of payment.
enum PendingKind {
  /// Commission collected from a shop.
  merchant,

  /// Commission collected from a courier.
  courier,

  /// Credit added to a shop's prepaid wallet.
  topUp,

  /// A subscription term paid for.
  subscription;

  /// The key segment. `merchant` and `courier` keep the exact spellings the two
  /// collection screens have always written, so a pending attempt already sitting on an
  /// admin's phone is read back rather than lost — and losing it means collecting the
  /// same cash twice.
  String get slug => name;
}

/// A money movement that was sent, or is about to be, and whose reply has not been seen.
///
/// The receipt id and everything the server will be told are **one frozen record**,
/// written before the first request and never edited afterwards. That is the whole point
/// of the type, and it is a type rather than a handful of local variables because the
/// merchant collection learned the hard way what happens when they drift apart: a receipt
/// minted when the dialog opened and an amount read out of the box at every press meant a
/// retry could send the original receipt id with a new figure. The server, doing exactly
/// its job, answered with the first receipt and moved nothing — and the screen said
/// «اتسجّل ٢٠٠ ج». A false receipt in a cash business, produced by the path built to
/// prevent one.
///
/// The wallet top-up and the subscription payment had a weaker version of the same fault
/// and it was worse: they minted a receipt id **in memory only**, so a double tap, or the
/// app being killed between the request and its reply, produced a *new* id — and the
/// server's protection only refuses a repeat of the **same** id. The same cash could be
/// credited twice.
class PendingCollection {
  const PendingCollection({
    required this.receiptId,
    required this.kind,
    required this.subjectId,
    required this.amount,
    this.expectedBalance,
    this.planId,
    this.months,
  });

  /// Reads a stored record, or null when there is nothing readable to act on.
  ///
  /// Every field the server will be told has to be there and of the right type. The id is
  /// written first, so a half-written record would leave the id set and the rest missing —
  /// an editable field, no notice — and the next press would send new figures under the
  /// old receipt. That is the original bug's exact shape, reassembled out of a
  /// half-readable preference, so it is all or nothing.
  ///
  /// [kind] and [subjectId] are what the caller is *about* to do. A record that disagrees
  /// belongs to something else and is not returned: replaying a shop's top-up as a
  /// courier's collection would be one receipt paying for the wrong thing.
  static PendingCollection? decode(
    String? json, {
    required PendingKind kind,
    required String subjectId,
  }) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final receiptId = map['receiptId'];
      final amount = map['amount'];
      if (receiptId is! String || receiptId.isEmpty || amount is! int) {
        return null;
      }

      // Absent on a record written by the release that only knew about collections. Its
      // key already carried both, so an old record is trusted to be what its key says.
      final storedKind = map['kind'];
      final storedSubject = map['subject'];
      if (storedKind is String && storedKind != kind.slug) return null;
      if (storedSubject is String && storedSubject != subjectId) return null;

      final planId = map['planId'];
      final months = map['months'];
      final expectedBalance = map['expectedBalance'];
      // A subscription is a term on a plan. An attempt missing either is one the server
      // cannot be told about, so it is not a record — it is a corrupt one.
      if (kind == PendingKind.subscription &&
          (planId is! String ||
              planId.isEmpty ||
              months is! int ||
              months <= 0)) {
        return null;
      }

      return PendingCollection(
        receiptId: receiptId,
        kind: kind,
        subjectId: subjectId,
        amount: amount,
        expectedBalance: expectedBalance is int ? expectedBalance : null,
        planId: planId is String ? planId : null,
        months: months is int ? months : null,
      );
    } catch (_) {
      return null;
    }
  }

  final String receiptId;
  final PendingKind kind;

  /// The shop or the courier this is for.
  final String subjectId;

  /// Integer piastres, frozen with the id.
  final int amount;

  /// Courier collection only: the balance the operator acted on. Null belongs to a
  /// pending record written before balance reconciliation shipped.
  final int? expectedBalance;

  /// Subscription only: which plan, and for how many months.
  final String? planId;
  final int? months;

  String encode() => jsonEncode({
    'receiptId': receiptId,
    'kind': kind.slug,
    'subject': subjectId,
    'amount': amount,
    if (expectedBalance != null) 'expectedBalance': expectedBalance,
    if (planId != null) 'planId': planId,
    if (months != null) 'months': months,
  });
}

/// Where pending money movements are kept between attempts.
///
/// On disk rather than in memory, because the case this exists for is the app being
/// killed between the request and its reply — the one case an in-memory id cannot
/// survive, and the one where losing the id means taking the same cash twice.
class PendingCollections {
  PendingCollections(this._prefs, {required this.kind});

  final SharedPreferencesAsync _prefs;
  final PendingKind kind;

  String _key(String subjectId) => 'pending_payment_${kind.slug}_$subjectId';

  Future<PendingCollection?> load(String subjectId) async {
    return PendingCollection.decode(
      await _prefs.getString(_key(subjectId)),
      kind: kind,
      subjectId: subjectId,
    );
  }

  Future<void> save(String subjectId, PendingCollection pending) async {
    // Fail closed, and the caller must not send until this returns. Moving money after
    // this write failed means a lost response can no longer be reconciled and the next
    // tap may take the same cash again.
    await _prefs.setString(_key(subjectId), pending.encode());
  }

  Future<void> clear(String subjectId) async {
    try {
      await _prefs.remove(_key(subjectId));
    } catch (_) {}
  }
}
