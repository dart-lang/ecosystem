// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Standard 64-bit signed/unsigned integer boundary values for stressing length
/// and size parsers (`HP-1`, `HP-2`, `ASN1-1`, `RFW-1`, `RFW-2`).
const List<int> fuzzBoundaryInts = [
  -9223372036854775808, // -2^63 (0x8000000000000000 signed overflow)
  -2147483649,
  -2147483648,
  -65536,
  -256,
  -1,
  0,
  1,
  127,
  128,
  255,
  256,
  65535,
  65536,
  2147483647,
  2147483648,
  4294967295,
  4294967296,
  9223372036854775807, // 2^63 - 1 (max signed 64-bit int)
];

/// Hexadecimal string boundaries covering 32-bit, 64-bit signed (`2^63`), and
/// 65-bit (`2^64` shift wrap-to-zero) chunk length edge cases.
const List<String> fuzzBoundaryHexStrings = [
  '0',
  '7fffffff',
  '80000000',
  'ffffffff',
  '7fffffffffffffff',
  '8000000000000000',
  'ffffffffffffffff',
  '10000000000000000',
  '10000000000000003',
];

/// Result of running a streaming parser inside [captureStreamZoneErrors].
typedef StreamContractResult<T> =
    ({
      List<T> items,
      Object? streamError,
      Object? uncaughtZoneError,
      bool completed,
    });

/// Verifies that a chunked or streaming parser produces identical output when a
/// valid encoded byte stream is split across arbitrary chunk boundaries
/// (`0`-byte, `1`-byte, and random `1..maxStep`-byte slices).
///
/// Throws a [StateError] with a detailed diff if any chunk split diverges from
/// the single-buffer conversion result.
void verifyChunkSplitEquivalence<T>({
  required List<int> Function(Random rng) generateEncodedStream,
  required T Function(List<int> fullBytes) parseFull,
  required T Function(Iterable<List<int>> chunks) parseChunked,
  bool Function(T a, T b)? equals,
  int iterations = 200,
  int maxStep = 7,
  int seed = 12345,
}) {
  final rng = Random(seed);
  final cmp = equals ?? _defaultEquals;
  for (var iter = 0; iter < iterations; iter++) {
    final fullPayload = generateEncodedStream(rng);
    final expected = parseFull(fullPayload);
    final chunks = _sliceIntoRandomChunks(fullPayload, rng, maxStep);
    final actual = parseChunked(chunks);
    if (!cmp(expected, actual)) {
      throw StateError(
        'Chunk-split equivalence failed on iteration $iter '
        '(payload: ${fullPayload.length} bytes, ${chunks.length} chunks):\n'
        '  Expected: $expected\n'
        '  Actual:   $actual',
      );
    }
  }
}

List<List<int>> _sliceIntoRandomChunks(
  List<int> fullPayload,
  Random rng,
  int maxStep,
) {
  final chunks = <List<int>>[];
  var offset = 0;
  while (offset < fullPayload.length) {
    final step = rng.nextInt(maxStep);
    final end = min(offset + step, fullPayload.length);
    chunks.add(fullPayload.sublist(offset, end));
    offset = end;
  }
  return chunks;
}

bool _defaultEquals<T>(T a, T b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}

/// Runs an asynchronous [StreamTransformer] inside a guarded [Zone], ensuring
/// subscriptions are deterministically cancelled and detecting uncaught zone
/// errors or hung output streams (`MIME-1` pattern).
Future<StreamContractResult<T>> captureStreamZoneErrors<S, T>(
  Stream<S> input,
  StreamTransformer<S, T> transformer, {
  Duration timeout = const Duration(milliseconds: 50),
}) async {
  final items = <T>[];
  Object? streamError;
  Object? uncaughtZoneError;
  var completed = false;
  StreamSubscription<T>? subscription;

  final doneCompleter = Completer<void>();

  await runZonedGuarded(
    () async {
      final transformed = input.transform(transformer);
      subscription = transformed.listen(
        items.add,
        onError: (Object error) {
          streamError = error;
          completed = true;
          if (!doneCompleter.isCompleted) doneCompleter.complete();
        },
        onDone: () {
          completed = true;
          if (!doneCompleter.isCompleted) doneCompleter.complete();
        },
        cancelOnError: true,
      );
      await doneCompleter.future.timeout(timeout, onTimeout: () {});
    },
    (error, _) {
      uncaughtZoneError = error;
      if (!doneCompleter.isCompleted) doneCompleter.complete();
    },
  );

  await subscription?.cancel();
  return (
    items: items,
    streamError: streamError,
    uncaughtZoneError: uncaughtZoneError,
    completed: completed,
  );
}

/// Verifies that a serialized header/cookie/URI value never contains raw CR
/// (`\r`), LF (`\n`), or NUL (`\x00`) control characters (`HTTP-2` oracle).
void verifyNoUnescapedCrlf(String serialized, {String context = 'serialized'}) {
  for (var i = 0; i < serialized.length; i++) {
    final cu = serialized.codeUnitAt(i);
    if (cu == 0x0D || cu == 0x0A || cu == 0x00) {
      final hex = utf8
          .encode(serialized)
          .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
          .join(', ');
      throw StateError(
        'Unescaped control character (0x${cu.toRadixString(16)}) found in '
        '$context at index $i: [$hex]',
      );
    }
  }
}
