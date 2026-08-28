import 'dart:async';

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
/// swapped (shared_preferences on the phone, memory in a test).
abstract interface class CourierWriteStore {
  Future<List<PendingCourierWrite>> load();
  Future<void> save(List<PendingCourierWrite> pending);
}

/// An in-memory store for tests.
class InMemoryCourierWriteStore implements CourierWriteStore {
  List<PendingCourierWrite> _pending = [];

  List<PendingCourierWrite> get snapshot => List.unmodifiable(_pending);

  @override
  Future<List<PendingCourierWrite>> load() async => List.of(_pending);

  @override
  Future<void> save(List<PendingCourierWrite> pending) async {
    _pending = List.of(pending);
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

/// A local queue over [CourierOrderRepository].
///
/// The smallest thing that covers the one case where a lost write is money lost: a
/// courier tapping "delivered" without a connection. The write is attempted; if it fails
/// offline it is held locally and replayed on [flush], oldest first. Anything else is
/// surfaced immediately — a conflict means the order moved under somebody else, and
/// retrying would not change that.
class CourierWriteQueue {
  CourierWriteQueue(this._repository, {CourierWriteStore? store})
    : _store = store ?? InMemoryCourierWriteStore();

  final CourierOrderRepository _repository;
  final CourierWriteStore _store;

  final List<PendingCourierWrite> _pending = [];
  bool _loaded = false;

  final _changed = StreamController<void>.broadcast();

  /// The writes still waiting to reach the server.
  List<PendingCourierWrite> get pending => List.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  /// Emits when the pending set changes, so the screen can show the honest
  /// "هيتبعت أول ما النت يرجع" line rather than pretending the tap vanished.
  Stream<void> get changes => _changed.stream;

  /// Loads persisted writes. Called once, before the first read of [pending].
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _pending.addAll(await _store.load());
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
  /// write that fails for any other reason is dropped — retrying a conflict forever is
  /// noise, and the order has already moved on.
  Future<void> flush() async {
    await load();
    if (_pending.isEmpty) return;

    final remaining = <PendingCourierWrite>[];
    for (final write in _pending) {
      final result = await _perform(write);
      if (result case Err(:final failure) when failure is OfflineFailure) {
        remaining.add(write);
      }
    }
    _pending
      ..clear()
      ..addAll(remaining);
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

  Future<void> _persist() => _store.save(List.of(_pending));

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();
}
