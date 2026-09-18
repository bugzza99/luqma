import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The other half of a notification: what happens when somebody taps it.
///
/// `LuqmaPush` writes the tapped notification payload to a notifier so whichever shell
/// is alive can route to the screen it is about. These tests are the reader and decoder.
void main() {
  group('payload decoding', () {
    test('a non-JSON payload becomes an orderId tap and never throws', () {
      final tap = LuqmaTap.decode('order-from-previous-build');
      expect(tap.kind, isNull);
      expect(tap.orderId, 'order-from-previous-build');
      expect(tap.data, {'orderId': 'order-from-previous-build'});
    });

    test('a numeric or scalar non-map payload becomes an orderId tap without throwing', () {
      final tap1 = LuqmaTap.decode('12345');
      expect(tap1.kind, isNull);
      expect(tap1.orderId, '12345');

      final tap2 = LuqmaTap.decode('');
      expect(tap2.kind, isNull);
      expect(tap2.orderId, '');
    });

    test('a JSON payload round-trips kind and ids', () {
      final original = {
        'kind': 'staffApplication',
        'applicationId': 'app-99',
        'note': 'motorcycle courier',
      };
      final encoded = jsonEncode(original);
      final tap = LuqmaTap.decode(encoded);

      expect(tap.kind, 'staffApplication');
      expect(tap.data['applicationId'], 'app-99');
      expect(tap.data['note'], 'motorcycle courier');
      expect(tap.orderId, isNull);
    });

    test('a JSON payload with orderId exposes orderId getter', () {
      final encoded = jsonEncode({
        'kind': 'needsAttention',
        'orderId': 'o-77',
      });
      final tap = LuqmaTap.decode(encoded);

      expect(tap.kind, 'needsAttention');
      expect(tap.orderId, 'o-77');
      expect(tap.data['orderId'], 'o-77');
    });

    test('LuqmaTap equality and hashCode work correctly', () {
      const tap1 = LuqmaTap(
        kind: 'staffApplication',
        data: {'applicationId': 'app-1'},
      );
      const tap2 = LuqmaTap(
        kind: 'staffApplication',
        data: {'applicationId': 'app-1'},
      );
      const tap3 = LuqmaTap(
        kind: 'needsAttention',
        data: {'orderId': 'o-1'},
      );

      expect(tap1, equals(tap2));
      expect(tap1.hashCode, equals(tap2.hashCode));
      expect(tap1, isNot(equals(tap3)));
    });
  });

  group('LuqmaTappedNotification widget', () {
    setUp(() => LuqmaPush.tapped.value = null);
    tearDown(() => LuqmaPush.tapped.value = null);

    Future<List<LuqmaTap>> pump(WidgetTester tester) async {
      final opened = <LuqmaTap>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LuqmaTappedNotification(
            onOpen: opened.add,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      return opened;
    }

    testWidgets('a notification tapped while the app was dead is opened on the first frame',
        (tester) async {
      // The launch case, and the one that cannot be covered by a listener alone: the tap
      // is recorded by launch details or getInitialMessage before any of this app's widgets exist.
      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'needsAttention',
        data: {'orderId': 'order-from-a-cold-start'},
      );

      final opened = await pump(tester);

      expect(opened, [
        const LuqmaTap(
          kind: 'needsAttention',
          data: {'orderId': 'order-from-a-cold-start'},
        ),
      ]);
      expect(opened.single.orderId, 'order-from-a-cold-start');
    });

    testWidgets('a notification tapped while the app is running is opened', (tester) async {
      final opened = await pump(tester);

      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'staffApplication',
        data: {'applicationId': 'app-alive'},
      );
      await tester.pump();

      expect(opened, [
        const LuqmaTap(
          kind: 'staffApplication',
          data: {'applicationId': 'app-alive'},
        ),
      ]);
    });

    testWidgets('the same notification is not opened twice by a rebuild', (tester) async {
      // Taking the value rather than watching it. A shell rebuilds on every tab switch,
      // and a screen that reopens itself each time is a screen nobody can leave.
      final opened = await pump(tester);

      LuqmaPush.tapped.value = const LuqmaTap(
        data: {'orderId': 'order-once'},
      );
      await tester.pump();
      await tester.pump();

      expect(opened.length, 1);
      expect(opened.single.orderId, 'order-once');
    });

    testWidgets('tapping the same notification again does open it again', (tester) async {
      // The consequence of taking rather than remembering: two notifications about one
      // event are two requests to see it, and the second must not be swallowed as a
      // duplicate of the first.
      final opened = await pump(tester);

      LuqmaPush.tapped.value = const LuqmaTap(
        data: {'orderId': 'order-twice'},
      );
      await tester.pump();
      LuqmaPush.tapped.value = const LuqmaTap(
        data: {'orderId': 'order-twice'},
      );
      await tester.pump();

      expect(opened.length, 2);
      expect(opened[0].orderId, 'order-twice');
      expect(opened[1].orderId, 'order-twice');
    });

    testWidgets('nothing is opened when no notification was tapped', (tester) async {
      final opened = await pump(tester);
      await tester.pump();

      expect(opened, isEmpty);
    });

    testWidgets('a tap after the widget is gone opens nothing', (tester) async {
      final opened = await pump(tester);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      LuqmaPush.tapped.value = const LuqmaTap(
        data: {'orderId': 'order-after-dispose'},
      );
      await tester.pump();

      expect(opened, isEmpty);
    });
  });
}
