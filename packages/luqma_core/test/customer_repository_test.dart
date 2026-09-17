import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('FakeCustomerRepository.setPassword', () {
    final customer = CustomerSummary(
      id: 'cust-1',
      name: 'أحمد',
      phone: '01012345678',
      isBlocked: false,
      rejectedOrdersCount: 0,
      createdAt: DateTime(2026, 9, 1),
    );

    test('sets a valid password and records (uid, password)', () async {
      final repo = FakeCustomerRepository(seed: [customer]);

      final result = await repo.setPassword('cust-1', 'password123');

      expect(result.isOk, isTrue);
      expect(repo.passwordCalls, [('cust-1', 'password123')]);
    });

    test('refuses passwords shorter than 8 chars with ValidationFailure', () async {
      final repo = FakeCustomerRepository(seed: [customer]);

      final result = await repo.setPassword('cust-1', 'short');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.passwordCalls, isEmpty);
    });

    test('refuses passwords longer than 72 chars with ValidationFailure', () async {
      final repo = FakeCustomerRepository(seed: [customer]);
      final longPassword = 'a' * 73;

      final result = await repo.setPassword('cust-1', longPassword);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.passwordCalls, isEmpty);
    });

    test('trims password before validating length', () async {
      final repo = FakeCustomerRepository(seed: [customer]);

      // '  1234567  ' trimmed is 7 chars -> fails
      final result = await repo.setPassword('cust-1', '  1234567  ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.passwordCalls, isEmpty);
    });

    test('returns NotFoundFailure when customer does not exist', () async {
      final repo = FakeCustomerRepository(seed: [customer]);

      final result = await repo.setPassword('missing-uid', 'validPassword123');

      expect(result.failureOrNull, isA<NotFoundFailure>());
      expect(repo.passwordCalls, isEmpty);
    });

    test('returns configured failure when repo.failure is set', () async {
      final repo = FakeCustomerRepository(
        seed: [customer],
        failure: const OfflineFailure(),
      );

      final result = await repo.setPassword('cust-1', 'validPassword123');

      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(repo.passwordCalls, isEmpty);
    });
  });

  group('SupabaseCustomerRepository.setPassword', () {
    test('succeeds on 200 {ok: true}', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/functions/v1/reset-customer-password');
          expect(jsonDecode(request.body), {'uid': 'u1', 'password': 'pass12345'});
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseCustomerRepository(client).setPassword('u1', 'pass12345');
      expect(result.isOk, isTrue);
    });

    test('maps 400 badPassword to ValidationFailure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'badPassword'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseCustomerRepository(client).setPassword('u1', 'short');
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('maps 400 notAllowed to PermissionFailure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'notAllowed'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseCustomerRepository(client).setPassword('admin-uid', 'pass12345');
      expect(result.failureOrNull, isA<PermissionFailure>());
    });

    test('maps 404 to NotFoundFailure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'noSuchAccount'}),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseCustomerRepository(client).setPassword('missing-uid', 'pass12345');
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('maps 401 and 403 to PermissionFailure', () async {
      final client401 = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'unauthorized'}),
            401,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client401.dispose);
      final res401 = await SupabaseCustomerRepository(client401).setPassword('u1', 'pass12345');
      expect(res401.failureOrNull, isA<PermissionFailure>());

      final client403 = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'forbidden'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client403.dispose);
      final res403 = await SupabaseCustomerRepository(client403).setPassword('u1', 'pass12345');
      expect(res403.failureOrNull, isA<PermissionFailure>());
    });
  });
}
