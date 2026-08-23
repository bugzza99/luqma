import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/home_section.dart';
import '../result.dart';

/// The arrangement of the customer's home screen.
///
/// Live rather than fetched once: a section hidden in AdminApp should disappear from
/// phones already open, which is most of what "without shipping an update" means in
/// practice.
abstract interface class HomeSectionRepository {
  /// Every section for the city, ordered, including hidden ones.
  ///
  /// Hidden sections are returned rather than filtered here because the same list feeds
  /// AdminApp's home builder, where a hidden section must still be visible to the person
  /// who hid it. Deciding what to draw belongs to the app.
  Stream<List<HomeSection>> watchSections({required String cityId});

  Future<Result<void>> save(HomeSection section);
  Future<Result<void>> setVisible(String key, bool isVisible);
  Future<Result<void>> reorder(List<String> keysInOrder);
}

class FirestoreHomeSectionRepository implements HomeSectionRepository {
  FirestoreHomeSectionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sections =>
      _firestore.collection('homeSections');

  @override
  Stream<List<HomeSection>> watchSections({required String cityId}) {
    return _sections
        .where('cityId', isEqualTo: cityId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => HomeSection.fromJson({...doc.data(), 'key': doc.id}))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }

  @override
  Future<Result<void>> save(HomeSection section) {
    return Result.guard(() async {
      await _sections.doc(section.key).set(
            section.toJson()..remove('key'),
            SetOptions(merge: true),
          );
    });
  }

  @override
  Future<Result<void>> setVisible(String key, bool isVisible) {
    return Result.guard(
      () => _sections.doc(key).update({'isVisible': isVisible}),
    );
  }

  @override
  Future<Result<void>> reorder(List<String> keysInOrder) {
    return Result.guard(() async {
      // One batch: a half-applied reorder would leave two sections claiming the same
      // position, and the screen would settle on whichever loaded first.
      final batch = _firestore.batch();
      for (var i = 0; i < keysInOrder.length; i++) {
        batch.update(_sections.doc(keysInOrder[i]), {'sortOrder': i});
      }
      await batch.commit();
    });
  }
}

class FakeHomeSectionRepository implements HomeSectionRepository {
  FakeHomeSectionRepository({List<HomeSection> seed = const [], this.failure})
      : _sections = List.of(seed);

  final List<HomeSection> _sections;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Everything held right now. A widget test runs on a fake clock and cannot await the
  /// stream below, so this is what lets a test assert on what a screen wrote.
  List<HomeSection> get all => List.unmodifiable(_sections);

  HomeSection? operator [](String key) =>
      _sections.where((s) => s.key == key).firstOrNull;

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();

  @override
  Stream<List<HomeSection>> watchSections({required String cityId}) {
    if (failure != null) return Stream.error(failure!);
    // Live, like Firestore's: a builder that hides a section has to see it change.
    return Stream.multi((listener) {
      List<HomeSection> read() =>
          _sections.where((s) => s.cityId == null || s.cityId == cityId).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      listener.add(read());
      final sub = _changed.stream.listen((_) => listener.add(read()));
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<Result<void>> save(HomeSection section) async {
    if (failure != null) return Result.err(failure!);
    _sections
      ..removeWhere((s) => s.key == section.key)
      ..add(section);
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setVisible(String key, bool isVisible) async {
    if (failure != null) return Result.err(failure!);
    final i = _sections.indexWhere((s) => s.key == key);
    if (i < 0) return const Result.err(NotFoundFailure());
    _sections[i] = _sections[i].copyWith(isVisible: isVisible);
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reorder(List<String> keysInOrder) async {
    if (failure != null) return Result.err(failure!);
    for (var i = 0; i < keysInOrder.length; i++) {
      final index = _sections.indexWhere((s) => s.key == keysInOrder[i]);
      if (index >= 0) _sections[index] = _sections[index].copyWith(sortOrder: i);
    }
    _notify();
    return const Result.ok(null);
  }
}
