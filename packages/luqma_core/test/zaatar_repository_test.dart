import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ZaatarVerdict.fromJson', () {
    test('reads each of the five intents', () {
      const cases = {
        'late': HelpTopic.late,
        'wrongItems': HelpTopic.wrongItems,
        'cancel': HelpTopic.cancel,
        'money': HelpTopic.money,
        'other': HelpTopic.other,
      };

      for (final entry in cases.entries) {
        final verdict = ZaatarVerdict.fromJson({
          'intent': entry.key,
          'source': 'model',
        });
        expect(verdict.topic, entry.value, reason: entry.key);
        expect(verdict.fromModel, isTrue);
      }
    });

    // Since 2026-09-24 the server may choose any of the ten topics the phone answers.
    test('reads each topic the server may now choose', () {
      for (final topic in HelpTopic.values) {
        expect(ZaatarVerdict.topicOf(topic.name), topic, reason: topic.name);
      }
    });

    test('reads anything outside the five as «حاجة تانية»', () {
      // A person is what handles those, so an intent nobody implemented is not a crash.
      for (final odd in ['refundEverything', '', 'LATE', 42, null]) {
        final verdict = ZaatarVerdict.fromJson({'intent': odd, 'source': 'local'});
        expect(verdict.topic, HelpTopic.other, reason: '$odd');
      }
    });

    test('marks an answer the server read itself as not from the model', () {
      final verdict = ZaatarVerdict.fromJson({'intent': 'late', 'source': 'local'});

      expect(verdict.topic, HelpTopic.late);
      expect(verdict.fromModel, isFalse);
    });
  });

  group('FakeZaatarRepository', () {
    test('records the call and answers «حاجة تانية» by default', () async {
      final repo = FakeZaatarRepository();

      final result = await repo.ask(orderId: 'order-123', message: 'فين الطلب؟');

      expect(result.isOk, isTrue);
      expect(
        result.valueOrNull,
        const ZaatarVerdict(topic: HelpTopic.other, fromModel: false),
      );
      expect(repo.calls.single.orderId, 'order-123');
      expect(repo.calls.single.message, 'فين الطلب؟');
    });

    test('returns scripted verdicts in order', () async {
      final repo = FakeZaatarRepository(scripted: const [
        ZaatarVerdict(topic: HelpTopic.late, fromModel: true),
        ZaatarVerdict(topic: HelpTopic.cancel, fromModel: false),
      ]);

      expect(
        (await repo.ask(orderId: 'o1', message: 'س1')).valueOrNull,
        const ZaatarVerdict(topic: HelpTopic.late, fromModel: true),
      );
      expect(
        (await repo.ask(orderId: 'o1', message: 'س2')).valueOrNull,
        const ZaatarVerdict(topic: HelpTopic.cancel, fromModel: false),
      );
      expect(repo.calls.length, 2);
    });

    test('the fallback flag is the failure the screen answers around', () async {
      final repo = FakeZaatarRepository(fallback: true);

      final result = await repo.ask(orderId: 'order-456', message: 'سؤال');

      expect(result.isOk, isFalse);
      expect((result.failureOrNull as UnknownFailure).cause, 'fallback');
    });

    test('returns a configured failure as it is', () async {
      final repo = FakeZaatarRepository(failure: const OfflineFailure());

      final result = await repo.ask(orderId: 'order-789', message: 'سؤال');

      expect(result.failureOrNull, isA<OfflineFailure>());
    });
  });

  group('SupabaseZaatarRepository', () {
    SupabaseClient clientReplying(
      int status,
      Object body, {
      void Function(Map<String, dynamic> request)? onRequest,
    }) {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/functions/v1/zaatar');
          onRequest?.call(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return client;
    }

    test('sends the order id and the message, and reads back the verdict', () async {
      Map<String, dynamic>? sent;
      final repo = SupabaseZaatarRepository(clientReplying(
        200,
        {'intent': 'late', 'source': 'model'},
        onRequest: (body) => sent = body,
      ));

      final result = await repo.ask(orderId: 'order-abc', message: 'فين الأوردر؟');

      expect(sent, {'orderId': 'order-abc', 'message': 'فين الأوردر؟'});
      expect(
        result.valueOrNull,
        const ZaatarVerdict(topic: HelpTopic.late, fromModel: true),
      );
    });

    test('a 200 with no intent in it is a fallback, not «حاجة تانية»', () async {
      final repo = SupabaseZaatarRepository(clientReplying(200, {'source': 'local'}));

      final result = await repo.ask(orderId: 'o1', message: 'سؤال');

      expect(result.isOk, isFalse);
      expect((result.failureOrNull as UnknownFailure).cause, 'fallback');
    });

    test('converts 429 into RateLimitedFailure', () async {
      final repo = SupabaseZaatarRepository(clientReplying(429, {'fallback': true}));

      final result = await repo.ask(orderId: 'o1', message: 'سؤال متكرر');

      expect(result.failureOrNull, isA<RateLimitedFailure>());
    });

    test('converts 503 into the fallback failure', () async {
      final repo = SupabaseZaatarRepository(clientReplying(503, {'fallback': true}));

      final result = await repo.ask(orderId: 'o1', message: 'سؤال');

      expect((result.failureOrNull as UnknownFailure).cause, 'fallback');
    });

    test('converts a timeout into the fallback failure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response(
            jsonEncode({'intent': 'late', 'source': 'local'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repo = SupabaseZaatarRepository(
        client,
        timeout: const Duration(milliseconds: 10),
      );
      final result = await repo.ask(orderId: 'o1', message: 'سؤال');

      expect((result.failureOrNull as UnknownFailure).cause, 'fallback');
    });

    test('converts 401 into PermissionFailure', () async {
      final repo =
          SupabaseZaatarRepository(clientReplying(401, {'error': 'unauthorized'}));

      final result = await repo.ask(orderId: 'o1', message: 'سؤال');

      expect(result.failureOrNull, isA<PermissionFailure>());
    });

    test('converts 404 into NotFoundFailure', () async {
      final repo = SupabaseZaatarRepository(clientReplying(404, {'error': 'notFound'}));

      final result = await repo.ask(orderId: 'nobody-elses', message: 'سؤال');

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });
}
