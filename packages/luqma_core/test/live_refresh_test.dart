import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Counts the refreshes, which is the whole of what this widget promises.
class _CountingAuth extends FakeAuthService {
  _CountingAuth() : super(restoring: const LuqmaIdentity(uid: 'u1'));

  int refreshes = 0;

  @override
  Future<Result<void>> refreshSession() async {
    refreshes++;
    return super.refreshSession();
  }
}

/// A one-shot read that remembers how many times it was asked.
class _CountingPlans extends FakeBillingRepository {
  int reads = 0;

  @override
  Future<Result<List<Plan>>> plans({bool includeInactive = false}) {
    reads++;
    return super.plans(includeInactive: includeInactive);
  }
}

/// The owner's report: approve something from AdminApp, and the merchant has to close the
/// app and open it again before it shows.
void main() {
  late _CountingAuth auth;
  late _CountingPlans plans;

  Future<void> pump(WidgetTester tester) async {
    auth = _CountingAuth();
    await auth.restore();
    addTearDown(auth.dispose);
    plans = _CountingPlans();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          billingRepositoryProvider.overrideWithValue(plans),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          home: LuqmaLiveRefresh(
            minInterval: const Duration(minutes: 1),
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(plansProvider);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('coming back to the app asks again, claims and all', (tester) async {
    await pump(tester);
    expect(plans.reads, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(auth.refreshes, 1, reason: 'an approval is a claim on the token');
    expect(plans.reads, 2, reason: 'a plan the admin changed is read again');
  });

  testWidgets('switching apps twice in a row is not two refreshes', (tester) async {
    await pump(tester);

    for (var i = 0; i < 2; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    expect(auth.refreshes, 1);
  });

  testWidgets('a notification arriving on screen refreshes, however recent the last',
      (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.refreshes, 1);

    LuqmaPush.received.add(const LuqmaTap(kind: 'subscription_activated'));
    await tester.pumpAndSettle();

    expect(auth.refreshes, 2);
    expect(plans.reads, 3);
  });
}
