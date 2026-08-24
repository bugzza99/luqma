import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../result.dart';

/// One customer's verdict on one order.
///
/// Not a `freezed` model: it is read and never written by any client — the customer app
/// writes the `ratings` row, and everything downstream of that only reads. A model with
/// a `toJson` would invite somebody to write one back.
class CustomerRating {
  const CustomerRating({
    required this.orderId,
    required this.merchantId,
    required this.stars,
    this.comment,
    this.createdAt,
  });

  final String orderId;
  final String merchantId;
  final int stars;

  /// Null far more often than not: most people rate without typing. Treating a missing
  /// comment as nothing to show would make the list look like nothing but complaints,
  /// because complaints are what people bother to write.
  final String? comment;

  final DateTime? createdAt;

  factory CustomerRating.fromJson(Map<String, dynamic> json) => CustomerRating(
    orderId: json['orderId'] as String,
    merchantId: json['merchantId'] as String,
    stars: (json['stars'] as num).toInt(),
    comment: json['comment'] as String?,
    // Local, as Firestore's Timestamp.toDate() always handed back.
    createdAt: switch (json['createdAt']) {
      null => null,
      String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    },
  );
}

/// What customers said, as the merchant reads it.
///
/// Private on purpose. Stars aggregate onto the merchant and are public; the words stay
/// between the customer, the merchant and the admin until the public-comments flag is
/// turned on. A merchant who reads honest criticism in private fixes it; one who reads
/// it in public argues with it.
abstract interface class FeedbackRepository {
  Stream<List<CustomerRating>> watchFeedback(String merchantId);
}

class SupabaseFeedbackRepository implements FeedbackRepository {
  SupabaseFeedbackRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<CustomerRating>> watchFeedback(String merchantId) {
    return watchRows(
      db: _db,
      table: 'ratings',
      map: (row) => CustomerRating.fromJson(ColumnNames.toModel(row)),
      filters: [RowFilter('merchant_id', merchantId)],
      // Sorted here rather than trusting an order: this list is a few dozen rows at most.
    ).map(
      (ratings) => ratings..sort((a, b) {
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      }),
    );
  }
}

class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository({List<CustomerRating> seed = const [], this.failure})
    : _feedback = List.of(seed);

  final List<CustomerRating> _feedback;
  final Failure? failure;

  @override
  Stream<List<CustomerRating>> watchFeedback(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(_feedback.where((f) => f.merchantId == merchantId).toList());
  }
}
