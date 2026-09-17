import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'harness.dart';

void main() {
  late LiveDatabase live;
  late SupabaseClient anon;

  setUpAll(() async {
    live = await LiveDatabase.open();
    anon = live.openAnonymously();
  });

  tearDownAll(() async {
    await anon.dispose();
    await live.close();
  });

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  test('records an app open against the real RPC anonymously without throwing', () async {
    final prefs = await SharedPreferences.getInstance();
    final recorder = AppOpenRecorder(client: anon, prefs: prefs);

    await recorder.record('customer');

    // `record` never throws by design, so completing proves nothing: read the row back.
    final deviceId = await recorder.deviceId();
    final rows = await live.client
        .from('app_opens')
        .select('app, device_id, uid')
        .eq('device_id', deviceId) as List;
    addTearDown(() => live.client.from('app_opens').delete().eq('device_id', deviceId));
    expect(rows, hasLength(1));
    expect(rows.single['app'], 'customer');
    expect(rows.single['uid'], isNull);
  });
}
