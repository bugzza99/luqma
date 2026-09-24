import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';
import '../support/order_helper.dart';

/// What «زعتر» decided a customer's typed question is about.
///
/// A verdict and not a reply: the server chooses one of the five [HelpTopic]s and the
/// sentence the customer reads is rendered here, by [OrderHelper.answer], from the order
/// the customer is already looking at. There is one answer specification in this product
/// and this is the side of the wire it lives on — the Edge Function used to carry a second
/// copy of those templates in TypeScript, which is two things that must agree for ever and
/// no test that they do.
class ZaatarVerdict {
  const ZaatarVerdict({required this.topic, required this.fromModel});

  /// The topic to answer from.
  final HelpTopic topic;

  /// True when the model chose it, false when the server read it off the words itself.
  /// Nothing in the product renders differently either way; it is here because "did this
  /// cost a turn" is a question worth being able to answer.
  final bool fromModel;

  /// The Edge Function's `{intent, source}`. An intent outside the five is «حاجة تانية»,
  /// which is what the assistant hands to a person anyway.
  factory ZaatarVerdict.fromJson(Map<String, dynamic> json) => ZaatarVerdict(
        topic: topicOf(json['intent']),
        fromModel: json['source'] == 'model',
      );

  /// Exact names only — «LATE» is not «late» — and anything else is «حاجة تانية».
  static HelpTopic topicOf(Object? intent) => HelpTopic.values.firstWhere(
        (topic) => topic.name == intent,
        orElse: () => HelpTopic.other,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZaatarVerdict &&
          runtimeType == other.runtimeType &&
          topic == other.topic &&
          fromModel == other.fromModel;

  @override
  int get hashCode => Object.hash(topic, fromModel);

  @override
  String toString() => 'ZaatarVerdict(topic: $topic, fromModel: $fromModel)';
}

/// The smart complaints assistant «زعتر».
abstract interface class ZaatarRepository {
  /// Sends the customer's question about one order and gets back what it is about.
  ///
  /// A [Failure] means "answer from the rules on this phone" — the screen reads the topic
  /// out of the words itself and says so. It is never a dead end.
  Future<Result<ZaatarVerdict>> ask({
    required String orderId,
    required String message,
  });
}

/// Supabase Edge Function implementation of [ZaatarRepository].
class SupabaseZaatarRepository implements ZaatarRepository {
  SupabaseZaatarRepository(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final SupabaseClient _client;
  final Duration timeout;

  @override
  Future<Result<ZaatarVerdict>> ask({
    required String orderId,
    required String message,
  }) {
    return Result.guard(() async {
      try {
        final response = await _client.functions.invoke(
          'zaatar',
          body: {'orderId': orderId, 'message': message},
        ).timeout(timeout);

        final status = response.status;
        final data = response.data;

        // The function itself answers locally rather than rate-limiting, but the gateway
        // in front of it can still say 429 on its own.
        if (status == 429) throw const RateLimitedFailure();
        if (status == 503) throw const UnknownFailure('fallback');

        if (status >= 400) {
          if (data is Map && data['fallback'] == true) {
            throw const UnknownFailure('fallback');
          }
          if (status == 401 || status == 403) throw const PermissionFailure();
          if (status == 404) throw const NotFoundFailure();
          throw UnknownFailure('zaatar: HTTP $status');
        }

        if (data is! Map) throw const UnknownFailure('fallback');

        final map = Map<String, dynamic>.from(data);
        if (map['fallback'] == true) throw const UnknownFailure('fallback');
        // No intent at all is not «other»: it is a reply we do not understand, and the
        // phone's own reading of the words is better than guessing.
        if (map['intent'] is! String) throw const UnknownFailure('fallback');

        return ZaatarVerdict.fromJson(map);
      } on TimeoutException {
        throw const UnknownFailure('fallback');
      } on FunctionException catch (e) {
        final details = e.details;
        if (e.status == 429) throw const RateLimitedFailure();
        if (e.status == 503 || (details is Map && details['fallback'] == true)) {
          throw const UnknownFailure('fallback');
        }
        if (e.status == 401 || e.status == 403) throw const PermissionFailure();
        if (e.status == 404) throw const NotFoundFailure();
        throw const UnknownFailure('fallback');
      } catch (e) {
        if (e is Failure) rethrow;
        throw const UnknownFailure('fallback');
      }
    });
  }
}

/// In-memory [ZaatarRepository] for tests and for the screens to be built against.
class FakeZaatarRepository implements ZaatarRepository {
  FakeZaatarRepository({
    List<ZaatarVerdict> scripted = const [],
    this.failure,
    this.fallback = false,
  }) : _scripted = List.of(scripted);

  final List<ZaatarVerdict> _scripted;
  Failure? failure;
  bool fallback;

  /// Recorded calls, for asserting what the screen actually sent.
  final List<({String orderId, String message})> calls = [];

  void enqueue(ZaatarVerdict verdict) => _scripted.add(verdict);

  @override
  Future<Result<ZaatarVerdict>> ask({
    required String orderId,
    required String message,
  }) async {
    calls.add((orderId: orderId, message: message));

    if (fallback) return const Result.err(UnknownFailure('fallback'));
    if (failure != null) return Result.err(failure!);
    if (_scripted.isNotEmpty) return Result.ok(_scripted.removeAt(0));
    return const Result.ok(
      ZaatarVerdict(topic: HelpTopic.other, fromModel: false),
    );
  }
}
