import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One equality constraint a live query applies — to its fetch and to its realtime
/// subscription alike.
final class RowFilter {
  const RowFilter(this.column, this.value);

  final String column;
  final String value;
}

int _watchSerial = 0;

/// How long the server may still be wiring replication after reporting a channel
/// subscribed. Writes landing inside this window fire no event; the delayed refetch
/// after every fresh subscription is what closes it.
const _replicationGrace = Duration(seconds: 1);

/// How often a watch whose channel died tries to rebuild it.
const _rejoinInterval = Duration(seconds: 2);

/// Watches one table the way Firestore watched a query.
///
/// Firestore streamed a *query* and re-evaluated it on the server. Supabase streams *row
/// changes* and leaves the list to the client. That difference is where the bugs of this
/// migration would otherwise live — nineteen streams over — so the bridge is written
/// once, and every repository watches through it:
///
/// - **Fetch.** The query runs and emits first, so a listener has data before any
///   socket handshake finishes.
/// - **Refetch, not merge.** A change on the table triggers the query again rather than
///   a hand-patched list. A refetch cannot apply a stale event out of order, and cannot
///   mishandle the row that changed *out of* the result — the merchant whose suspension
///   should remove them from a customer's list is exactly such a row. At Edku's size a
///   refetch costs nothing.
/// - **Reconnect.** Nothing replays what was missed while the socket was down, and the
///   realtime client does not even rejoin its channels after an explicit drop — verified
///   against the local stack, where disconnect/connect delivers `closed` and then
///   nothing, for ever. So the watch rebuilds its own channel whenever it reports
///   anything but `subscribed`, and the refetch on the far side *is* the backfill.
///
/// Errors surface as stream errors, as snapshots did. RLS applies to realtime exactly
/// as to reads, so a policy that is subtly wrong shows up as a stream that is quietly
/// short rather than as an error — which is why the policies have tests of their own in
/// `supabase/test/stack`, beside these.
Stream<List<T>> watchRows<T>({
  required SupabaseClient db,
  required String table,
  required T Function(Map<String, dynamic> row) map,
  List<RowFilter> filters = const [],
  String? orderBy,
  bool ascending = true,
}) {
  // Counts up on every fetch, so a slow fetch overtaken by a newer one cannot deliver
  // an older snapshot after a newer one has already been delivered.
  var inFlight = 0;
  var cancelled = false;
  // Set by a `subscribed` status, not by polling: the drop window can be shorter than
  // one watchdog tick, and only the status is proof the channel was ever alive.
  var everConnected = false;
  var dropped = false;
  RealtimeChannel? channel;
  Timer? rejoin;
  late final Timer watchdog;
  late final StreamController<List<T>> controller;

  Future<void> fetchAndEmit() async {
    final token = ++inFlight;
    try {
      Future<List<Map<String, dynamic>>> run() async {
        var query = db.from(table).select();
        for (final f in filters) {
          query = query.eq(f.column, f.value);
        }
        // `ascending` spelled out, again: postgrest-dart defaults it to false, the
        // opposite of what `order by` means in SQL. Left implicit, ordering flips.
        if (orderBy != null) {
          return query.order(orderBy, ascending: ascending);
        }
        return query;
      }

      final rows = await run();
      if (!controller.isClosed && token == inFlight) {
        controller.add(rows.map(map).toList());
      }
    } catch (error, stackTrace) {
      if (!controller.isClosed && token == inFlight) {
        controller.addError(error, stackTrace);
      }
    }
  }

  void openChannel() {
    final ch = db.channel('luqma-watch-${_watchSerial++}-$table');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filters: filters
          .map((f) => PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: f.column,
                value: f.value,
              ))
          .toList(),
      callback: (_) => unawaited(fetchAndEmit()),
    );
    ch.subscribe((status, _) {
      if (cancelled) return;

      if (status == RealtimeSubscribeStatus.subscribed) {
        rejoin?.cancel();
        rejoin = null;
        everConnected = true;
        // The join reports `subscribed` before the server has finished wiring the
        // replication behind it, so a write made in that window fires no event. The
        // immediate refetch answers the query as it stands; the delayed one sweeps
        // whatever landed in the window.
        unawaited(fetchAndEmit());
        unawaited(Future<void>.delayed(_replicationGrace).then((_) {
          if (!cancelled) fetchAndEmit();
        }));
        return;
      }

      // Closed, errored or timed out: rebuild until subscribed comes back.
      rejoin ??= Timer.periodic(_rejoinInterval, (_) {
        if (cancelled) return;
        final dead = channel;
        channel = null;
        if (dead != null) unawaited(db.removeChannel(dead));
        openChannel();
      });
    });
    channel = ch;
  }

  // An explicit disconnect delivers no status to the channels at all — verified against
  // the local stack, where a watch sat on a dead socket reporting nothing, for ever.
  // So the socket's state is watched directly: a drop is marked, and the socket coming
  // back rebuilds every channel it took with it.
  watchdog = Timer.periodic(_rejoinInterval, (_) {
    if (cancelled) return;
    if (!db.realtime.isConnected) {
      if (everConnected) dropped = true;
      return;
    }
    if (!dropped) return;
    dropped = false;
    final dead = channel;
    channel = null;
    if (dead != null) unawaited(db.removeChannel(dead));
    openChannel();
  });

  controller = StreamController<List<T>>(
    onListen: () {
      unawaited(fetchAndEmit());
      openChannel();
    },
    onCancel: () {
      cancelled = true;
      ++inFlight; // an answer arriving after cancellation belongs to nobody
      rejoin?.cancel();
      watchdog.cancel();
      final ch = channel;
      channel = null;
      if (ch != null) unawaited(db.removeChannel(ch));
    },
  );
  return controller.stream;
}

