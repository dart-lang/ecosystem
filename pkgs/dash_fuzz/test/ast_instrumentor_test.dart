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

    test(
      'skips instrumenting AssertStatement and records both bits in \$fuzzXor',
      () {
        const sample = '''
int check(int a, int b) {
  assert(a == b && a > 0);
  return a ^ b;
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(sample);

        expect(out, contains('assert(a == b && a > 0);'));
        expect(out, isNot(contains(r'$fuzzEq')));
        expect(out, isNot(contains(r'$fuzzGt')));
        expect(out, contains(r'$fuzzXor(a, b,'));
        expect(instrumentor.comparesInserted, equals(1));

        final xorSiteId = instrumentor.sites
            .singleWhere((s) => s.kind == 'cmp')
            .id;
        FuzzRuntime.siteHits[xorSiteId] = 0;
        expect($fuzzXor(5, 5, xorSiteId), equals(0));
        expect(FuzzRuntime.siteHits[xorSiteId], equals(1));
        expect($fuzzXor(5, 3, xorSiteId), equals(6));
        expect(FuzzRuntime.siteHits[xorSiteId], equals(3));
      },
    );

    test(
      'instruments SwitchExpression cases with \$fuzzExpr and unwraps throw',
      () {
        const sample = '''
String describeCode(int code) => switch (code) {
  200 => 'ok',
  404 || 410 => 'missing',
  var c when c >= 500 => 'server_error',
  _ => throw ArgumentError.value(code, 'code'),
};
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(sample);

        // The outer arrow body and the 3 non-throw case arms are wrapped with
        // $fuzzExpr; the throw arm is unwrapped as `throw $fuzzExpr(id, ...)`.
        expect(out, contains(r'=> $fuzzExpr('));
        expect(out, contains(r"=> $fuzzExpr(15470, 'ok')"));
        expect(out, contains(r"=> $fuzzExpr(55973, 'missing')"));
        expect(
          out,
          contains(
            r'var c when $fuzzGe(c, 500, 46410) => '
            r"$fuzzExpr(30940, 'server_error')",
          ),
        );
        expect(
          out,
          contains(
            r"_ => throw $fuzzExpr(5907, ArgumentError.value(code, 'code'))",
          ),
        );

        final parsed = parseString(content: out, throwIfDiagnostics: true);
        expect(parsed.errors, isEmpty);
        expect(instrumentor.edgesInserted, equals(5));
        expect(instrumentor.comparesInserted, equals(1));
      },
    );

    test('instruments ConditionalExpression and ExpressionFunctionBody with '
        '\$fuzzExpr including nested shared-offset expressions', () {
      const sample = '''
int clampSign(int x, bool neg, bool zero) =>
    zero ? 0 : neg ? -x : x;
''';
      final instrumentor = AstInstrumentor();
      final out = instrumentor.instrumentSource(sample);

      expect(out, contains(r'$fuzzBool(zero,'));
      expect(out, contains(r'$fuzzBool(neg,'));
      expect(out, contains(r'$fuzzExpr('));

      final parsed = parseString(content: out, throwIfDiagnostics: true);
      expect(parsed.errors, isEmpty);
      // 1 arrow body + 2 outer ternary arms + 2 inner ternary arms = 5 edges.
      expect(instrumentor.edgesInserted, equals(5));
      // 2 non-binary conditions (`zero` and `neg`) = 2 cmp sites.
      expect(instrumentor.comparesInserted, equals(2));
    });

    test('wraps non-binary conditions in \$fuzzBool while preserving type '
        'promotions and boolean literals', () {
      const sample = '''
int scanItems(List<int> items, Object? maybeText) {
  if (items.isEmpty) return 0;
  if (maybeText is String) {
    return maybeText.length;
  }
  if (!(maybeText != null)) {
    return -1;
  }
  while (true) {
    if (items.first.isEven) break;
    return 1;
  }
  return 2;
}
''';
      final instrumentor = AstInstrumentor();
      final out = instrumentor.instrumentSource(sample);

      expect(out, contains(r'if ($fuzzBool(items.isEmpty,'));
      expect(out, contains(r'if ($fuzzBool(items.first.isEven,'));
      // Type-promotion conditions (`is`, `!= null`) and `while (true)` must
      // not be wrapped in $fuzzBool.
      expect(out, contains('if (maybeText is String)'));
      expect(out, contains('if (!(maybeText != null))'));
      expect(out, contains('while (true)'));
      expect(out, isNot(contains(r'$fuzzBool(true')));

      final parsed = parseString(content: out, throwIfDiagnostics: true);
      expect(parsed.errors, isEmpty);
      expect(instrumentor.comparesInserted, equals(2));
    });

    test(
      'wraps braceless for, while, and do loop bodies with \$fuzzEdge blocks',
      () {
        const sample = '''
int sumUp(List<int> xs) {
  var total = 0;
  for (var i = 0; i < xs.length; i++) total += xs[i];
  while (total > 100) total -= 10;
  do total++; while (total < 10);
  return total;
}
''';
        final instrumentor = AstInstrumentor();
        final out = instrumentor.instrumentSource(sample);

        expect(out, contains(r'{ $fuzzEdge(15470); total += xs[i]; }'));
        expect(out, contains(r'{ $fuzzEdge(30940); total -= 10; }'));
        expect(out, contains(r'{ $fuzzEdge(46410); total++; }'));

        final parsed = parseString(content: out, throwIfDiagnostics: true);
        expect(parsed.errors, isEmpty);
        // 1 function body + 3 braceless loop bodies = 4 edges.
        expect(instrumentor.edgesInserted, equals(4));
        // 3 binary loop conditions = 3 cmp sites.
        expect(instrumentor.comparesInserted, equals(3));
      },
    );

    test('preserves flow promotions in ConditionalExpression branches, unwraps '
        'parenthesized throws, skips all-throwing outer wrappers and async=>, '
        'and supports bool \$fuzzXor and PatternAssignment conditions', () {
      const sample = '''
Future<void> asyncVoidArrow(String msg) async => print(msg);

int condPromotion(int? x, bool flag) {
  if (flag ? x != null : false) {
    return x;
  }
  if ((flag ? x is int : false) && x.isEven) {
    return x;
  }
  return 0;
}

Never alwaysThrowsSwitch(int code) => switch (code) {
  0 => throw StateError('0'),
  _ => (throw ArgumentError('other')),
};

bool checkBoolXor(bool a, bool b, List<(int?, bool)> items) {
  int? x;
  var ok = false;
  while (((x, ok) = items.first).\$2) {
    if (a ^ b) return x != null;
  }
  return false;
}

int nullAwareAssignPromotion(int? position, RegExpMatch? match) {
  position ??= match == null ? 0 : match.start;
  return position + 1;
}
''';
      final instrumentor = AstInstrumentor();
      final out = instrumentor.instrumentSource(sample);

      // async => is not wrapped in $fuzzExpr to preserve void expressions.
      expect(
        out,
        contains(
          'Future<void> asyncVoidArrow(String msg) async => print(msg);',
        ),
      );
      // ConditionalExpression branches with `!= null`, `is`, or `false` stay
      // unwrapped so Dart flow-analysis type promotion is preserved.
      expect(out, contains(r'if ($fuzzBool(flag, 15470) ? x != null : false)'));
      expect(
        out,
        contains(
          r'if (($fuzzBool(flag, 30940) ? x is int : false) && x.isEven)',
        ),
      );
      // All-throwing SwitchExpression omits an unreachable outer $fuzzExpr
      // while unwrapping parenthesized `(throw ...)` inside its arm.
      expect(
        out,
        contains(r'Never alwaysThrowsSwitch(int code) => switch (code) {'),
      );
      expect(
        out,
        contains(r"_ => (throw $fuzzExpr(21377, ArgumentError('other')))"),
      );
      // PatternAssignment loop condition is not wrapped in $fuzzBool, and
      // `a ^ b` uses generic `$fuzzXor`.
      expect(out, contains(r'while (((x, ok) = items.first).$2)'));
      expect(out, contains(r'if ($fuzzXor(a, b, 52317))'));
      // AssignmentExpression RHS ConditionalExpression arms stay unwrapped so
      // downward context `int?` does not widen `$fuzzExpr<T>` and block LHS
      // promotion to `int`.
      expect(out, contains('position ??= match == null ? 0 : match.start;'));

      final parsed = parseString(content: out, throwIfDiagnostics: true);
      expect(parsed.errors, isEmpty);

      // Verify generic $fuzzXor on bool operands.
      FuzzRuntime.siteHits[52317] = 0;
      expect($fuzzXor(true, false, 52317), isTrue);
      expect(FuzzRuntime.siteHits[52317], equals(1));
      expect($fuzzXor(true, true, 52317), isFalse);
      expect(FuzzRuntime.siteHits[52317], equals(3));
    });
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

      // edge_manifest.json records all sites and computes exact per-file stats.
      final manifestJson = File(res.edgeManifestPath).readAsStringSync();
      FuzzRuntime.siteHits.fillRange(0, FuzzRuntime.numCounters, 0);
      final manifestMap = jsonDecode(manifestJson) as Map<String, Object?>;
      final sites = (manifestMap['sites'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        sites.length,
        equals(res.edgesInserted + res.comparesInserted + res.switchesInserted),
      );

      final firstId = sites.first['id'] as int;
      $fuzzEdge(firstId);
      final report = computeCoverageReport(
        edgeManifestJson: manifestJson,
        siteHits: FuzzRuntime.siteHits,
      );
      expect(report.packageName, equals('sample_pkg'));
      expect(report.hitSites, equals(1));
      expect(report.totalSites, equals(sites.length));
      expect(report.files.map((f) => f.file), [
        'lib/sample_pkg.dart',
        'lib/src/part_file.dart',
      ]);
      expect(formatCoverageTable(report), contains('lib/sample_pkg.dart'));
    });
  });
}
