import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A widget suite cannot prove a database grant, but it can refuse to teach screens a
/// path production rejects. These tests keep the fake's answer and its authority aligned
/// with `promotion_push_report` rather than making an admin-only read available to any
/// caller that happens to hold the repository.
void main() {
  const delivered = PromotionPushReport(
    queued: 4,
    sent: 1,
    waiting: 2,
    failed: 1,
  );

  test('returns the server-shaped counts for one campaign', () async {
    final repository = FakePromotionRepository(
      pushReports: const {'p1': delivered},
    );

    expect(
      (await repository.pushReport('p1')).valueOrNull,
      delivered,
    );
  });

  test('a campaign with no outbox rows answers zero', () async {
    final repository = FakePromotionRepository();

    expect(
      (await repository.pushReport('p1')).valueOrNull,
      const PromotionPushReport(),
    );
  });

  test('a non-admin is refused instead of receiving the fake report', () async {
    final repository = FakePromotionRepository(
      isAdmin: false,
      pushReports: const {'p1': delivered},
    );

    expect(
      (await repository.pushReport('p1')).failureOrNull,
      isA<PermissionFailure>(),
    );
  });
}
