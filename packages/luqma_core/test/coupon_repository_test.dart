import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final now = DateTime(2026, 9, 17, 12, 0);

  final baseCoupon = Coupon(
    id: 'c-1',
    code: 'SAVE10',
    cityId: 'edku',
    type: CouponType.percentage,
    value: 1000,
    maxDiscount: 2000,
    merchantId: 'm-1',
    fundedBy: CouponFunder.merchant,
    validFrom: now,
    validUntil: now.add(const Duration(days: 7)),
  );

  group('FakeCouponRepository', () {
    test(
      'create normalizes code and assigns id, usedCount=0, createdByUid',
      () async {
        final repo = FakeCouponRepository(actingUid: 'user-admin');

        final draft = const Coupon(
          id: '',
          code: '  save20  ',
          cityId: 'edku',
          type: CouponType.percentage,
          value: 2000,
          maxDiscount: 3000,
          merchantId: 'm-1',
        );

        final result = await repo.create(draft);
        expect(result.isOk, isTrue);
        final created = result.valueOrNull!;
        expect(created.id, isNotEmpty);
        expect(created.code, 'SAVE20');
        expect(created.usedCount, 0);
        // An admin's write is not stamped by the guard trigger; the column defaults to null.
        expect(created.createdByUid, isNull);
      },
    );

    test(
      'create refuses percentage without maxDiscount with ValidationFailure',
      () async {
        final repo = FakeCouponRepository();

        final draft = const Coupon(
          id: '',
          code: 'UNCAPPED',
          cityId: 'edku',
          type: CouponType.percentage,
          value: 1500,
          maxDiscount: null,
        );

        final result = await repo.create(draft);
        expect(result.failureOrNull, isA<ValidationFailure>());
      },
    );

    test(
      'create refuses duplicate code in same city with ConflictFailure',
      () async {
        final repo = FakeCouponRepository(seed: [baseCoupon]);

        final draft = const Coupon(
          id: '',
          code: 'save10', // same as SAVE10 in 'edku'
          cityId: 'edku',
          type: CouponType.fixedAmount,
          value: 500,
        );

        final result = await repo.create(draft);
        expect(result.failureOrNull, isA<ConflictFailure>());
      },
    );

    test('create allows same code in different city', () async {
      final repo = FakeCouponRepository(seed: [baseCoupon]);

      final draft = const Coupon(
        id: '',
        code: 'save10',
        cityId: 'cairo',
        type: CouponType.fixedAmount,
        value: 500,
      );

      final result = await repo.create(draft);
      expect(result.isOk, isTrue);
    });

    test(
      'merchant-scoped write can only create for their own shop with fundedBy=merchant',
      () async {
        final repo = FakeCouponRepository(isAdmin: false, merchantId: 'm-1');

        // Attempt to create for another shop
        final wrongShop = await repo.create(
          const Coupon(
            id: '',
            code: 'OTHER',
            cityId: 'edku',
            type: CouponType.fixedAmount,
            value: 500,
            merchantId: 'm-2',
            fundedBy: CouponFunder.merchant,
          ),
        );
        expect(wrongShop.failureOrNull, isA<PermissionFailure>());

        // Attempt to create platform-funded coupon
        final platformFunded = await repo.create(
          const Coupon(
            id: '',
            code: 'PLATFORM',
            cityId: 'edku',
            type: CouponType.fixedAmount,
            value: 500,
            merchantId: 'm-1',
            fundedBy: CouponFunder.platform,
          ),
        );
        expect(platformFunded.failureOrNull, isA<PermissionFailure>());

        // Valid merchant coupon succeeds
        final valid = await repo.create(
          const Coupon(
            id: '',
            code: 'MYSHOP',
            cityId: 'edku',
            type: CouponType.fixedAmount,
            value: 500,
            merchantId: 'm-1',
            fundedBy: CouponFunder.merchant,
          ),
        );
        expect(valid.isOk, isTrue);
      },
    );

    test(
      'update edits allowed fields only and enforces cap & unique code',
      () async {
        final repo = FakeCouponRepository(seed: [baseCoupon]);

        final updated = baseCoupon.copyWith(
          code: 'save15',
          value: 1500,
          maxDiscount: 2500,
          minOrder: 5000,
          firstOrderOnly: true,
        );

        final result = await repo.update(updated);
        expect(result.isOk, isTrue);

        final all = (await repo.listAll()).valueOrNull!;
        expect(all.first.code, 'SAVE15');
        expect(all.first.value, 1500);
        expect(all.first.maxDiscount, 2500);
        expect(all.first.minOrder, 5000);
        expect(all.first.firstOrderOnly, isTrue);
      },
    );

    test('update refuses percentage without maxDiscount', () async {
      final repo = FakeCouponRepository(seed: [baseCoupon]);

      final uncapped = baseCoupon.copyWith(maxDiscount: null);
      final result = await repo.update(uncapped);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test(
      'update under merchant scope refuses editing another merchant coupon',
      () async {
        final repo = FakeCouponRepository(
          seed: [baseCoupon],
          isAdmin: false,
          merchantId: 'm-other',
        );

        final result = await repo.update(baseCoupon.copyWith(value: 2000));
        expect(
          result.failureOrNull,
          isA<NotFoundFailure>(),
        ); // hidden by the policy, as on the server
      },
    );

    test('setActive updates status and enforces merchant scope', () async {
      final repo = FakeCouponRepository(seed: [baseCoupon]);

      final deactivate = await repo.setActive('c-1', false);
      expect(deactivate.isOk, isTrue);
      expect((await repo.listAll()).valueOrNull!.first.isActive, isFalse);

      final activate = await repo.setActive('c-1', true);
      expect(activate.isOk, isTrue);
      expect((await repo.listAll()).valueOrNull!.first.isActive, isTrue);

      final nonExistent = await repo.setActive('missing', false);
      expect(nonExistent.failureOrNull, isA<NotFoundFailure>());
    });

    test('watchForMerchant emits coupons for that merchant', () async {
      final repo = FakeCouponRepository(
        seed: [
          baseCoupon,
          baseCoupon.copyWith(id: 'c-2', code: 'OTHER', merchantId: 'm-2'),
        ],
      );

      final list = await repo.watchForMerchant('m-1').first;
      expect(list.length, 1);
      expect(list.first.id, 'c-1');
    });
  });

  group('SupabaseCouponRepository', () {
    test(
      'create maps snake_case columns, normalizes code, and parses response',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'anon-key',
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/rpc/create_coupon' &&
                request.method == 'POST') {
              final body = jsonDecode(request.body) as Map;
              expect(body['p_code'], 'CODE10');
              expect(body['p_city_id'], 'edku');
              expect(body['p_type'], 'percentage');
              expect(body['p_value'], 1000);
              expect(body['p_max_discount'], 2000);
              expect(body['p_merchant_id'], 'm-1');
              expect(body.containsKey('p_id'), isFalse);
              expect(body.containsKey('p_used_count'), isFalse);
              expect(body.containsKey('p_created_by'), isFalse);

              return http.Response(
                jsonEncode({
                  'id': 'c-created-1',
                  'code': 'CODE10',
                  'city_id': 'edku',
                  'type': 'percentage',
                  'value': 1000,
                  'max_discount': 2000,
                  'min_order': 0,
                  'merchant_id': 'm-1',
                  'first_order_only': false,
                  'per_user_limit': 0,
                  'total_limit': 0,
                  'used_count': 0,
                  'is_active': true,
                  'funded_by': 'merchant',
                  'created_by': 'user-123',
                }),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return http.Response('Not found', 404, request: request);
          }),
        );
        addTearDown(client.dispose);

        final repo = SupabaseCouponRepository(client);
        final draft = const Coupon(
          id: '',
          code: '  code10  ',
          cityId: 'edku',
          type: CouponType.percentage,
          value: 1000,
          maxDiscount: 2000,
          merchantId: 'm-1',
        );

        final result = await repo.create(draft);
        expect(result.isOk, isTrue);
        final coupon = result.valueOrNull!;
        expect(coupon.id, 'c-created-1');
        expect(coupon.code, 'CODE10');
        expect(coupon.createdByUid, 'user-123');
      },
    );

    test('create maps 23505 unique code constraint to ConflictFailure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': '23505',
              'message':
                  'duplicate key value violates unique constraint "coupons_code_idx"',
            }),
            409,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repo = SupabaseCouponRepository(client);
      final result = await repo.create(baseCoupon);
      expect(result.failureOrNull, isA<ConflictFailure>());
    });

    test('create client-side refuses percentage without maxDiscount', () async {
      final client = SupabaseClient('https://example.supabase.co', 'anon-key');
      addTearDown(client.dispose);

      final repo = SupabaseCouponRepository(client);
      final uncapped = baseCoupon.copyWith(maxDiscount: null);
      final result = await repo.create(uncapped);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('listAll fetches newest first and decodes columns', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/coupons');
          expect(
            request.url.queryParameters['order'],
            contains('created_at.desc'),
          );
          return http.Response(
            jsonEncode([
              {
                'id': 'c-1',
                'code': 'SAVE10',
                'city_id': 'edku',
                'type': 'percentage',
                'value': 1000,
                'max_discount': 2000,
                'min_order': 0,
                'merchant_id': 'm-1',
                'first_order_only': false,
                'per_user_limit': 0,
                'total_limit': 0,
                'used_count': 3,
                'is_active': true,
                'funded_by': 'merchant',
                'created_by': 'uid-1',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repo = SupabaseCouponRepository(client);
      final result = await repo.listAll();
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.first.createdByUid, 'uid-1');
      expect(result.valueOrNull!.first.usedCount, 3);
    });
  });
}
