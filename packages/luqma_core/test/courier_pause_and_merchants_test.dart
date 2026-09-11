import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  group('StaffMember availability', () {
    final now = DateTime(2026, 9, 22, 14, 0);

    test('is available when pausedUntil is null', () {
      const member = StaffMember(
        uid: 'c1',
        scope: 'merchant',
        role: 'courier',
        isActive: true,
      );

      expect(member.pausedUntil, isNull);
      expect(member.isAvailableAt(now), isTrue);
    });

    test('is not available when pausedUntil is in the future', () {
      final member = StaffMember(
        uid: 'c1',
        scope: 'merchant',
        role: 'courier',
        isActive: true,
        pausedUntil: now.add(const Duration(minutes: 30)),
      );

      expect(member.isAvailableAt(now), isFalse);
    });

    test('is available when pausedUntil is in the past', () {
      final member = StaffMember(
        uid: 'c1',
        scope: 'merchant',
        role: 'courier',
        isActive: true,
        pausedUntil: now.subtract(const Duration(minutes: 5)),
      );

      expect(member.isAvailableAt(now), isTrue);
    });

    test('is available at the exact moment pausedUntil lapses', () {
      final member = StaffMember(
        uid: 'c1',
        scope: 'merchant',
        role: 'courier',
        isActive: true,
        pausedUntil: now,
      );

      expect(member.isAvailableAt(now), isTrue);
    });

    test('fromJson and fromRow parse pausedUntil and paused_until', () {
      final fromJson = StaffMember.fromJson({
        'uid': 'c1',
        'scope': 'merchant',
        'role': 'courier',
        'isActive': true,
        'pausedUntil': '2026-09-22T14:30:00.000Z',
      });
      expect(fromJson.pausedUntil, isNotNull);
      expect(fromJson.pausedUntil!.toUtc().hour, 14);
      expect(fromJson.pausedUntil!.toUtc().minute, 30);

      final fromRow = StaffMember.fromRow({
        'uid': 'c1',
        'scope': 'merchant',
        'role': 'courier',
        'is_active': true,
        'paused_until': '2026-09-22T15:00:00.000Z',
      });
      expect(fromRow.pausedUntil, isNotNull);
      expect(fromRow.pausedUntil!.toUtc().hour, 15);
    });
  });

  group('FakeStaffRepository.setPausedUntil', () {
    test('updates pausedUntil and notifies live watchers', () async {
      final initial = StaffMember(
        uid: 'c1',
        scope: 'merchant',
        role: 'courier',
        isActive: true,
      );
      final repo = FakeStaffRepository(seed: [initial]);

      final emissions = <DateTime?>[];
      final sub = repo.watchStaffMember('c1').listen((m) {
        emissions.add(m?.pausedUntil);
      });

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, isNull);

      final until = DateTime(2026, 9, 22, 15, 0);
      final res = await repo.setPausedUntil('c1', until);
      expect(res.isOk, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, until);

      // Resuming by clearing it
      final resumeRes = await repo.setPausedUntil('c1', null);
      expect(resumeRes.isOk, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, isNull);

      await sub.cancel();
      repo.dispose();
    });

    test('returns not found for unknown staff member', () async {
      final repo = FakeStaffRepository();
      final res = await repo.setPausedUntil('unknown', DateTime.now());
      expect(res.isOk, isFalse);
      expect(res.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('FakeCourierOrderRepository.watchCarriedMerchants', () {
    test('emits carried shops including null for platform', () async {
      final repo = FakeCourierOrderRepository(
        carriedMerchants: const ['m1', 'm2', null],
      );

      final carried = await repo.watchCarriedMerchants().first;
      expect(carried, containsAll(['m1', 'm2', null]));
      expect(carried.length, 3);
    });

    test('updates live on attach and detach', () async {
      final repo = FakeCourierOrderRepository(
        carriedMerchants: const ['m1'],
      );

      final emissions = <List<String?>>[];
      final sub = repo.watchCarriedMerchants().listen((shops) {
        emissions.add(shops);
      });

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, ['m1']);

      repo.attach(null);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, containsAll(['m1', null]));

      repo.detach('m1');
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, [null]);

      await sub.cancel();
      repo.dispose();
    });
  });
}
