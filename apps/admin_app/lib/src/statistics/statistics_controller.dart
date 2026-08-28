import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'statistics_controller.g.dart';

/// Who is on the platform and how it is moving. Read-only, wider than a day.
@riverpod
Future<AdminStatistics> adminStatistics(Ref ref) async {
  final result = await ref.watch(adminRepositoryProvider).statistics();
  return result.valueOrThrow;
}
