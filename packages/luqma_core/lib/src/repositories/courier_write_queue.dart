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
  });

  final String orderId;
  final CourierWriteKind kind;

  /// For [CourierWriteKind.onTheWay]: whose name goes on the order.
  final String? courierUid;

  /// For [CourierWriteKind.failed]: what the admin eventually reads.
  final String? reason;

  Map<String, Object?> toJson() => {
        'orderId': orderId,
        'kind': kind.name,
        if (courierUid != null) 'courierUid': courierUid,
        if (reason != null) 'reason': reason,
      };

  factory PendingCourierWrite.fromJson(Map<String, dynamic> json) =>
      PendingCourierWrite(
        orderId: json['orderId'] as String,
        kind: CourierWriteKind.fromName(json['kind'] as String),
        courierUid: json['courierUid'] as String?,
        reason: json['reason'] as String?,
      );
}

/// Where the queue's pending writes live between launches.
///
/// An interface so the queue is testable without a device and so the store can be
/// swapped (shared_preferences on the phone, memory in a test). The account travels
/// with each call because the phone store exists before there is a signed-in identity;
/// putting it in the store constructor would make start-up guess who will use it.
abstract interface class CourierWriteStore {
  Future<List<PendingCourierWrite>> load({required String accountId});
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
  });
}

/// An in-memory store for tests.
class InMemoryCourierWriteStore implements CourierWriteStore {
  final Map<String, List<PendingCourierWrite>> _pendingByAccount = {};

  List<PendingCourierWrite> snapshotFor(String accountId) =>
      List.unmodifiable(_pendingByAccount[accountId] ?? const []);

  @override
  Future<List<PendingCourierWrite>> load({required String accountId}) async =>
      List.of(_pendingByAccount[accountId] ?? const []);

  @override
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
  }) async {
    if (pending.isEmpty) {
      _pendingByAccount.remove(accountId);
    } else {
      _pendingByAccount[accountId] = List.of(pending);
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
  }) : _store = store ?? InMemoryCourierWriteStore();

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

  bool _loaded = false;

  final _changed = StreamController<void>.broadcast();

  /// The writes still waiting to reach the server.
  List<PendingCourierWrite> get pending => List.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  /// What a replay could not land. Cleared by [clearRejected] once it has been shown.
  List<PendingCourierWrite> get rejected => List.unmodifiable(_rejected);

  /// The courier has read it.
  void clearRejected() {
    if (_rejected.isEmpty) return;
    _rejected.clear();
    _notify();
  }

  /// Emits when the pending set changes, so the screen can show the honest
  /// "هيتبعت أول ما النت يرجع" line rather than pretending the tap vanished.
  Stream<void> get changes => _changed.stream;

  /// Loads persisted writes. Called once, before the first read of [pending].
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _pending.addAll(await _store.load(accountId: accountId));
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
        PendingCourierWrite(orderId: orderId, kind: CourierWriteKind.delivered),
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

  /// Replays the queue, oldest first. A write that fails offline again stays queued; a
  /// write that fails for any other reason is not retried — retrying a conflict for ever
  /// is noise, and the order has already moved on — but it lands in [rejected] rather
  /// than vanishing, because the courier was promised it would be sent.
  Future<void> flush() async {
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
    for (final write in attempted) {
      final result = await _perform(write);
      if (result case Err(:final failure) when failure is OfflineFailure) {
        stillWaiting.add(write);
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
          _repository.markDelivered(write.orderId),
        CourierWriteKind.failed => _repository.markFailed(
            write.orderId,
            reason: write.reason ?? '',
          ),
      };

  Future<void> _persist() => _store.save(
        accountId: accountId,
        pending: List.of(_pending),
      );

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();
}
