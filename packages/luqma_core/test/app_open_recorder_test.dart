import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('device id is a valid v4 uuid and persists across instances', () async {
    final prefs = await SharedPreferences.getInstance();
    final recorder1 = AppOpenRecorder(prefs: prefs, rpc: (_, _) async {});

    final id1 = await recorder1.deviceId();
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(id1),
      isTrue,
      reason: 'Should be a valid v4 UUID',
    );
    expect(prefs.getString('luqma.device_id'), id1);

    // Second instance with same prefs gets same device id
    final recorder2 = AppOpenRecorder(prefs: prefs, rpc: (_, _) async {});
    expect(await recorder2.deviceId(), id1);
  });

  test('records once per Cairo day per app in memory', () async {
    final prefs = await SharedPreferences.getInstance();
    final calls = <(String, String)>[];
    var currentTime = DateTime.utc(2026, 9, 17, 10, 0); // 13:00 Cairo

    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => currentTime,
      rpc: (app, deviceId) async => calls.add((app, deviceId)),
    );

    await recorder.record('customer');
    expect(calls.length, 1);
    expect(calls.first.$1, 'customer');

    // Second call on the same Cairo day does not call RPC again
    await recorder.record('customer');
    expect(calls.length, 1);

    // Call for a different app calls RPC once
    await recorder.record('merchant');
    expect(calls.length, 2);
    expect(calls.last.$1, 'merchant');
  });

  test('records again on the next Cairo day', () async {
    final prefs = await SharedPreferences.getInstance();
    final calls = <(String, String)>[];
    var currentTime = DateTime.utc(2026, 9, 17, 10, 0);

    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => currentTime,
      rpc: (app, deviceId) async => calls.add((app, deviceId)),
    );

    await recorder.record('customer');
    expect(calls.length, 1);

    // Advance by 1 day
    currentTime = currentTime.add(const Duration(days: 1));

    await recorder.record('customer');
    expect(calls.length, 2);
  });

  test('never throws when RPC throws an error', () async {
    final prefs = await SharedPreferences.getInstance();
    final recorder = AppOpenRecorder(
      prefs: prefs,
      rpc: (_, _) async => throw Exception('RPC network error'),
    );

    // Should not throw
    await expectLater(recorder.record('customer'), completes);
  });

  test('observer records again when app lifecycle state resumes', () async {
    final prefs = await SharedPreferences.getInstance();
    final calls = <(String, String)>[];
    var currentTime = DateTime.utc(2026, 9, 17, 10, 0);

    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => currentTime,
      rpc: (app, deviceId) async => calls.add((app, deviceId)),
    );

    final observer = AppOpenLifecycleObserver(recorder: recorder, app: 'customer');

    // First record
    await recorder.record('customer');
    expect(calls.length, 1);

    // Resumed on same day -> does not call again
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);

    // Advance clock to next day and resume -> records again!
    currentTime = currentTime.add(const Duration(days: 1));
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 2);
  });

  // Found in review: the key was (app, day) alone, so an anonymous open at launch followed
  // by signing in the same day never attributed the day to the account, and «accounts»
  // undercounted everybody who opens the app before signing in.
  test('records again the same day once somebody has signed in', () async {
    final prefs = await SharedPreferences.getInstance();
    final calls = <(String, String)>[];
    var signedIn = false;
    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => DateTime.utc(2026, 9, 17, 10),
      hasUser: () => signedIn,
      rpc: (app, deviceId) async => calls.add((app, deviceId)),
    );

    await recorder.record('customer');
    await recorder.record('customer');
    expect(calls.length, 1);

    signedIn = true;
    await recorder.record('customer');
    await recorder.record('customer');
    expect(calls.length, 2);
  });

  test('two overlapping calls send one request', () async {
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final gate = Completer<void>();
    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => DateTime.utc(2026, 9, 17, 10),
      rpc: (_, _) async {
        calls++;
        await gate.future;
      },
    );

    final first = recorder.record('customer');
    final second = recorder.record('customer');
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });

  test('a failed request is tried again on the next open', () async {
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    var fail = true;
    final recorder = AppOpenRecorder(
      prefs: prefs,
      clock: () => DateTime.utc(2026, 9, 17, 10),
      rpc: (_, _) async {
        calls++;
        if (fail) throw Exception('offline');
      },
    );

    await recorder.record('customer');
    fail = false;
    await recorder.record('customer');
    await recorder.record('customer');
    expect(calls, 2);
  });
}
