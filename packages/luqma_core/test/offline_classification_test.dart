import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Whether a dropped connection is recognised as one.
///
/// `OfflineFailure` was declared, and read in five places — "مفيش نت — جرّب تاني" on the
/// error view, on the media picker, on the admin gate — and **nothing ever produced it**.
/// `Failure.from` classified `PostgrestException` carefully and sent everything else to
/// `UnknownFailure`, so a phone with no signal reported "حصل خطأ" and the offline
/// sentence was unreachable text.
///
/// The expensive half is the courier. `CourierWriteQueue` queues a write only when the
/// failure `is OfflineFailure` and rejects everything else, so the one class in this
/// product built to keep a "delivered" tap alive through a dead connection was rejecting
/// every real one. Its own tests passed because they injected `OfflineFailure` directly
/// and never went near the classifier.
void main() {
  test('no route to the host is offline', () {
    expect(
      Failure.from(const SocketException('Failed host lookup')),
      isA<OfflineFailure>(),
    );
  });

  test('a connection closed mid-request is offline', () {
    expect(
      Failure.from(http.ClientException('Connection closed before full header')),
      isA<OfflineFailure>(),
    );
  });

  test('a request that never came back is offline', () {
    expect(
      Failure.from(TimeoutException('no response', const Duration(seconds: 30))),
      isA<OfflineFailure>(),
    );
  });

  test('a refused TLS handshake is offline', () {
    expect(
      Failure.from(const HandshakeException('connection terminated')),
      isA<OfflineFailure>(),
    );
  });

  test('a failure that already knows what it is passes through', () {
    expect(Failure.from(const ConflictFailure()), isA<ConflictFailure>());
  });

  test('and anything genuinely unrecognised still is', () {
    // Not everything is the network. A type error is a bug, and dressing it as "no
    // connection" would send somebody to check their wifi over a crash.
    expect(Failure.from(ArgumentError('bad')), isA<UnknownFailure>());
  });

  test('a refusal from the database is still classified as before', () {
    expect(
      Failure.from(PostgrestException(message: 'no', code: '42501')),
      isA<PermissionFailure>(),
    );
  });
}
