import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AdminRepository.deleteAccount', () {
    test('FakeAdminRepository refuses deleting signed-in admin with PermissionFailure', () async {
      final repo = FakeAdminRepository(currentAdminUid: 'admin-me');

      final result = await repo.deleteAccount('admin-me');

      expect(result.failureOrNull, isA<PermissionFailure>());
      expect(repo.deletedAccountCalls, isEmpty);
    });

    test('FakeAdminRepository refuses deleting platform staff with PermissionFailure', () async {
      final repo = FakeAdminRepository(
        currentAdminUid: 'admin-me',
        platformStaffUids: {'admin-me', 'platform-staff-1'},
      );

      final result = await repo.deleteAccount('platform-staff-1');

      expect(result.failureOrNull, isA<PermissionFailure>());
      expect(repo.deletedAccountCalls, isEmpty);
    });

    test('FakeAdminRepository removes customer and staff from lists and records call', () async {
      final customerRepo = FakeCustomerRepository(
        seed: [
          CustomerSummary(
            id: 'cust-1',
            name: 'محمود',
            phone: '01000000000',
            isBlocked: false,
            rejectedOrdersCount: 0,
            createdAt: DateTime(2026, 9, 1),
          ),
        ],
      );
      final staffRepo = FakeStaffRepository(
        seed: const [
          StaffMember(
            uid: 'courier-1',
            scope: 'merchant',
            role: 'courier',
            isActive: true,
          ),
        ],
      );

      final repo = FakeAdminRepository(
        currentAdminUid: 'admin-me',
        customers: customerRepo,
        staff: staffRepo,
      );

      final resultCust = await repo.deleteAccount('cust-1');
      expect(resultCust.isOk, isTrue);
      expect((await customerRepo.search('')).valueOrNull, isEmpty);

      final resultStaff = await repo.deleteAccount('courier-1');
      expect(resultStaff.isOk, isTrue);
      expect(staffRepo.all, isEmpty);

      expect(repo.deletedAccountCalls, ['cust-1', 'courier-1']);
    });

    test('SupabaseAdminRepository calls rpc admin_delete_account', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/admin_delete_account');
          expect(jsonDecode(request.body), {'p_uid': 'target-uid'});
          return http.Response('', 204, request: request);
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseAdminRepository(client).deleteAccount('target-uid');
      expect(result.isOk, isTrue);
    });
  });

  group('ActiveUsers model & AdminRepository.activeUsers', () {
    test('ActiveUsers reads missing rows as 0', () {
      final empty = ActiveUsers.fromRows([]);
      expect(empty.customer.day.devices, 0);
      expect(empty.customer.day.accounts, 0);
      expect(empty.customer.week.devices, 0);
      expect(empty.customer.week.accounts, 0);
      expect(empty.customer.month.devices, 0);
      expect(empty.customer.month.accounts, 0);

      expect(empty.merchant.day.devices, 0);
      expect(empty.merchant.day.accounts, 0);
      expect(empty.merchant.week.devices, 0);
      expect(empty.merchant.week.accounts, 0);
      expect(empty.merchant.month.devices, 0);
      expect(empty.merchant.month.accounts, 0);
    });

    test('ActiveUsers decodes (app, period) counts accurately', () {
      final rows = [
        {'app': 'customer', 'period': 'day', 'devices': 42, 'accounts': 12},
        {'app': 'customer', 'period': 'week', 'devices': 100, 'accounts': 35},
        {'app': 'customer', 'period': 'month', 'devices': 300, 'accounts': 80},
        {'app': 'merchant', 'period': 'day', 'devices': 5, 'accounts': 3},
        {'app': 'merchant', 'period': 'week', 'devices': 15, 'accounts': 8},
        {'app': 'merchant', 'period': 'month', 'devices': 20, 'accounts': 10},
      ];

      final users = ActiveUsers.fromRows(rows);
      expect(users.customer.day.devices, 42);
      expect(users.customer.day.accounts, 12);
      expect(users.customer.week.devices, 100);
      expect(users.customer.week.accounts, 35);
      expect(users.customer.month.devices, 300);
      expect(users.customer.month.accounts, 80);

      expect(users.merchant.day.devices, 5);
      expect(users.merchant.day.accounts, 3);
      expect(users.merchant.week.devices, 15);
      expect(users.merchant.week.accounts, 8);
      expect(users.merchant.month.devices, 20);
      expect(users.merchant.month.accounts, 10);
    });

    test('SupabaseAdminRepository.activeUsers invokes rpc and parses rows', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/admin_active_users');
          return http.Response(
            jsonEncode([
              {'app': 'customer', 'period': 'day', 'devices': 10, 'accounts': 5},
              {'app': 'merchant', 'period': 'week', 'devices': 7, 'accounts': 2},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseAdminRepository(client).activeUsers();
      expect(result.isOk, isTrue);
      final active = result.valueOrNull!;
      expect(active.customer.day.devices, 10);
      expect(active.customer.day.accounts, 5);
      expect(active.customer.week.devices, 0); // missing row is 0
      expect(active.merchant.week.devices, 7);
      expect(active.merchant.week.accounts, 2);
    });

    test('FakeAdminRepository returns activeUsersValue or default', () async {
      final fake = FakeAdminRepository();
      final res = await fake.activeUsers();
      expect(res.isOk, isTrue);
      expect(res.valueOrNull!.customer.day.devices, 0);

      final custom = FakeAdminRepository(
        activeUsersValue: ActiveUsers.fromRows([
          {'app': 'customer', 'period': 'day', 'devices': 99, 'accounts': 98},
        ]),
      );
      final customRes = await custom.activeUsers();
      expect(customRes.valueOrNull!.customer.day.devices, 99);
      expect(customRes.valueOrNull!.customer.day.accounts, 98);
    });
  });
}
