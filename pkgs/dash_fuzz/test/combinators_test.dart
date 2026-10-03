// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';

import 'package:dash_fuzz/dash_fuzz.dart';
import 'package:test/test.dart';

void main() {
  group('Track 1 Combinators & Oracles', () {
    test('verifyChunkSplitEquivalence passes for chunk-invariant parser', () {
      verifyChunkSplitEquivalence<List<int>>(
        generateEncodedStream: (rng) =>
            List<int>.generate(rng.nextInt(30), (_) => rng.nextInt(256)),
        parseFull: (bytes) => bytes,
        parseChunked: (chunks) => [for (final c in chunks) ...c],
        iterations: 50,
      );
    });

    test(
      'verifyChunkSplitEquivalence terminates for maxStep == 1 and rejects < 1',
      () {
        verifyChunkSplitEquivalence<List<int>>(
          generateEncodedStream: (_) => const [10, 20, 30, 40],
          parseFull: (bytes) => bytes,
          parseChunked: (chunks) => [for (final c in chunks) ...c],
          iterations: 10,
          maxStep: 1,
        );
        expect(
          () => verifyChunkSplitEquivalence<List<int>>(
            generateEncodedStream: (_) => const [1],
            parseFull: (bytes) => bytes,
            parseChunked: (chunks) => [for (final c in chunks) ...c],
            maxStep: 0,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'verifyChunkSplitEquivalence throws StateError on chunk-boundary bug',
      () {
        expect(
          () => verifyChunkSplitEquivalence<List<int>>(
            generateEncodedStream: (_) => const [1, 2, 3, 4, 5],
            parseFull: (bytes) => bytes,
            // Buggy chunked parser drops the first byte of every chunk after
            // chunk 0.
            parseChunked: (chunks) {
              final out = <int>[];
              var first = true;
              for (final c in chunks) {
                out.addAll(first ? c : c.skip(1));
                first = false;
              }
              return out;
            },
            iterations: 10,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'captureStreamZoneErrors catches uncaught zone throws and hung streams',
      () async {
        // Simulate MIME-1: a transformer whose onData throws synchronously into
        // the Zone instead of routing to sink.addError.
        final brokenTransformer =
            StreamTransformer<List<int>, int>.fromHandlers(
              handleData: (data, sink) {
                scheduleMicrotask(() {
                  throw const FormatException('escaped to zone');
                });
              },
            );

        final result = await captureStreamZoneErrors<List<int>, int>(
          Stream<List<int>>.value(const [1, 2, 3]),
          brokenTransformer,
        );
        expect(result.uncaughtZoneError, isA<FormatException>());
      },
    );

    test(
      'verifyNoUnescapedCrlf rejects CR, LF, and NUL control characters',
      () {
        verifyNoUnescapedCrlf('session=abc; Domain=example.com');
        expect(
          () => verifyNoUnescapedCrlf('session=abc\r\nX-Injected: 1'),
          throwsStateError,
        );
        expect(
          () => verifyNoUnescapedCrlf('session=abc\nX-Injected: 1'),
          throwsStateError,
        );
        expect(
          () => verifyNoUnescapedCrlf('session=abc\x00'),
          throwsStateError,
        );
      },
    );

    test(
      'boundary corpora include 64-bit signed overflow and 65-bit hex wrap',
      () {
        expect(fuzzBoundaryInts, contains(-9223372036854775808));
        expect(fuzzBoundaryInts, contains(9223372036854775807));
        expect(fuzzBoundaryHexStrings, contains('8000000000000000'));
        expect(fuzzBoundaryHexStrings, contains('10000000000000000'));
      },
    );
  });
}
