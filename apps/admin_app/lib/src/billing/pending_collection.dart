import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A collection that was sent and whose reply never came back.
///
/// The receipt id and the amount are **one frozen pair**, set before the first request
/// and never changed afterwards. That is the whole point of the type, and it is a type
/// rather than two local variables because the merchant collection learned the hard way
/// what happens when they drift apart: a receipt minted when the dialog opened and an
/// amount read out of the box at every press meant a retry could send the original
/// receipt id with a new figure. The server, doing exactly its job, answered with the
/// first receipt and moved nothing — and the screen said «اتسجّل ٢٠٠ ج». A false receipt
/// in a cash business, produced by the path built to prevent one.
class PendingCollection {
  const PendingCollection({required this.receiptId, required this.amount});

  /// Reads a stored record. Returns null unless **both** halves are there and readable.
  ///
  /// Both or neither, deliberately. The id is written first, so a record with a missing
  /// or non-integer amount would leave the id set and the amount null — an editable
  /// field, no notice — and the next press would send a new figure under the old
  /// receipt. That is the original bug's exact shape, reassembled out of a half-readable
  /// preference.
  static PendingCollection? decode(String? json) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final receiptId = map['receiptId'];
      final amount = map['amount'];
      if (receiptId is! String || receiptId.isEmpty || amount is! int) {
        return null;
      }
      return PendingCollection(receiptId: receiptId, amount: amount);
    } catch (_) {
      return null;
    }
  }

  final String receiptId;

  /// Integer piastres, frozen with the id.
  final int amount;

  String encode() => jsonEncode({'receiptId': receiptId, 'amount': amount});
}

/// Where pending collections are kept between attempts.
///
/// On disk rather than in memory, because the case this exists for is the app being
/// killed between the request and its reply — the one case an in-memory id cannot
/// survive, and the one where losing the id means collecting the same cash twice.
class PendingCollections {
  PendingCollections(this._prefs, {required this.kind});

  final SharedPreferencesAsync _prefs;

  /// Namespaces the key, so a shop and a courier with the same id — which cannot happen
  /// today and would be silent if it ever did — cannot read each other's attempt.
  final String kind;

  String _key(String subjectId) => 'pending_payment_${kind}_$subjectId';

  Future<PendingCollection?> load(String subjectId) async {
    return PendingCollection.decode(await _prefs.getString(_key(subjectId)));
  }

  Future<void> save(String subjectId, PendingCollection pending) async {
    // Fail closed. Sending money after this write failed means a lost response can no
    // longer be reconciled and the next tap may collect the same cash twice.
    await _prefs.setString(_key(subjectId), pending.encode());
  }

  Future<void> clear(String subjectId) async {
    try {
      await _prefs.remove(_key(subjectId));
    } catch (_) {}
  }
}
