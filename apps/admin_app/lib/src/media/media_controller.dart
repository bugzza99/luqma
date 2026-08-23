import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/identity_provider.dart';

part 'media_controller.g.dart';

/// Images waiting for a decision.
@riverpod
Stream<List<Media>> pendingMedia(Ref ref) =>
    ref.watch(mediaRepositoryProvider).watchPending();

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
  String? build() => ref.watch(adminIdentityProvider).value?.uid;

  Future<void> approve(String id) async {
    await ref.read(mediaRepositoryProvider).setStatus(
          id,
          MediaStatus.approved,
          reviewedBy: state,
        );
    ref.invalidate(pendingMediaProvider);
  }

  Future<void> reject(String id, String reason) async {
    await ref.read(mediaRepositoryProvider).setStatus(
          id,
          MediaStatus.rejected,
          reviewedBy: state,
          note: reason,
        );
    ref.invalidate(pendingMediaProvider);
  }
}
