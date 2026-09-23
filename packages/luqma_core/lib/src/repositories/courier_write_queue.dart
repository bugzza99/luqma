import 'dart:async';

import '../models/order.dart';
import 'courier_order_repository.dart';
import '../result.dart';

/// What a queued courier write is.
enum CourierWriteKind {
  onTheWay,
  delivered,
  failed;

  static CourierWriteKind fromName(String name) => switch (name) {
        'onTheWay' => onTheWay,
        'delivered' => delivered,
        'failed' => failed,
        _ => delivered,
      };
}

/// One courier action that has not yet reached the server.
///
/// A courier stands in the street and takes cash. A tap on "delivered" that dies with
/// the connection is money collected against an order the system still thinks is out —
/// so the tap must survive, not disappear. This is the smallest unit that can be kept
/// and replayed.
class PendingCourierWrite {
  const PendingCourierWrite({
    required this.orderId,
    required this.kind,
    this.courierUid,
    this.reason,
    this.at,
  });

  final String orderId;
  final CourierWriteKind kind;

  /// For [CourierWriteKind.onTheWay]: whose name goes on the order.
  final String? courierUid;

  /// For [CourierWriteKind.failed]: what the admin eventually reads.
  final String? reason;

  /// For [CourierWriteKind.delivered]: the moment of the tap, not of the send (L3). A tap
  /// at 23:50 that reaches the server at 01:10 belongs to the day it happened on. Null
  /// on a record written before this was kept; the server then dates it on arrival.
  final DateTime? at;

  Map<String, Object?> toJson() => {
        'orderId': orderId,
        'kind': kind.name,
        if (courierUid != null) 'courierUid': courierUid,
        if (reason != null) 'reason': reason,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
      };

  factory PendingCourierWrite.fromJson(Map<String, dynamic> json) =>
      PendingCourierWrite(
        orderId: json['orderId'] as String,
        kind: CourierWriteKind.fromName(json['kind'] as String),
        courierUid: json['courierUid'] as String?,
        reason: json['reason'] as String?,
        at: json['at'] is String ? DateTime.tryParse(json['at'] as String) : null,
      );
}

/// Everything one account's queue keeps between launches.
///
/// The refused writes travel with the pending ones because both are promises to the
/// courier: one that a tap is still coming, the other that they will be told it never
/// arrived. Kept only in memory, the second was broken by any app kill — the «محصلش»
/// banner vanished with the process, and the cash for that order was still in their
/// pocket.
class StoredCourierWrites {
  const StoredCourierWrites({this.pending = const [], this.rejected = const []});

  static const empty = StoredCourierWrites();

  final List<PendingCourierWrite> pending;
  final List<PendingCourierWrite> rejected;

  bool get isEmpty => pending.isEmpty && rejected.isEmpty;
}

/// Where the queue's writes live between launches.
///
/// An interface so the queue is testable without a device and so the store can be
/// swapped (shared_preferences on the phone, memory in a test). The account travels
/// with each call because the phone store exists before there is a signed-in identity;
/// putting it in the store constructor would make start-up guess who will use it.
///
/// One call writes both lists, so they are one record on disk and cannot be half-saved.
abstract interface class CourierWriteStore {
  Future<StoredCourierWrites> load({required String accountId});
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
    required List<PendingCourierWrite> rejected,
  });
}

/// An in-memory store for tests.
class InMemoryCourierWriteStore implements CourierWriteStore {
  final Map<String, StoredCourierWrites> _byAccount = {};

  List<PendingCourierWrite> snapshotFor(String accountId) =>
      List.unmodifiable(_byAccount[accountId]?.pending ?? const []);

  List<PendingCourierWrite> rejectedSnapshotFor(String accountId) =>
      List.unmodifiable(_byAccount[accountId]?.rejected ?? const []);

  @override
  Future<StoredCourierWrites> load({required String accountId}) async {
    final stored = _byAccount[accountId];
    if (stored == null) return StoredCourierWrites.empty;
    return StoredCourierWrites(
      pending: List.of(stored.pending),
      rejected: List.of(stored.rejected),
    );
  }

  @override
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
    required List<PendingCourierWrite> rejected,
  }) async {
    if (pending.isEmpty && rejected.isEmpty) {
      _byAccount.remove(accountId);
    } else {
      _byAccount[accountId] = StoredCourierWrites(
        pending: List.of(pending),
        rejected: List.of(rejected),
      );
    }
  }
}

/// The result of submitting a courier write.
sealed class CourierSubmitOutcome {
  const CourierSubmitOutcome();
}

/// The write reached the server now.
class CourierSubmitted extends CourierSubmitOutcome {
  const CourierSubmitted();
}

/// The write is saved locally and will be sent when the connection returns.
class CourierQueued extends CourierSubmitOutcome {
  const CourierQueued();
}

/// The write was refused for a reason that will not change by retrying.
class CourierRejected extends CourierSubmitOutcome {
  const CourierRejected(this.failure);

  final Failure failure;
}

/// Where an order stands for the courier who is holding it.
///
/// The server is not the whole truth on this screen, and treating it as one cost the
/// half of the delivery that carries the cash. A courier taps «بدأت التوصيل» in a
/// stairwell with no signal: the tap is queued, the server goes on saying `preparing`,
/// and a card reading the status alone offers «بدأت التوصيل» a second time and never
/// offers «تم التسليم». So a run could be *started* with no connection and not
/// *finished* with one — the money changed hands at the door and the one tap that
/// records it was the tap the screen refused to draw.
///
/// What this reads is the courier's own queue, which is the only other thing on the
/// phone that knows what they did.
enum CourierProgress {
  /// Nothing queued, and the server has not sent it out: the next tap starts the run.
  toCollect,

  /// On the road — by the server's account, or by a tap still waiting to be sent.
  onTheRoad,

  /// This phone has already recorded the end of it. There is no tap left to make, and
  /// offering one would queue the same delivery twice.
  finished;

  /// [status] is what the server last said; [pending] is everything this account has
  /// queued, for every order.
  static CourierProgress of(
    String orderId,
    OrderStatus status,
    Iterable<PendingCourierWrite> pending,
  ) {
    // The last one wins: a courier who started and then delivered has queued two, and
    // where they stand is wherever the second one put them.
    final queued = lastQueuedFor(orderId, pending);
    return switch (queued) {
      CourierWriteKind.delivered || CourierWriteKind.failed => finished,
      CourierWriteKind.onTheWay => onTheRoad,
      null => status == OrderStatus.outForDelivery ? onTheRoad : toCollect,
    };
  }
}

/// The last thing this phone recorded about one order and has not yet managed to send,
/// or null when the queue holds nothing for it.
CourierWriteKind? lastQueuedFor(
  String orderId,
  Iterable<PendingCourierWrite> pending,
) {
  CourierWriteKind? last;
  for (final write in pending) {
    if (write.orderId == orderId) last = write.kind;
  }
  return last;
}

/// A local queue over [CourierOrderRepository].
///
/// The smallest thing that covers the one case where a lost write is money lost: a
/// courier tapping "delivered" without a connection. The write is attempted; if it fails
/// offline it is held locally and replayed on [flush], oldest first. Anything else is
/// surfaced immediately — a conflict means the order moved under somebody else, and
/// retrying would not change that.
class CourierWriteQueue {
  CourierWriteQueue(
    this._repository, {
    required this.accountId,
    CourierWriteStore? store,
    DateTime Function()? now,
  })  : _store = store ?? InMemoryCourierWriteStore(),
        _now = now ?? DateTime.now;

  /// When a tap happened. Read at the tap, carried with the write.
  final DateTime Function() _now;

  final CourierOrderRepository _repository;
  final String accountId;
  final CourierWriteStore _store;

  final List<PendingCourierWrite> _pending = [];

  /// Writes the server refused on replay, kept until somebody has been told.
  ///
  /// Dropping a conflicting write is right — retrying it for ever is noise and the
  /// order has moved on. Dropping it *silently* is not: the screen promises "هيتبعت أول
  /// ما النت يرجع", and a count that quietly falls by one reads as sent. The courier is
  /// standing in the street with the cash for that order.
  final List<PendingCourierWrite> _rejected = [];

  /// The read of the store, once started — kept so every caller waits for the same one.
  Future<void>? _loading;

  final _changed = StreamController<void>.broadcast();

  /// The writes still waiting to reach the server.
  List<PendingCourierWrite> get pending => List.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  /// What a replay could not land. Cleared by [clearRejected] once it has been shown.
  List<PendingCourierWrite> get rejected => List.unmodifiable(_rejected);

  /// The courier has read it — and it is gone from the store too, or it would be back on
  /// the screen at the next launch.
  Future<void> clearRejected() async {
    await load();
    if (_rejected.isEmpty) return;
    _rejected.clear();
    _notify();
    await _persist();
  }

  /// Emits when the pending set changes, so the screen can show the honest
  /// "هيتبعت أول ما النت يرجع" line rather than pretending the tap vanished.
  Stream<void> get changes => _changed.stream;

  /// Loads persisted writes. Called once, before the first read of [pending].
  ///
  /// Every caller waits for the same read, including one that arrives while it is still
  /// in progress. A flag set before the read finished told a second caller the queue was
  /// loaded while it still held nothing: after a cold start the first tap sent a delivery
  /// straight past the start stored for the same order, and its `_persist` saved a list
  /// without the stored writes over the one that had them.
  ///
  /// A read that fails is not remembered. Latching it would leave a queue that believes
  /// itself loaded and empty, and the next tap would save that emptiness over writes that
  /// are still on the disk — the courier's cash, lost to one bad read. So the failure
  /// reaches this caller, and the next caller reads the store again.
  Future<void> load() => _loading ??= _read().then(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _loading = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  Future<void> _read() async {
    final stored = await _store.load(accountId: accountId);
    _pending.addAll(stored.pending);
    _rejected.addAll(stored.rejected);
  }

  Future<CourierSubmitOutcome> markOnTheWay(
    String orderId, {
    required String courierUid,
  }) =>
      _submit(PendingCourierWrite(
        orderId: orderId,
        kind: CourierWriteKind.onTheWay,
        courierUid: courierUid,
      ));

  Future<CourierSubmitOutcome> markDelivered(String orderId) => _submit(
        PendingCourierWrite(
          orderId: orderId,
          kind: CourierWriteKind.delivered,
          at: _now().toUtc(),
        ),
      );

  Future<CourierSubmitOutcome> markFailed(
    String orderId, {
    required String reason,
  }) =>
      _submit(PendingCourierWrite(
        orderId: orderId,
        kind: CourierWriteKind.failed,
        reason: reason,
      ));

  Future<CourierSubmitOutcome> _submit(PendingCourierWrite write) async {
    await load();

    // Behind anything already waiting for the same order, never ahead of it. «بدأت
    // التوصيل» queued in a stairwell and «تم التسليم» tapped at the door with signal: sent
    // at once, the delivery reached an order the server still had as `preparing`, was
    // refused, and was not even kept — the tap that records the cash, lost, while the
    // start sat in the queue waiting to be replayed. The queue is the order the courier
    // did things in, and an order's writes only make sense in that order.
    //
    // Queued, and then tried at once rather than left to the drain: the drain may be
    // backed off for minutes, and a courier at the door with the signal back should not
    // be told «هيتبعت أول ما النت يرجع» about a network that has already returned. The
    // flush replays this order oldest first, so the start still goes before the
    // delivery; with no signal the start fails offline and the delivery waits behind it.
    if (_pending.any((w) => w.orderId == write.orderId)) {
      _pending.add(write);
      await _persist();
      _notify();
      await flush();
      if (_rejected.contains(write)) {
        return const CourierRejected(ConflictFailure());
      }
      return _pending.contains(write)
          ? const CourierQueued()
          : const CourierSubmitted();
    }

    final result = await _perform(write);
    if (result case Err(:final failure) when failure is OfflineFailure) {
      _pending.add(write);
      await _persist();
      _notify();
      return const CourierQueued();
    }
    if (result case Err(:final failure)) {
      return CourierRejected(failure);
    }
    return const CourierSubmitted();
  }

  /// The pass in progress, which a second caller joins rather than starting another.
  Future<void>? _flushing;

  /// Replays the queue, oldest first. A write that fails offline again stays queued; a
  /// write that fails for any other reason is not retried — retrying a conflict for ever
  /// is noise, and the order has already moved on — but it lands in [rejected] rather
  /// than vanishing, because the courier was promised it would be sent.
  ///
  /// One pass at a time, whoever asks. The drain had its own guard and the «حاول تاني»
  /// button went round it, so a tap during a timer drain made two passes over the same
  /// snapshot: every write sent twice, and the second copy refused and reported as
  /// «محصلش» for a delivery that had landed. The guard lives here now, where every
  /// caller has to pass through it.
  Future<void> flush() =>
      _flushing ??= _flushOnce().whenComplete(() => _flushing = null);

  Future<void> _flushOnce() async {
    await load();
    if (_pending.isEmpty) return;

    // A snapshot, and a reconcile rather than a replace.
    //
    // Both halves of the old version lost taps, and both situations are ordinary: this
    // runs from a connectivity listener, and a courier keeps working while it does.
    // Iterating `_pending` while awaiting inside the loop threw
    // `ConcurrentModificationError` the moment a tap was added — leaving the queue
    // unpersisted and no change announced — and `..clear()..addAll(remaining)` threw
    // away anything that arrived after the last await. The second is exactly the loss
    // this class exists to prevent, arriving through the code that prevents it.
    final attempted = List.of(_pending);
    final stillWaiting = <PendingCourierWrite>[];

    // Orders whose earlier write could not be sent this pass. Everything after it for the
    // same order waits too, in place: a delivery sent past its unsent start reaches an
    // order that has not left the kitchen, is refused, and is reported as «محصلش».
    final held = <String>{};
    for (final write in attempted) {
      if (held.contains(write.orderId)) {
        stillWaiting.add(write);
        continue;
      }
      final result = await _perform(write);
      if (result case Err(:final failure) when failure is OfflineFailure) {
        stillWaiting.add(write);
        held.add(write.orderId);
      } else if (result case Err()) {
        _rejected.add(write);
      }
    }

    // Only what was attempted *and* settled leaves the queue. Anything a courier tapped
    // in the meantime is still there, in the order they tapped it.
    final settled = Set<PendingCourierWrite>.identity()
      ..addAll(attempted.where((w) => !stillWaiting.contains(w)));
    _pending.removeWhere(settled.contains);
    await _persist();
    _notify();
  }

  Future<Result<void>> _perform(PendingCourierWrite write) =>
      switch (write.kind) {
        CourierWriteKind.onTheWay => _repository.markOnTheWay(
            write.orderId,
            courierUid: write.courierUid ?? '',
          ),
        CourierWriteKind.delivered =>
          _repository.markDelivered(write.orderId, at: write.at),
        CourierWriteKind.failed => _repository.markFailed(
            write.orderId,
            reason: write.reason ?? '',
          ),
      };

  Future<void> _persist() => _store.save(
        accountId: accountId,
        pending: List.of(_pending),
        rejected: List.of(_rejected),
      );

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();
}
