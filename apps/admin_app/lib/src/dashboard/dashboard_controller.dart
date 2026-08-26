import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_controller.g.dart';

/// The four numbers the owner opens the app to see, in one server round trip.
@riverpod
Future<AdminToday> adminToday(Ref ref) async {
  final result = await ref.watch(adminRepositoryProvider).today();
  return result.valueOrThrow;
}
