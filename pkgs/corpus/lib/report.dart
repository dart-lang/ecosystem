// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'api.dart';
import 'pub.dart';
import 'utils.dart';

abstract class ReportTarget {
  final String name;
  final String version;

  ReportTarget({required this.name, required this.version});

  String get type;

  Stream<PackageInfo> getPackages(Pub pub);

  @override
  String toString() => '$type:$name';
}

class PackageTarget extends ReportTarget {
  final PackageInfo targetPackage;
  final String? description;

  PackageTarget({
    required super.name,
    required super.version,
    required this.targetPackage,
    this.description,
  });

  factory PackageTarget.fromPackage(PackageInfo package) {
    return PackageTarget(
      name: package.name,
      version: package.version,
      targetPackage: package,
      description: package.description,
    );
  }

  @override
  String get type => 'package';

  @override
  Stream<PackageInfo> getPackages(Pub pub) => pub.popularDependenciesOf(name);
}

class DartLibraryTarget extends ReportTarget {
  DartLibraryTarget({required super.name, required super.version});

  @override
  String get type => 'dart';

  @override
  Stream<PackageInfo> getPackages(Pub pub) => pub.allPubPackages();
}

class Report {
  final ReportTarget reportTarget;

  Report(this.reportTarget);

  File generateReport(List<ApiUsage> usages, {bool showSrcReferences = false}) {
    var usage = ApiUsage.combine(usages);

    var file = File('reports/${reportTarget.type}_${reportTarget.name}.md');
    file.parent.createSync();
    var buf = StringBuffer();

    buf.writeln('# Report for ${reportTarget.type}:${reportTarget.name}');
    buf.writeln();
    buf.writeln('## General info');
    buf.writeln();
    if (reportTarget is DartLibraryTarget) {
      buf.writeln(
        'https://api.dart.dev/dart-${reportTarget.name}/'
        'dart-${reportTarget.name}-library.html',
      );
    } else if (reportTarget is PackageTarget) {
      buf.writeln((reportTarget as PackageTarget).description);
      buf.writeln();
      buf.writeln('- pub page: https://pub.dev/packages/${reportTarget.name}');
      buf.writeln(
        '- docs: https://pub.dev/documentation/${reportTarget.name}/latest/',
      );
      buf.writeln(
        '- dependent packages: '
        'https://pub.dev/packages?q=dependency%3A${reportTarget.name}&sort=top',
      );
    }
    buf.writeln();
    buf.writeln(
      'Stats for ${reportTarget.type}:${reportTarget.name} '
      'v${reportTarget.version} pulled from ${usage.corpusPackages.length} '
      'packages.',
    );

    var packagesReferences = usage.referringPackages;
    var libraryReferences = usage.referringLibraries;

    // TODO(devoncarew): write a utility class to construct markdown tables;
    // that could then include automatic whitespace padding for cells

    // Library references
    buf.writeln();
    buf.writeln('## Library references');
    buf.writeln();
    buf.writeln('### Library references from packages');
    buf.writeln();
    buf.writeln('| Library | Package references | % |');
    buf.writeln('| --- | ---: | ---: |');
    for (var entry in packagesReferences.sortedLibraryReferences.entries) {
      var val = entry.value;
      var count = usage.corpusPackages.length;
      buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      var library = entry.key;
      if (showSrcReferences && library.contains('/src/')) {
        for (var entity in packagesReferences.getLibraryReferences(entry.key)) {
          buf.writeln('  - ${entity.toString()}');
        }
      }
    }
    buf.writeln();
    buf.writeln('### Library references from libraries');
    buf.writeln();
    buf.writeln('| Library | Library references | % |');
    buf.writeln('| --- | ---: | ---: |');
    for (var entry in libraryReferences.sortedLibraryReferences.entries) {
      var val = entry.value;
      var count = libraryReferences.entityCount;
      buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      var library = entry.key;
      if (showSrcReferences && library.contains('/src/')) {
        for (var entity in libraryReferences.getLibraryReferences(entry.key)) {
          buf.writeln('  - ${entity.toString()}');
        }
      }
    }

    // Class references
    buf.writeln();
    buf.writeln('## Class references');
    buf.writeln();
    buf.writeln('### Class references from packages');
    buf.writeln();
    buf.writeln('| Class | Package references | % |');
    buf.writeln('| --- | ---: | ---: |');
    for (var entry in packagesReferences.sortedClassReferences.entries) {
      var val = entry.value;
      var count = usage.corpusPackages.length;
      buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
    }

    // // TODO: convert this into a command-line option
    // final searchClass = 'Foo';
    // var classRefs = packagesReferences.getReferencesToClass(searchClass);
    // if (classRefs.isNotEmpty) {
    //   print('Found references to $searchClass:');
    //   for (var ref in classRefs) {
    //     print('- $ref');
    //   }
    // }

    buf.writeln();
    buf.writeln('### Class references from libraries');
    buf.writeln();
    buf.writeln('| Class | Library references | % |');
    buf.writeln('| --- | ---: | ---: |');
    for (var entry in libraryReferences.sortedClassReferences.entries) {
      var val = entry.value;
      var count = libraryReferences.entityCount;
      buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
    }

    // Extension references
    if (packagesReferences.sortedExtensionReferences.isNotEmpty ||
        libraryReferences.sortedExtensionReferences.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Extension references');
      buf.writeln();
      buf.writeln('### Extension references from packages');
      buf.writeln();
      buf.writeln('| Extension | Package references | % |');
      buf.writeln('| --- | ---: | ---: |');
      for (var entry in packagesReferences.sortedExtensionReferences.entries) {
        var val = entry.value;
        var count = usage.corpusPackages.length;
        buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      }

      buf.writeln();
      buf.writeln('### Extension references from libraries');
      buf.writeln();
      buf.writeln('| Extension | Library references | % |');
      buf.writeln('| --- | ---: | ---: |');
      for (var entry in libraryReferences.sortedExtensionReferences.entries) {
        var val = entry.value;
        var count = libraryReferences.entityCount;
        buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      }
    }

    // Top-level symbols
    if (packagesReferences.sortedTopLevelReferences.isNotEmpty ||
        libraryReferences.sortedTopLevelReferences.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Top-level symbols');
      buf.writeln();
      buf.writeln('### Top-level symbols references from packages');
      buf.writeln();
      buf.writeln('| Top-level symbol | Package references | % |');
      buf.writeln('| --- | ---: | ---: |');
      for (var entry in packagesReferences.sortedTopLevelReferences.entries) {
        var val = entry.value;
        var count = usage.corpusPackages.length;
        buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      }
      buf.writeln();
      buf.writeln('### Top-level symbol references from libraries');
      buf.writeln();
      buf.writeln('| Top-level symbol | Library references | % |');
      buf.writeln('| --- | ---: | ---: |');
      for (var entry in libraryReferences.sortedTopLevelReferences.entries) {
        var val = entry.value;
        var count = libraryReferences.entityCount;
        buf.writeln('| ${entry.key} | $val | ${percent(val, count)} |');
      }
    }

    // Corpus
    buf.writeln();
    buf.writeln('## Corpus packages');
    buf.writeln();
    for (var package in usage.corpusPackages) {
      buf.writeln('- ${package.name} v${package.version}');
    }

    file.writeAsStringSync(buf.toString());

    return file;
  }
}
