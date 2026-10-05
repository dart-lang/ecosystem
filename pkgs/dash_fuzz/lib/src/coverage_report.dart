// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

/// Metadata for a single AST-instrumented control-flow or comparison site.
typedef FuzzSiteEntry = ({
  int id,
  String file,
  int line,
  int column,
  String kind,
});

/// Per-file AST site coverage statistics.
typedef FileCoverageStat = ({
  String file,
  int hitSites,
  int totalSites,
  int hitEdges,
  int totalEdges,
  int hitCompares,
  int totalCompares,
  int bothBranchCompares,
  List<int> uncoveredLines,
});

/// Whole-package AST site coverage summary computed from `edge_manifest.json`
/// and `FuzzRuntime.siteHits`.
typedef PackageCoverageReport = ({
  String packageName,
  int hitSites,
  int totalSites,
  int hitEdges,
  int totalEdges,
  int hitCompares,
  int totalCompares,
  int bothBranchCompares,
  List<FileCoverageStat> files,
});

/// Computes per-file and whole-package AST coverage from [edgeManifestJson]
/// and the 65,536-byte [siteHits] bitmap recorded by `FuzzRuntime`.
PackageCoverageReport computeCoverageReport({
  required String edgeManifestJson,
  required Uint8List siteHits,
}) {
  final root = jsonDecode(edgeManifestJson) as Map<String, Object?>;
  final packageName = (root['package'] as String?) ?? '<unknown>';
  final rawSites = (root['sites'] as List<Object?>)
      .cast<Map<String, Object?>>();

  final byFile = <String, List<FuzzSiteEntry>>{};
  for (final raw in rawSites) {
    final entry = (
      id: raw['id'] as int,
      file: raw['file'] as String,
      line: raw['line'] as int,
      column: raw['column'] as int,
      kind: raw['kind'] as String,
    );
    (byFile[entry.file] ??= <FuzzSiteEntry>[]).add(entry);
  }

  final fileStats = <FileCoverageStat>[];
  var pkgHitSites = 0;
  var pkgTotalSites = 0;
  var pkgHitEdges = 0;
  var pkgTotalEdges = 0;
  var pkgHitCompares = 0;
  var pkgTotalCompares = 0;
  var pkgBothCompares = 0;

  final sortedFiles = byFile.keys.toList()..sort();
  for (final file in sortedFiles) {
    final stat = _computeFileStat(file, byFile[file]!, siteHits);
    fileStats.add(stat);
    pkgHitSites += stat.hitSites;
    pkgTotalSites += stat.totalSites;
    pkgHitEdges += stat.hitEdges;
    pkgTotalEdges += stat.totalEdges;
    pkgHitCompares += stat.hitCompares;
    pkgTotalCompares += stat.totalCompares;
    pkgBothCompares += stat.bothBranchCompares;
  }

  return (
    packageName: packageName,
    hitSites: pkgHitSites,
    totalSites: pkgTotalSites,
    hitEdges: pkgHitEdges,
    totalEdges: pkgTotalEdges,
    hitCompares: pkgHitCompares,
    totalCompares: pkgTotalCompares,
    bothBranchCompares: pkgBothCompares,
    files: fileStats,
  );
}

FileCoverageStat _computeFileStat(
  String file,
  List<FuzzSiteEntry> sites,
  Uint8List siteHits,
) {
  var hitSites = 0;
  var hitEdges = 0;
  var totalEdges = 0;
  var hitCompares = 0;
  var totalCompares = 0;
  var bothBranchCompares = 0;
  final uncoveredLines = <int>{};
  final coveredLines = <int>{};

  for (final site in sites) {
    final mask = siteHits[site.id & 0xFFFF];
    final isHit = mask != 0;
    if (isHit) {
      hitSites++;
      coveredLines.add(site.line);
    } else {
      uncoveredLines.add(site.line);
    }
    if (site.kind == 'cmp') {
      totalCompares++;
      if (isHit) hitCompares++;
      if ((mask & 0x3) == 0x3) bothBranchCompares++;
    } else if (site.kind != 'switch') {
      totalEdges++;
      if (isHit) hitEdges++;
    }
  }

  final missedOnlyLines = uncoveredLines.difference(coveredLines).toList()
    ..sort();
  return (
    file: file,
    hitSites: hitSites,
    totalSites: sites.length,
    hitEdges: hitEdges,
    totalEdges: totalEdges,
    hitCompares: hitCompares,
    totalCompares: totalCompares,
    bothBranchCompares: bothBranchCompares,
    uncoveredLines: missedOnlyLines,
  );
}

/// Formats [report] as a human-readable ASCII summary table.
String formatCoverageTable(PackageCoverageReport report) {
  final sb = StringBuffer()
    ..writeln(
      '\n=== AST Coverage Report: package:${report.packageName} '
      '(${_pct(report.hitSites, report.totalSites)} of ${report.totalSites} '
      'sites) ===',
    )
    ..writeln(
      '${'File'.padRight(42)} '
      '${'Sites'.padLeft(13)} '
      '${'Edges'.padLeft(11)} '
      '${'Cmp (Both)'.padLeft(14)}',
    )
    ..writeln('-' * 83);

  for (final f in report.files) {
    if (f.totalSites == 0) continue;
    final siteCol =
        '${f.hitSites}/${f.totalSites} (${_pct(f.hitSites, f.totalSites)})';
    final edgeCol = '${f.hitEdges}/${f.totalEdges}';
    final cmpCol =
        '${f.hitCompares}/${f.totalCompares} (${f.bothBranchCompares})';
    sb.writeln(
      '${f.file.padRight(42)} '
      '${siteCol.padLeft(13)} '
      '${edgeCol.padLeft(11)} '
      '${cmpCol.padLeft(14)}',
    );
  }

  final totalSiteCol =
      '${report.hitSites}/${report.totalSites} '
      '(${_pct(report.hitSites, report.totalSites)})';
  final totalEdgeCol = '${report.hitEdges}/${report.totalEdges}';
  final totalCmpCol =
      '${report.hitCompares}/${report.totalCompares} '
      '(${report.bothBranchCompares})';
  sb
    ..writeln('-' * 83)
    ..writeln(
      '${'TOTAL'.padRight(42)} '
      '${totalSiteCol.padLeft(13)} '
      '${totalEdgeCol.padLeft(11)} '
      '${totalCmpCol.padLeft(14)}',
    );
  return sb.toString();
}

/// Serializes [report] to a structured JSON string.
String coverageReportToJson(PackageCoverageReport report) =>
    const JsonEncoder.withIndent('  ').convert({
      'package': report.packageName,
      'hitSites': report.hitSites,
      'totalSites': report.totalSites,
      'siteCoveragePct': report.totalSites == 0
          ? 100.0
          : (report.hitSites * 100.0 / report.totalSites),
      'hitEdges': report.hitEdges,
      'totalEdges': report.totalEdges,
      'hitCompares': report.hitCompares,
      'totalCompares': report.totalCompares,
      'bothBranchCompares': report.bothBranchCompares,
      'files': [
        for (final f in report.files)
          {
            'file': f.file,
            'hitSites': f.hitSites,
            'totalSites': f.totalSites,
            'siteCoveragePct': f.totalSites == 0
                ? 100.0
                : (f.hitSites * 100.0 / f.totalSites),
            'hitEdges': f.hitEdges,
            'totalEdges': f.totalEdges,
            'hitCompares': f.hitCompares,
            'totalCompares': f.totalCompares,
            'bothBranchCompares': f.bothBranchCompares,
            'uncoveredLines': f.uncoveredLines,
          },
      ],
    });

String _pct(int hit, int total) =>
    total == 0 ? '100%' : '${(hit * 100 / total).toStringAsFixed(1)}%';
