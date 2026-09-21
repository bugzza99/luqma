import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_controller.g.dart';

/// Images waiting for a decision.
@riverpod
Stream<List<Media>> pendingMedia(Ref ref) =>
    ref.watch(mediaRepositoryProvider).watchPending();

/// Whose each waiting picture is — shop, dish, uploader — named by the server in one call.
/// A failure names nobody rather than failing the queue: the picture can still be judged.
@riverpod
Future<Map<String, MediaContext>> pendingMediaContext(Ref ref) async {
  final pending = await ref.watch(pendingMediaProvider.future);
  final result = await ref.read(mediaRepositoryProvider).contextOf([
    for (final m in pending) m.id,
  ]);
  return result.valueOrNull ?? const {};
}

/// Kept alive for the same reason as the merchant actions: nothing watches a commands
/// object, so an auto-disposed one is thrown away while its command is still running.
/// Kept alive for the same reason as the merchant actions: nothing watches a commands
/// object, so an auto-disposed one is thrown away while its command is still running.
///
/// Its state is the reviewer's uid. Holding it as state rather than asking for it when a
/// button is pressed means the identity provider has a subscriber for as long as this
/// exists — `read(...future)` on a stream nobody is listening to never resolves, and the
/// command would hang instead of failing.
@Riverpod(keepAlive: true)
class MediaActions extends _$MediaActions {
  @override
  String? build() => ref.watch(currentIdentityProvider).value?.uid;

  Future<Result<void>> approve(String id) async {
    final res = await ref
        .read(mediaRepositoryProvider)
        .setStatus(id, MediaStatus.approved);
    if (res.isOk) {
      ref.invalidate(pendingMediaProvider);
    }
    return res;
  }

  Future<Result<void>> reject(String id, String reason) async {
    final res = await ref
        .read(mediaRepositoryProvider)
        .setStatus(id, MediaStatus.rejected, note: reason);
    if (res.isOk) {
      ref.invalidate(pendingMediaProvider);
    }
    return res;
  }
}
