import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plans_editor_controller.g.dart';

/// Every plan, active or withdrawn — the editor sees what a price change would touch.
@riverpod
Future<List<Plan>> allPlans(Ref ref) async {
  final result =
      await ref.watch(billingRepositoryProvider).plans(includeInactive: true);
  return result.valueOrThrow;
}

/// Commands, kept alive for the same reason as every other actions object.
@Riverpod(keepAlive: true)
class PlansActions extends _$PlansActions {
  @override
  void build() {}

  Future<Result<void>> save(Plan plan) async {
    final result = await ref.read(billingRepositoryProvider).savePlan(plan);
    ref.invalidate(allPlansProvider);
    ref.invalidate(plansProvider);
    return result;
  }
}
