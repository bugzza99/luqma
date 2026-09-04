import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
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
  /// Both of these name a city, and neither is complete without one: `home_sections` is
  /// keyed `(key, cityId)`, so the same `key` exists once per city. Without the city
  /// these act on every city that has a section by that name.
  Future<Result<void>> setVisible(String key, bool isVisible,
      {required String cityId});
  Future<Result<void>> reorder(List<String> keysInOrder, {required String cityId});
}

class SupabaseHomeSectionRepository implements HomeSectionRepository {
  SupabaseHomeSectionRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<HomeSection>> watchSections({required String cityId}) {
    return watchRows(
      db: _db,
      table: 'home_sections',
      filters: [RowFilter('city_id', cityId)],
      orderBy: 'sort_order',
      map: (row) => HomeSection.fromJson(ColumnNames.toModel(row)),
    );
  }

  @override
  Future<Result<void>> save(HomeSection section) {
    return Result.guard(() async {
      // Upsert on the composite primary key: saving is create-or-replace, as it always
      // was. A section names its city — the key demands it — so the model's nullable
      // `cityId` must be filled before this is called, exactly as the table says.
      await _db.from('home_sections').upsert(
            ColumnNames.toRow(section.toJson()),
            onConflict: 'key,city_id',
          );
    });
  }

  @override
  Future<Result<void>> setVisible(String key, bool isVisible,
      {required String cityId}) {
    return Result.guardWrite(
      () => _db.from('home_sections').update({
        'is_visible': isVisible,
      }).eq('key', key).eq('city_id', cityId).select('key'),
      (_) {},
    );
  }

  @override
  Future<Result<void>> reorder(List<String> keysInOrder,
      {required String cityId}) {
    return Result.guard(
      () => _db.rpc('reorder_home_sections', params: {
        'p_keys': keysInOrder,
        'p_city_id': cityId,
      }),
    );
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
  Future<Result<void>> setVisible(String key, bool isVisible,
      {required String cityId}) async {
    if (failure != null) return Result.err(failure!);
    final i = _sections.indexWhere((s) => s.key == key && s.cityId == cityId);
    if (i < 0) return const Result.err(NotFoundFailure());
    _sections[i] = _sections[i].copyWith(isVisible: isVisible);
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reorder(List<String> keysInOrder,
      {required String cityId}) async {
    if (failure != null) return Result.err(failure!);
    for (var i = 0; i < keysInOrder.length; i++) {
      final index = _sections
          .indexWhere((s) => s.key == keysInOrder[i] && s.cityId == cityId);
      if (index >= 0) _sections[index] = _sections[index].copyWith(sortOrder: i);
    }
    _notify();
    return const Result.ok(null);
  }
}
