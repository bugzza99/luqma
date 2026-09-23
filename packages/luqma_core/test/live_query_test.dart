import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/src/data/live_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The parts of the bridge between Postgres changes and a Dart stream that can be proven
/// without a server. What needs one — a change arriving, a socket coming back — is in
/// `test_live`, against luqma-test.
void main() {
  late SupabaseClient db;

  setUp(() {
    // Nothing listens on this port. Nothing here should ever try it.
    db = SupabaseClient('http://127.0.0.1:9', 'anon');
  });
  tearDown(() => db.dispose());

  test('a watch nobody listens to keeps no clock running', () {
    // E10. The watchdog was started when the stream was *made*, and stopped only by a
    // cancellation — which a stream nobody ever listened to never receives. Every
    // provider rebuilt before its first frame left a two-second timer running for the
    // life of the app, polling a socket for a watch that did not exist.
    var periodic = 0;
    runZoned(
      () => watchRows(db: db, table: 'orders', map: (row) => row),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, period, tick) {
          periodic++;
          return parent.createPeriodicTimer(zone, period, tick);
        },
      ),
    );

    expect(periodic, 0);
  });
}
