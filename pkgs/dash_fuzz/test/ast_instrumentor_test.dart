// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dash_fuzz/dash_fuzz.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('AstInstrumentor', () {
    test(
      'instruments edges, comparisons, and switches while preserving consts',
      () {
        const sample = '''
library sample;

const int kMagic = 1 + 2;

class Demo {
  const Demo([int x = 3 == 3 ? 1 : 0]);
}

int check(int a, String s) {
  if (a == 42) return 1;
  switch (s) {
    case 'foo':
      return 2;
    default:
      return a ^ 7;
  }
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(sample);

        expect(out, contains("import 'package:dash_fuzz/dash_fuzz.dart';"));
        expect(out, contains(r'$fuzzEdge('));
        expect(out, contains(r'$fuzzEq(a, 42,'));
        expect(out, contains(r'$fuzzSwitch(s,'));
        expect(out, contains(r'$fuzzXor(a, 7,'));
        expect(out, contains('const int kMagic = 1 + 2;'));
        expect(out, contains('const Demo([int x = 3 == 3 ? 1 : 0]);'));

        final parsed = parseString(content: out, throwIfDiagnostics: true);
        expect(parsed.errors, isEmpty);
        expect(instrumentor.edgesInserted, greaterThan(0));
        expect(instrumentor.comparesInserted, equals(2));
        expect(instrumentor.switchesInserted, equals(1));
      },
    );

    test(
      'omits import directive in `part of` files to preserve valid syntax',
      () {
        const partSample = '''
part of 'sample.dart';

bool isHeaderByte(int b) {
  if (b == 0xFE) return true;
  return b < 0x20;
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(partSample);

        expect(out, isNot(contains('import ')));
        expect(out, contains(r'$fuzzEq(b, 0xFE,'));
        expect(out, contains(r'$fuzzLt(b, 0x20,'));

        final parsed = parseString(content: out, throwIfDiagnostics: true);
        expect(parsed.errors, isEmpty);
      },
    );

    test(
      'preserves == null and != null for Dart flow-analysis type promotion',
      () {
        const nullPromotionSample = '''
int promotedLength(String? value, bool flag) {
  if (value != null && flag == true) {
    return value.length;
  }
  return 0;
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(nullPromotionSample);

        expect(out, contains('value != null'));
        expect(out, contains('flag == true'));
        expect(out, isNot(contains(r'$fuzzNe(value, null')));
        expect(out, isNot(contains(r'$fuzzEq(flag, true')));
        expect(instrumentor.comparesInserted, equals(0));
        expect(instrumentor.edgesInserted, greaterThan(0));
      },
    );

    test(
      'preserves ConstantPattern in if-case and instruments switch when guards',
      () {
        const patternSample = '''
int evalPattern(int x) {
  if (x case const (1 ^ 2)) {
    return 1;
  }
  switch (x) {
    case var v when v > 10 && v == 42:
      return 2;
    default:
      return 0;
  }
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(patternSample);

        // ConstantPattern inside if-case must stay a valid constant expression.
        expect(out, contains('if (x case const (1 ^ 2))'));
        expect(out, isNot(contains(r'const ($fuzzXor')));

        // Runtime guard expression in `when` clause must be instrumented.
        expect(out, contains(r'$fuzzGt(v, 10,'));
        expect(out, contains(r'$fuzzEq(v, 42,'));

        final parsed = parseString(content: out, throwIfDiagnostics: true);
        expect(parsed.errors, isEmpty);
      },
    );
  });

  group('PackageOverlayInstrumentor', () {
    test('creates non-destructive .dart_tool/dash_fuzz/ overlay for multi-file package', () async {
      await d.dir('sample_pkg', [
        d.file('pubspec.yaml', '''
name: sample_pkg
environment:
  sdk: ^3.7.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'sample_pkg',
                  'rootUri': '../',
                  'packageUri': 'lib/',
                  'languageVersion': '3.7',
                },
              ],
            }),
          ),
        ]),
        d.dir('lib', [
          d.file('sample_pkg.dart', '''
library sample_pkg;

part 'src/part_file.dart';

int parseRoot(int x) {
  if (x == 10) return _parsePart(x);
  return 0;
}
'''),
          d.dir('src', [
            d.file('part_file.dart', '''
part of '../sample_pkg.dart';

int _parsePart(int x) => x > 5 ? 1 : 0;
'''),
          ]),
        ]),
      ]).create();

      final pkgRoot = p.join(d.sandbox, 'sample_pkg');
      final originalLib = File(p.join(pkgRoot, 'lib', 'sample_pkg.dart'))
          .readAsStringSync();

      final res = await PackageOverlayInstrumentor.instrumentPackage(
        packageRoot: pkgRoot,
      );

      expect(res.packageName, equals('sample_pkg'));
      expect(res.filesInstrumented, equals(2));
      expect(res.edgesInserted, greaterThan(0));
      expect(res.comparesInserted, equals(2));

      // Original source in lib/ must remain 100% untouched.
      expect(
        File(p.join(pkgRoot, 'lib', 'sample_pkg.dart')).readAsStringSync(),
        equals(originalLib),
      );

      // Instrumented library root has import; part file does not.
      final instRoot = File(p.join(res.instrumentedLibDir, 'sample_pkg.dart'))
          .readAsStringSync();
      final instPart = File(
        p.join(res.instrumentedLibDir, 'src', 'part_file.dart'),
      ).readAsStringSync();
      expect(instRoot, contains("import 'package:dash_fuzz/dash_fuzz.dart';"));
      expect(instPart, isNot(contains('import ')));
      expect(instPart, contains(r'$fuzzGt(x, 5,'));

      // Overlay package_config.json remaps sample_pkg and injects dash_fuzz.
      final overlayJson = jsonDecode(
        File(res.overlayPackageConfigPath).readAsStringSync(),
      ) as Map<String, Object?>;
      final packages = (overlayJson['packages'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final sampleEntry = packages.singleWhere(
        (e) => e['name'] == 'sample_pkg',
      );
      final dashFuzzEntry = packages.singleWhere(
        (e) => e['name'] == 'dash_fuzz',
      );
      expect(
        sampleEntry['rootUri'] as String,
        endsWith('.dart_tool/dash_fuzz/instrumented'),
      );
      expect(dashFuzzEntry['packageUri'], equals('lib/'));
    });
  });
}
