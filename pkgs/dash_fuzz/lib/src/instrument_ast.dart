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
  final int seq;
  final String replacement;

  _SourceEdit({
    required this.start,
    required this.end,
    required this.kind,
    required this.depth,
    required this.seq,
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
    final cmpDepth = kind == _EditKind.prefix
        ? depth.compareTo(other.depth)
        : other.depth.compareTo(depth);
    if (cmpDepth != 0) return cmpDepth;
    return kind == _EditKind.prefix
        ? seq.compareTo(other.seq)
        : other.seq.compareTo(seq);
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
  int _nextSeq = 0;

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
        SwitchExpressionCase(:final guardedPattern) => _isInside(
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
    final seq = _nextSeq++;
    edits.add(
      _SourceEdit(
        start: stmt.offset,
        end: stmt.offset,
        kind: _EditKind.prefix,
        depth: d,
        seq: seq,
        replacement: '{ \$fuzzEdge($id); ',
      ),
    );
    edits.add(
      _SourceEdit(
        start: stmt.end,
        end: stmt.end,
        kind: _EditKind.suffix,
        depth: d,
        seq: seq,
        replacement: ' }',
      ),
    );
  }

  void _wrapExprWithEdge(
    Expression expr, {
    String kind = 'branch',
    bool preserveConditionFlow = false,
  }) {
    final unp = expr.unParenthesized;
    if (unp is RethrowExpression) return;
    if (unp is! ThrowExpression && _alwaysThrows(unp)) return;
    if (unp is! ThrowExpression && _isInsideAssignmentRhs(expr)) return;
    if (preserveConditionFlow &&
        unp is! ThrowExpression &&
        _containsConditionFlowCheck(unp)) {
      return;
    }
    final target = unp is ThrowExpression ? unp.expression : expr;
    final id = owner._allocSite(
      offset: expr.offset,
      kind: kind,
      lineInfo: lineInfo,
      filePath: filePath,
    );
    owner.edgesInserted++;
    final d = _depth(target);
    final seq = _nextSeq++;
    edits.add(
      _SourceEdit(
        start: target.offset,
        end: target.offset,
        kind: _EditKind.prefix,
        depth: d,
        seq: seq,
        replacement: '\$fuzzExpr($id, ',
      ),
    );
    edits.add(
      _SourceEdit(
        start: target.end,
        end: target.end,
        kind: _EditKind.suffix,
        depth: d,
        seq: seq,
        replacement: ')',
      ),
    );
  }

  static bool _alwaysThrows(Expression expr) => switch (expr.unParenthesized) {
    ThrowExpression() || RethrowExpression() => true,
    ConditionalExpression(:final thenExpression, :final elseExpression) =>
      _alwaysThrows(thenExpression) && _alwaysThrows(elseExpression),
    SwitchExpression(:final cases) =>
      cases.isNotEmpty && cases.every((c) => _alwaysThrows(c.expression)),
    _ => false,
  };

  static bool _isInsideAssignmentRhs(AstNode node) {
    for (
      var cur = node.parent;
      cur != null && cur is! Statement && cur is! FunctionBody;
      cur = cur.parent
    ) {
      if (cur is AssignmentExpression) return true;
    }
    return false;
  }

  void _wrapConditionWithBool(Expression cond) {
    final unp = cond.unParenthesized;
    if (unp is BinaryExpression ||
        unp is BooleanLiteral ||
        _containsFlowSensitiveCheck(unp)) {
      return;
    }
    final id = owner._allocSite(
      offset: cond.offset,
      kind: 'cmp',
      lineInfo: lineInfo,
      filePath: filePath,
    );
    owner.comparesInserted++;
    final d = _depth(cond);
    final seq = _nextSeq++;
    edits.add(
      _SourceEdit(
        start: cond.offset,
        end: cond.offset,
        kind: _EditKind.prefix,
        depth: d,
        seq: seq,
        replacement: r'$fuzzBool(',
      ),
    );
    edits.add(
      _SourceEdit(
        start: cond.end,
        end: cond.end,
        kind: _EditKind.suffix,
        depth: d,
        seq: seq,
        replacement: ', $id)',
      ),
    );
  }

  static bool _containsFlowSensitiveCheck(AstNode node) {
    final finder = _FlowSensitiveFinder();
    node.accept(finder);
    return finder.found;
  }

  static bool _containsConditionFlowCheck(AstNode node) {
    final finder = _ConditionFlowFinder();
    node.accept(finder);
    return finder.found;
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
          seq: _nextSeq++,
          replacement: ' \$fuzzEdge($id);',
        ),
      );
    }
    super.visitBlock(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      if (node.caseClause == null) {
        _wrapConditionWithBool(node.expression);
      }
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

  @override
  void visitForStatement(ForStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      if (node.forLoopParts case ForParts(:final condition?)) {
        _wrapConditionWithBool(condition);
      }
      if (node.body is! Block) {
        _wrapStatementWithEdge(node.body);
      }
    }
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      _wrapConditionWithBool(node.condition);
      if (node.body is! Block) {
        _wrapStatementWithEdge(node.body);
      }
    }
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      if (node.body is! Block) {
        _wrapStatementWithEdge(node.body);
      }
      _wrapConditionWithBool(node.condition);
    }
    super.visitDoStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      _wrapConditionWithBool(node.condition);
      _wrapExprWithEdge(node.thenExpression, preserveConditionFlow: true);
      _wrapExprWithEdge(node.elseExpression, preserveConditionFlow: true);
    }
    super.visitConditionalExpression(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (!node.isAsynchronous && !_inConstOrNonInstrumentableContext(node)) {
      _wrapExprWithEdge(node.expression, kind: 'block');
    }
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    if (!_inConstOrNonInstrumentableContext(node)) {
      for (final member in node.cases) {
        _wrapExprWithEdge(member.expression, kind: 'switch_case');
      }
    }
    super.visitSwitchExpression(node);
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
              seq: _nextSeq++,
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
        final seq = _nextSeq++;
        edits.add(
          _SourceEdit(
            start: expr.offset,
            end: expr.offset,
            kind: _EditKind.prefix,
            depth: d,
            seq: seq,
            replacement: '\$fuzzSwitch(',
          ),
        );
        edits.add(
          _SourceEdit(
            start: expr.end,
            end: expr.end,
            kind: _EditKind.suffix,
            depth: d,
            seq: seq,
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

  static bool _hasNullOrBoolLiteral(BinaryExpression node) {
    final left = node.leftOperand.unParenthesized;
    final right = node.rightOperand.unParenthesized;
    return left is SuperExpression ||
        left is NullLiteral ||
        right is NullLiteral ||
        left is BooleanLiteral ||
        right is BooleanLiteral;
  }

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
      final seq = _nextSeq++;
      edits.add(
        _SourceEdit(
          start: node.offset,
          end: node.offset,
          kind: _EditKind.prefix,
          depth: d,
          seq: seq,
          replacement: '$helper(',
        ),
      );
      edits.add(
        _SourceEdit(
          start: node.leftOperand.end,
          end: node.rightOperand.offset,
          kind: _EditKind.replace,
          depth: d,
          seq: seq,
          replacement: ', ',
        ),
      );
      edits.add(
        _SourceEdit(
          start: node.end,
          end: node.end,
          kind: _EditKind.suffix,
          depth: d,
          seq: seq,
          replacement: ', $id)',
        ),
      );
    }
    super.visitBinaryExpression(node);
  }
}

class _FlowSensitiveFinder extends GeneralizingAstVisitor<void> {
  bool found = false;

  @override
  void visitNode(AstNode node) {
    if (found) return;
    if (node is IsExpression ||
        node is AsExpression ||
        node is NullLiteral ||
        node is BooleanLiteral ||
        node is AssignmentExpression ||
        node is PatternAssignment ||
        node is ThrowExpression ||
        node is RethrowExpression) {
      found = true;
      return;
    }
    super.visitNode(node);
  }
}

class _ConditionFlowFinder extends GeneralizingAstVisitor<void> {
  bool found = false;

  @override
  void visitNode(AstNode node) {
    if (found) return;
    if (node is IsExpression || node is NullLiteral || node is BooleanLiteral) {
      found = true;
      return;
    }
    super.visitNode(node);
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
