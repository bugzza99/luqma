import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'summary uses the account RPC and decodes every integer total',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/settlement_summary');
          expect(jsonDecode(request.body), {'p_merchant_id': 'm1'});
          return http.Response(
            jsonEncode({
              'orders': 101,
              'taken': 20200,
              'platform_owes': 30300,
              'paid': 10100,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await SupabaseSettlementRepository(
        client,
      ).summaryFor('m1');
      expect(
        result.valueOrThrow,
        const SettlementSummary(
          orders: 101,
          taken: 20200,
          platformOwes: 30300,
          paid: 10100,
        ),
      );
    },
  );

  test(
    'an unreadable account is a permission failure, never zero totals',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient(
          (request) async => http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      final result = await SupabaseSettlementRepository(
        client,
      ).summaryFor('m2');
      expect(result.failureOrNull, isA<PermissionFailure>());
    },
  );
}
