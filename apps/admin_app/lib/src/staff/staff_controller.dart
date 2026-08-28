import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'staff_controller.g.dart';

/// Every platform account, active first.
@riverpod
Stream<List<StaffMember>> staffList(Ref ref) =>
    ref.watch(staffRepositoryProvider).watchStaff();
