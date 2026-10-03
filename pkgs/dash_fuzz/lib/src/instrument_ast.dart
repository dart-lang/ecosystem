// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

/// Metadata for a single AST-instrumented control-flow or comparison site.
typedef FuzzSiteEntry = ({
  int id,
  String file,
  int line,
  int column,
  String kind,
});

enum _EditKind {
  /// Inserted at the end of an inner node (innermost first).
  suffix,

  /// Replaces an operator token.
  replace,

  /// Inserted at the start of an outer node (outermost first).
  prefix,
}

class _SourceEdit implements Comparable<_SourceEdit> {
  final int start;
  final int end;
  final _EditKind kind;
  final int depth;
  final String replacement;

  _SourceEdit({
    required this.start,
    required this.end,
    required this.kind,
    required this.depth,
    required this.replacement,
  });

  @override
  int compareTo(_SourceEdit other) {
    final cmpStart = start.compareTo(other.start);
    if (cmpStart != 0) return cmpStart;
    final cmpEnd = end.compareTo(other.end);
    if (cmpEnd != 0) return cmpEnd;
    final cmpKind = kind.index.compareTo(other.kind.index);
    if (cmpKind != 0) return cmpKind;
    // Prefix edits order outermost first; others order innermost first.
    return kind == _EditKind.prefix
        ? depth.compareTo(other.depth)
        : other.depth.compareTo(depth);
  }
}

/// Rewrites Dart source files with SanitizerCoverage-style edge and comparison
/// hooks (`$fuzzEdge`, `$fuzzEq`, `$fuzzLt`, `$fuzzSwitch`, etc.).
class AstInstrumentor {
  int _nextId = 1;
  int edgesInserted = 0;
  int comparesInserted = 0;
  int switchesInserted = 0;

  /// Every AST site instrumented across one or more [instrumentSource] calls.
  final List<FuzzSiteEntry> sites = [];

  int _allocSite({
    required int offset,
    required String kind,
    required LineInfo lineInfo,
    required String filePath,
  }) {
    final id = (_nextId * 40503) & 0xFFFF;
    _nextId++;
    final nonZeroId = id == 0 ? 1 : id;
    final loc = lineInfo.getLocation(offset);
    sites.add((
      id: nonZeroId,
      file: filePath,
      line: loc.lineNumber,
      column: loc.columnNumber,
      kind: kind,
    ));
    return nonZeroId;
  }

  /// Instruments [source] with `$fuzzEdge`, `$fuzzEq`/`$fuzzLt`/etc., and
  /// `$fuzzSwitch` calls into [runtimeImport].
  ///
  /// Automatically omits the `import` directive if [source] is a `part of`
  /// compilation unit (which inherits imports from its owning library).
  String instrumentSource(
    String source, {
    String runtimeImport = 'package:dash_fuzz/dash_fuzz.dart',
    bool addImport = true,
    String filePath = '<memory>',
  }) {
    final parseResult = parseString(content: source, throwIfDiagnostics: false);
    final unit = parseResult.unit;
    final visitor = _InstrumentVisitor(
      this,
      filePath: filePath,
      lineInfo: parseResult.lineInfo,
    );
    unit.accept(visitor);

    final edits = visitor.edits..sort();

    final sb = StringBuffer();
    var cursor = 0;
    for (final edit in edits) {
      if (edit.start < cursor) continue;
      sb.write(source.substring(cursor, edit.start));
      sb.write(edit.replacement);
      cursor = edit.end;
    }
    sb.write(source.substring(cursor));

    final instrumentedBody = sb.toString();
    final isPartOf = unit.directives.any((d) => d is PartOfDirective);
    if (!addImport || isPartOf) return instrumentedBody;

    final insertPos = _findImportInsertOffset(unit);
    return '${instrumentedBody.substring(0, insertPos)}\n'
        "import '$runtimeImport';\n"
        '${instrumentedBody.substring(insertPos)}';
  }

  static int _findImportInsertOffset(CompilationUnit unit) {
    for (final directive in unit.directives) {
      if (directive is LibraryDirective) return directive.end;
    }
    if (unit.directives.isNotEmpty) {
      return unit.directives.first.offset;
    }
    if (unit.declarations.isNotEmpty) {
      return unit.declarations.first.offset;
    }
    return 0;
  }
}

class _InstrumentVisitor extends RecursiveAstVisitor<void> {
  final AstInstrumentor owner;
  final String filePath;
  final LineInfo lineInfo;
  final List<_SourceEdit> edits = [];

  _InstrumentVisitor(
    this.owner, {
    required this.filePath,
    required this.lineInfo,
  });

  int _depth(AstNode node) {
    var d = 0;
    for (var cur = node.parent; cur != null; cur = cur.parent) {
      d++;
    }
    return d;
  }

  bool _inConstOrNonInstrumentableContext(AstNode node) {
    for (AstNode? cur = node; cur != null; cur = cur.parent) {
      if (_isNonInstrumentableAncestor(cur, node)) return true;
    }
    return false;
  }

  static bool _isNonInstrumentableAncestor(AstNode current, AstNode leaf) =>
      switch (current) {
        VariableDeclarationList(:final isConst) => isConst,
        InstanceCreationExpression(:final isConst) => isConst,
        TypedLiteral(:final isConst) => isConst,
        ConstructorDeclaration(:final constKeyword) => constKeyword != null,
        Annotation() ||
        AssertStatement() ||
        ConstantPattern() ||
        RelationalPattern() ||
        ConstructorInitializer() ||
        FormalParameter() ||
        EnumConstantArguments() => true,
        SwitchCase(:final expression) => _isInside(leaf, expression),
        SwitchPatternCase(:final guardedPattern) => _isInside(
          leaf,
          guardedPattern.pattern,
        ),
        _ => false,
      };

  static bool _isInside(AstNode leaf, AstNode target) =>
      leaf.thisOrAncestorMatching((n) => identical(n, target)) != null;

  void _wrapStatementWithEdge(Statement stmt) {
    final id = owner._allocSite(
      offset: stmt.offset,
      kind: 'branch',
      lineInfo: lineInfo,
      filePath: filePath,
    );
    owner.edgesInserted++;
    final d = _depth(stmt);
    edits.add(
      _SourceEdit(
        start: stmt.offset,
        end: stmt.offset,
        kind: _EditKind.prefix,
        depth: d,
        replacement: '{ \$fuzzEdge($id); ',
      ),
    );
    edits.add(
      _SourceEdit(
        start: stmt.end,
        end: stmt.end,
        kind: _EditKind.suffix,
        depth: d,
        replacement: ' }',
      ),
    );
  }

  @override
  void visitBlock(Block node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      final id = owner._allocSite(
        offset: node.leftBracket.offset,
        kind: 'block',
        lineInfo: lineInfo,
        filePath: filePath,
      );
      owner.edgesInserted++;
      edits.add(
        _SourceEdit(
          start: node.leftBracket.end,
          end: node.leftBracket.end,
          kind: _EditKind.prefix,
          depth: _depth(node),
          replacement: ' \$fuzzEdge($id);',
        ),
      );
    }
    super.visitBlock(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      final thenStmt = node.thenStatement;
      if (thenStmt is! Block) {
        _wrapStatementWithEdge(thenStmt);
      }
      final elseStmt = node.elseStatement;
      if (elseStmt != null && elseStmt is! Block && elseStmt is! IfStatement) {
        _wrapStatementWithEdge(elseStmt);
      }
    }
    super.visitIfStatement(node);
  }

  static String? _switchMemberCaseSource(SwitchMember member) =>
      switch (member) {
        SwitchCase(:final expression) => expression.toSource(),
        SwitchPatternCase(
          guardedPattern: GuardedPattern(
            pattern: ConstantPattern(:final expression),
          ),
        ) =>
          expression.toSource(),
        _ => null,
      };

  @override
  void visitSwitchStatement(SwitchStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      final caseExprs = <String>[];
      for (final member in node.members) {
        final caseSource = _switchMemberCaseSource(member);
        if (caseSource != null) caseExprs.add(caseSource);
        if (member.statements.isNotEmpty) {
          final edgeId = owner._allocSite(
            offset: member.offset,
            kind: 'switch_case',
            lineInfo: lineInfo,
            filePath: filePath,
          );
          owner.edgesInserted++;
          edits.add(
            _SourceEdit(
              start: member.colon.end,
              end: member.colon.end,
              kind: _EditKind.prefix,
              depth: _depth(member),
              replacement: ' \$fuzzEdge($edgeId);',
            ),
          );
        }
      }
      if (caseExprs.isNotEmpty) {
        final switchId = owner._allocSite(
          offset: node.offset,
          kind: 'switch',
          lineInfo: lineInfo,
          filePath: filePath,
        );
        owner.switchesInserted++;
        final expr = node.expression;
        final d = _depth(expr);
        edits.add(
          _SourceEdit(
            start: expr.offset,
            end: expr.offset,
            kind: _EditKind.prefix,
            depth: d,
            replacement: '\$fuzzSwitch(',
          ),
        );
        edits.add(
          _SourceEdit(
            start: expr.end,
            end: expr.end,
            kind: _EditKind.suffix,
            depth: d,
            replacement: ', <Object?>[${caseExprs.join(', ')}], $switchId)',
          ),
        );
      }
    }
    super.visitSwitchStatement(node);
  }

  static String? _operatorHelper(TokenType op) => switch (op) {
    TokenType.EQ_EQ => r'$fuzzEq',
    TokenType.BANG_EQ => r'$fuzzNe',
    TokenType.LT => r'$fuzzLt',
    TokenType.LT_EQ => r'$fuzzLe',
    TokenType.GT => r'$fuzzGt',
    TokenType.GT_EQ => r'$fuzzGe',
    TokenType.CARET => r'$fuzzXor',
    _ => null,
  };

  static bool _hasNullOrBoolLiteral(BinaryExpression node) =>
      node.leftOperand is NullLiteral ||
      node.rightOperand is NullLiteral ||
      node.leftOperand is BooleanLiteral ||
      node.rightOperand is BooleanLiteral;

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final helper =
        (_inConstOrNonInstrumentableContext(node) ||
            _hasNullOrBoolLiteral(node))
        ? null
        : _operatorHelper(node.operator.type);
    if (helper != null) {
      final id = owner._allocSite(
        offset: node.operator.offset,
        kind: 'cmp',
        lineInfo: lineInfo,
        filePath: filePath,
      );
      owner.comparesInserted++;
      final d = _depth(node);
      edits.add(
        _SourceEdit(
          start: node.offset,
          end: node.offset,
          kind: _EditKind.prefix,
          depth: d,
          replacement: '$helper(',
        ),
      );
      edits.add(
        _SourceEdit(
          start: node.leftOperand.end,
          end: node.rightOperand.offset,
          kind: _EditKind.replace,
          depth: d,
          replacement: ', ',
        ),
      );
      edits.add(
        _SourceEdit(
          start: node.end,
          end: node.end,
          kind: _EditKind.suffix,
          depth: d,
          replacement: ', $id)',
        ),
      );
    }
    super.visitBinaryExpression(node);
  }
}

/// Summary of a `.dart_tool/dash_fuzz/` package overlay instrumentation pass.
typedef OverlayResult = ({
  String packageName,
  String overlayPackageConfigPath,
  String edgeManifestPath,
  String instrumentedLibDir,
  int filesInstrumented,
  int edgesInserted,
  int comparesInserted,
  int switchesInserted,
});

/// Builds a non-destructive AST-instrumented copy of a target package's `lib/`
/// directory inside `.dart_tool/dash_fuzz/instrumented/lib/` and writes an
/// overlay `.dart_tool/dash_fuzz/package_config.json`.
class PackageOverlayInstrumentor {
  /// Instruments `<packageRoot>/lib` into `<packageRoot>/.dart_tool/dash_fuzz/`
  /// without modifying any tracked files in [packageRoot].
  static Future<OverlayResult> instrumentPackage({
    required String packageRoot,
    String runtimeImport = 'package:dash_fuzz/dash_fuzz.dart',
  }) async {
    final rootDir = p.normalize(p.absolute(packageRoot));
    final pubspecFile = File(p.join(rootDir, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw ArgumentError('No pubspec.yaml found in $rootDir');
    }

    final packageName = _extractPackageName(pubspecFile.readAsStringSync());
    final sourceLibDir = Directory(p.join(rootDir, 'lib'));
    if (!sourceLibDir.existsSync()) {
      throw ArgumentError('No lib/ directory found in $rootDir');
    }

    final dashFuzzDir = p.join(rootDir, '.dart_tool', 'dash_fuzz');
    final instrumentedRoot = p.join(dashFuzzDir, 'instrumented');
    final instrumentedLibDir = p.join(instrumentedRoot, 'lib');
    final outDir = Directory(instrumentedLibDir);
    if (outDir.existsSync()) {
      outDir.deleteSync(recursive: true);
    }
    outDir.createSync(recursive: true);

    final instrumentor = AstInstrumentor();
    final filesInstrumented = _instrumentDirectoryTree(
      sourceLibDir: sourceLibDir,
      instrumentedLibDir: instrumentedLibDir,
      instrumentor: instrumentor,
      runtimeImport: runtimeImport,
    );

    final edgeManifestPath = _writeEdgeManifest(
      dashFuzzDir: dashFuzzDir,
      packageName: packageName,
      sites: instrumentor.sites,
    );

    final overlayConfigPath = await _writeOverlayPackageConfig(
      rootDir: rootDir,
      packageName: packageName,
      instrumentedRoot: instrumentedRoot,
      dashFuzzDir: dashFuzzDir,
    );

    return (
      packageName: packageName,
      overlayPackageConfigPath: overlayConfigPath,
      edgeManifestPath: edgeManifestPath,
      instrumentedLibDir: instrumentedLibDir,
      filesInstrumented: filesInstrumented,
      edgesInserted: instrumentor.edgesInserted,
      comparesInserted: instrumentor.comparesInserted,
      switchesInserted: instrumentor.switchesInserted,
    );
  }

  static String _writeEdgeManifest({
    required String dashFuzzDir,
    required String packageName,
    required List<FuzzSiteEntry> sites,
  }) {
    final manifestPath = p.join(dashFuzzDir, 'edge_manifest.json');
    final payload = <String, Object?>{
      'package': packageName,
      'totalSites': sites.length,
      'sites': [
        for (final s in sites)
          {
            'id': s.id,
            'file': s.file,
            'line': s.line,
            'column': s.column,
            'kind': s.kind,
          },
      ],
    };
    File(manifestPath)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    return manifestPath;
  }

  static String _extractPackageName(String pubspecContent) {
    final match = RegExp(
      r'^name:\s*([a-zA-Z0-9_]+)',
      multiLine: true,
    ).firstMatch(pubspecContent);
    if (match == null) {
      throw const FormatException('Could not parse `name:` from pubspec.yaml');
    }
    return match.group(1)!;
  }

  static int _instrumentDirectoryTree({
    required Directory sourceLibDir,
    required String instrumentedLibDir,
    required AstInstrumentor instrumentor,
    required String runtimeImport,
  }) {
    final files =
        sourceLibDir.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    var count = 0;
    for (final entity in files) {
      final relPath = p.relative(entity.path, from: sourceLibDir.path);
      final destPath = p.join(instrumentedLibDir, relPath);
      Directory(p.dirname(destPath)).createSync(recursive: true);
      if (relPath.endsWith('.dart')) {
        final source = entity.readAsStringSync();
        final posixRel = p.posix.joinAll(['lib', ...p.split(relPath)]);
        final out = instrumentor.instrumentSource(
          source,
          runtimeImport: runtimeImport,
          filePath: posixRel,
        );
        File(destPath).writeAsStringSync(out);
        count++;
      } else {
        entity.copySync(destPath);
      }
    }
    return count;
  }

  static Future<String> _writeOverlayPackageConfig({
    required String rootDir,
    required String packageName,
    required String instrumentedRoot,
    required String dashFuzzDir,
  }) async {
    final pkgConfigFile = _findPackageConfigFile(rootDir);
    final rawJson =
        jsonDecode(pkgConfigFile.readAsStringSync()) as Map<String, Object?>;
    final configDir = p.dirname(pkgConfigFile.path);
    final packages = (rawJson['packages'] as List<Object?>)
        .cast<Map<String, Object?>>();

    final updatedPackages = <Map<String, Object?>>[];
    var hasDashFuzz = false;

    for (final entry in packages) {
      final name = entry['name'] as String;
      if (name == 'dash_fuzz') hasDashFuzz = true;
      if (name == packageName) {
        updatedPackages.add({
          ...entry,
          'rootUri': p.toUri(instrumentedRoot).toString(),
          'packageUri': 'lib/',
        });
      } else {
        updatedPackages.add(_absolutizePackageEntry(entry, configDir));
      }
    }

    if (!hasDashFuzz) {
      final dashFuzzRoot = await _resolveDashFuzzPackageRoot();
      updatedPackages.add({
        'name': 'dash_fuzz',
        'rootUri': p.toUri(dashFuzzRoot).toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      });
    }

    final overlayConfigPath = p.join(dashFuzzDir, 'package_config.json');
    final overlayMap = <String, Object?>{
      ...rawJson,
      'packages': updatedPackages,
    };
    File(
      overlayConfigPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(overlayMap));
    return overlayConfigPath;
  }

  static File _findPackageConfigFile(String startDir) {
    var current = p.normalize(p.absolute(startDir));
    while (true) {
      final candidate = File(
        p.join(current, '.dart_tool', 'package_config.json'),
      );
      if (candidate.existsSync()) return candidate;
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    throw StateError(
      'No .dart_tool/package_config.json found in $startDir or its parents. '
      'Run `dart pub get` first.',
    );
  }

  static Map<String, Object?> _absolutizePackageEntry(
    Map<String, Object?> entry,
    String configDir,
  ) {
    final rootUriStr = entry['rootUri'] as String;
    final parsed = Uri.parse(rootUriStr);
    if (parsed.hasScheme) return entry;
    final absPath = p.normalize(p.join(configDir, p.fromUri(parsed)));
    return {...entry, 'rootUri': p.toUri(absPath).toString()};
  }

  static Future<String> _resolveDashFuzzPackageRoot() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:dash_fuzz/dash_fuzz.dart'),
    );
    if (resolved != null) {
      return p.dirname(p.dirname(resolved.toFilePath()));
    }
    return p.normalize(p.absolute('.'));
  }
}
