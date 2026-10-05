// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:dash_fuzz/dash_fuzz.dart';
import 'package:dash_fuzz/src/native_builder.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('NativeFuzzerBuilder', () {
    test('fails hard with ToolchainMissingException and pure-dart hint when '
        'clang++ is missing', () async {
      expect(
        NativeFuzzerBuilder.findClangExecutable(
          environment: {'CLANG_CXX': '/nonexistent/clang++'},
        ),
        isNull,
      );

      await expectLater(
        () => NativeFuzzerBuilder.buildSharedLibrary(
          outputDir: d.sandbox,
          clangExecutable: '/nonexistent/clang++',
        ),
        throwsA(
          isA<ToolchainMissingException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('--mode=cgf'),
              contains('--mode=pure-dart'),
              contains('clang'),
              contains('libclang-rt-dev'),
            ),
          ),
        ),
      );
    });
  });

  group('FuzzRuntime (Pure-Dart Mode)', () {
    test('records edge and comparison feedback and drives pure-Dart mutator '
        'including LHS constants and List<int> equality', () {
      FuzzRuntime.init(mode: FuzzMode.pureDart);
      FuzzRuntime.covMap.fillRange(0, FuzzRuntime.numCounters, 0);
      FuzzRuntime.prevLoc = 0;

      $fuzzEdge(101);
      expect($fuzzEq(1000, 1000, 202), isTrue);
      expect($fuzzNe('alpha', 'beta', 303), isTrue);
      expect($fuzzLt(0, 4, 404), isTrue);
      expect($fuzzLe(4, 4, 405), isTrue);
      expect($fuzzGt(9, 4, 406), isTrue);
      expect($fuzzGe(9, 9, 407), isTrue);
      expect($fuzzXor(0x41, 0x61, 505), equals(0x20));
      expect($fuzzSwitch('hdr', <Object?>['hdr', 'body'], 606), 'hdr');
      expect($fuzzExpr(707, 'payload'), equals('payload'));
      expect(FuzzRuntime.siteHits[707], equals(1));

      FuzzRuntime.siteHits[808] = 0;
      expect($fuzzBool(true, 808), isTrue);
      expect(FuzzRuntime.siteHits[808], equals(1));
      expect($fuzzBool(false, 808), isFalse);
      expect(FuzzRuntime.siteHits[808], equals(3));

      final nonZero = FuzzRuntime.covMap.where((b) => b != 0).length;
      expect(nonZero, greaterThanOrEqualTo(8));

      var foundRhsMagic = false;
      var foundLhsMagic = false;
      FuzzRuntime.runDriver(
        (Uint8List data) {
          $fuzzEdge(1);
          if ($fuzzGe(data.length, 4, 10)) {
            $fuzzEdge(2);
            final str = String.fromCharCodes(data.take(4));
            if ($fuzzEq(str, 'FUZZ', 20)) {
              foundRhsMagic = true;
            }
            if ($fuzzEq('DART', str, 30)) {
              foundLhsMagic = true;
            }
          }
          return 0;
        },
        mode: FuzzMode.pureDart,
        fuzzerArgs: const ['-runs=3000', '-max_len=16'],
      );
      expect(foundRhsMagic, isTrue);
      expect(foundLhsMagic, isTrue);
    });
  });

  group('FuzzRuntime (Native CGF Mode)', () {
    test('compiles fuzzer.cc, links libFuzzer counters, and solves List<int> '
        'comparisons when clang++ is available', () async {
      final clang = NativeFuzzerBuilder.findClangExecutable();
      if (clang == null) {
        markTestSkipped('clang++ not installed on this runner');
        return;
      }

      final libPath = await NativeFuzzerBuilder.buildSharedLibrary(
        outputDir: d.sandbox,
        clangExecutable: clang,
      );
      FuzzRuntime.init(mode: FuzzMode.cgf, libraryPath: libPath);
      FuzzRuntime.covMap.fillRange(0, FuzzRuntime.numCounters, 0);
      FuzzRuntime.prevLoc = 0;

      $fuzzEdge(77);
      expect($fuzzEq(0xCAFEBABE, 0xCAFEBABE, 88), isTrue);
      expect($fuzzEq('magic', 'magic', 99), isTrue);
      expect($fuzzEq(const [0x46, 0x55], const [0x46, 0x5A], 100), isFalse);
      expect(
        FuzzRuntime.covMap.where((b) => b != 0).length,
        greaterThanOrEqualTo(4),
      );

      // Verify switching to pureDart and back to cgf preserves native siteHits
      // buffer identity.
      final nativeSiteHitsRef = FuzzRuntime.siteHits;
      FuzzRuntime.init(mode: FuzzMode.pureDart);
      expect(identical(FuzzRuntime.siteHits, nativeSiteHitsRef), isTrue);
      FuzzRuntime.init(mode: FuzzMode.cgf, libraryPath: libPath);
      expect(identical(FuzzRuntime.siteHits, nativeSiteHitsRef), isTrue);
    });
  });
}
