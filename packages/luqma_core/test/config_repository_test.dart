import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The admin's write path to the control plane.
void main() {
  group('FakeConfigRepository', () {
    test('readAll returns the seeded rows already typed', () async {
      final repo = FakeConfigRepository(
        seed: {'otp_enabled': true, 'marketing_push_per_week': 3},
      );

      final values = (await repo.readAll()).valueOrNull!;
      expect(values['otp_enabled'], true);
      expect(values['marketing_push_per_week'], 3);
    });

    test(
      'setValues upserts and records exactly what the screen wrote',
      () async {
        final repo = FakeConfigRepository();

        final persisted = (await repo.setValues({
          'otp_enabled': true,
          'support_whatsapp': '010',
        })).valueOrNull!;

        expect(repo.setCalls, [
          {'otp_enabled': true, 'support_whatsapp': '010'},
        ]);
        expect((await repo.readAll()).valueOrNull!['otp_enabled'], true);
        expect(persisted['support_whatsapp'], '010');
      },
    );

    test('a failure passes through rather than being swallowed', () async {
      final repo = FakeConfigRepository(failure: const OfflineFailure());

      expect((await repo.readAll()).failureOrNull, isA<OfflineFailure>());
      expect(
        (await repo.setValues({'otp_enabled': true})).failureOrNull,
        isA<OfflineFailure>(),
      );
    });
  });
}
