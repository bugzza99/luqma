import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'config_controller.g.dart';

/// The current config rows, fresh from the table.
///
/// Not the customer's `appConfigProvider`: that is the *last fetched* values, and an
/// admin editing the control plane must see what is actually in the table rather than
/// what their own phone last fetched.
@riverpod
Future<Map<String, Object>> adminConfig(Ref ref) async {
  final result = await ref.watch(configRepositoryProvider).readAll();
  return result.valueOrThrow;
}

/// Commands rather than state, kept alive for the same reason as every other actions
/// object: nothing watches a commands object, so an auto-disposed one is thrown away
/// while its write is still in flight.
@Riverpod(keepAlive: true)
class ConfigActions extends _$ConfigActions {
  @override
  void build() {}

  Future<Result<void>> save(Map<String, Object> values) async {
    final result = await ref.read(configRepositoryProvider).setValues(values);
    ref.invalidate(adminConfigProvider);
    return result;
  }
}
