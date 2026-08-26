import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'about_controller.g.dart';

/// The owner's photo, resolved from the media id the config carries.
///
/// Null when no id is set, or when the id does not resolve to an approved image — a
/// photo that has not passed the moderation queue is not shown, exactly like every
/// other image in the product.
@riverpod
Future<Media?> aboutPhoto(Ref ref) async {
  final id = ref.watch(appConfigProvider).aboutPhotoMediaId;
  if (id == null || id.isEmpty) return null;

  final result = await ref.watch(mediaRepositoryProvider).get(id);
  final media = result.valueOrNull;
  return (media != null && media.status == MediaStatus.approved) ? media : null;
}
