// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as path;

import 'pub.dart';
import 'report.dart';
import 'surveyor.dart';
import 'utils.dart';

class ApiUsage {
  final PackageInfo package;

  final References fromPackages;
  final References fromLibraries;

  ApiUsage(this.package, this.fromPackages, this.fromLibraries);

  static CollectedApiUsage combine(List<ApiUsage> usages) {
    var corpusPackages = <PackageInfo>[];

    var referringPackages = References();
    var referringLibraries = References();

    for (var usage in usages) {
      corpusPackages.add(usage.package);

      referringPackages.combineWith(usage.fromPackages);
      referringLibraries.combineWith(usage.fromLibraries);
    }

    return CollectedApiUsage(
      corpusPackages,
      referringPackages,
      referringLibraries,
    );
  }

  void toFile(File file) {
    var json = {
      'packages': fromPackages.toJson(),
      'libraries': fromLibraries.toJson(),
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Returns whether we found any references to the target package.
  bool get hadAnyReferences {
    return fromPackages.sortedLibraryReferences.isNotEmpty;
  }

  String describeUsage() {
    var libraryCount = fromPackages.sortedLibraryReferences.length;
    var classCount = fromPackages.sortedClassReferences.length;
    var extensionCount = fromPackages.sortedExtensionReferences.length;
    var symbolCount = fromPackages.sortedTopLevelReferences.length;
    var librariesStr = pluralize(libraryCount, 'library', plural: 'libraries');
    return 'referenced $libraryCount $librariesStr, '
        '$classCount ${pluralize(classCount, 'class', plural: 'classes')}, '
        '$extensionCount ${pluralize(extensionCount, 'extension')}, '
        'and $symbolCount top-level ${pluralize(symbolCount, 'symbol')}';
  }

  static ApiUsage fromFile(PackageInfo packageInfo, File file) {
    var json = const JsonDecoder().convert(file.readAsStringSync())
        as Map<String, dynamic>;
    return ApiUsage(
      packageInfo,
      References.fromJson(json['packages'] as Map<String, dynamic>),
      References.fromJson(json['libraries'] as Map<String, dynamic>),
    );
  }
}

class CollectedApiUsage {
  final List<PackageInfo> corpusPackages;

  final References referringPackages;
  final References referringLibraries;

  CollectedApiUsage(
    this.corpusPackages,
    this.referringPackages,
    this.referringLibraries,
  );
}

class ApiUseCollector extends RecursiveAstVisitor implements SurveyorVisitor {
  final ReportTarget reportTarget;
  final PackageInfo packageInfo;
  final Directory packageDir;

  final PackageEntity packageEntity;

  SurveyorContext? _context;

  References referringPackages = References();
  References referringLibraries = References();

  ApiUseCollector(this.reportTarget, this.packageInfo, this.packageDir)
      : packageEntity = PackageEntity(packageInfo.name);

  String get targetName => reportTarget.name;
  String get targetType => reportTarget.type;

  ApiUsage get usage =>
      ApiUsage(packageInfo, referringPackages, referringLibraries);

  String get packageName => usage.package.name;

  @override
  void preAnalysis(SurveyorContext context, {required bool subDir}) {
    _context = context;
  }

  String get currentFilePath => _context!.currentFilePath;

  @override
  void postAnalysis(SurveyorContext context) {
    _context = null;
  }

  @override
  void visitImportDirective(ImportDirective node) {
    var uri = node.uri.stringValue;

    if (uri != null && uri.startsWith('$targetType:')) {
      bool matches;

      if (reportTarget is DartLibraryTarget) {
        matches = uri == 'dart:$targetName';
      } else {
        matches = uri.startsWith('package:$targetName/');
      }

      if (matches) {
        referringPackages.addLibraryReference(uri, packageEntity);
        var relativeLibraryPath =
            path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addLibraryReference(
            uri, LibraryEntity(packageName, relativeLibraryPath));
      }
    }

    super.visitImportDirective(node);
  }

  @override
  void visitNamedType(NamedType node) {
    super.visitNamedType(node);

    _handleType(node.type);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);

    var element = node.staticElement;
    if (element == null) {
      return;
    }

    var library = element.library;
    if (library == null) {
      return;
    }

    var libraryUri = library.librarySource.uri;
    if (libraryUri.scheme != targetType ||
        libraryUri.pathSegments.first != targetName) {
      return;
    }

    //TODO: fix as soon as enclosingElement3 is on Dart stable
    // ignore: deprecated_member_use
    var enclosingElement = element.enclosingElement!;

    if (enclosingElement.kind == ElementKind.CLASS) {
      final name = enclosingElement.name!;
      referringPackages.addClassReference(name, packageEntity);
      var relPath = path.relative(currentFilePath, from: packageDir.path);
      referringLibraries.addClassReference(
          name, LibraryEntity(packageName, relPath));
    } else if (enclosingElement.kind == ElementKind.EXTENSION) {
      final name = enclosingElement.name!;
      referringPackages.addExtensionReference(name, packageEntity);
      var relPath = path.relative(currentFilePath, from: packageDir.path);
      referringLibraries.addExtensionReference(
          name, LibraryEntity(packageName, relPath));
    }

    if (element.kind == ElementKind.GETTER) {
      if (enclosingElement.kind == ElementKind.COMPILATION_UNIT) {
        // Record top-level elements.
        final name = element.name!;
        referringPackages.addTopLevelReference(name, packageEntity);
        var relPath = path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addTopLevelReference(
            name, LibraryEntity(packageName, relPath));
      } else if (enclosingElement.kind == ElementKind.EXTENSION) {
        // Record extensions.
        final name = enclosingElement.name!;
        referringPackages.addExtensionReference(name, packageEntity);
        var relPath = path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addExtensionReference(
            name, LibraryEntity(packageName, relPath));
      }
    } else if (element.kind == ElementKind.FUNCTION) {
      if (enclosingElement.kind == ElementKind.COMPILATION_UNIT) {
        // Record top-level elements.
        final name = element.name!;
        referringPackages.addTopLevelReference(name, packageEntity);
        var relPath = path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addTopLevelReference(
            name, LibraryEntity(packageName, relPath));
      } else if (enclosingElement.kind == ElementKind.EXTENSION) {
        // Record extensions.
        final name = enclosingElement.name!;
        referringPackages.addExtensionReference(name, packageEntity);
        var relPath = path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addExtensionReference(
            name, LibraryEntity(packageName, relPath));
      }
    }
  }

  void _handleType(DartType? type) {
    var element = type?.element;
    if (element != null) {
      var library = element.library;
      if (library == null) {
        return;
      }

      var libraryUri = library.librarySource.uri;
      if (libraryUri.scheme == targetType &&
          libraryUri.pathSegments.first == targetName) {
        final name = element.name!;
        referringPackages.addClassReference(name, packageEntity);
        var relPath = path.relative(currentFilePath, from: packageDir.path);
        referringLibraries.addClassReference(
            name, LibraryEntity(packageName, relPath));
      }
    }
  }
}

/// A referring entity - either a package or a library.
abstract class Entity {
  String toJson();

  static Entity fromJson(String json) {
    var l = json.split(':');
    if (l.first == 'package') {
      return PackageEntity(l[1]);
    } else {
      return LibraryEntity(l[1], l[2]);
    }
  }
}

class PackageEntity extends Entity {
  final String name;

  PackageEntity(this.name);

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    return other is PackageEntity && name == other.name;
  }

  @override
  String toJson() => 'package:$name';

  @override
  String toString() => 'package:$name';
}

class LibraryEntity extends Entity {
  final String package;
  final String libraryPath;

  LibraryEntity(this.package, this.libraryPath);

  @override
  int get hashCode => package.hashCode ^ libraryPath.hashCode;

  @override
  bool operator ==(Object other) {
    return other is LibraryEntity &&
        package == other.package &&
        libraryPath == other.libraryPath;
  }

  @override
  String toJson() => 'library:$package:$libraryPath';

  @override
  String toString() => 'package:$package/$libraryPath';
}

class References {
  final EntityReferences _libraryReferences = EntityReferences();
  final EntityReferences _classReferences = EntityReferences();
  final EntityReferences _extensionReferences = EntityReferences();
  final EntityReferences _topLevelReferences = EntityReferences();

  References();

  factory References.fromJson(Map<String, dynamic> json) {
    var refs = References();

    refs._libraryReferences.fromJson(json['library'] as Map<String, dynamic>);
    refs._classReferences.fromJson(json['class'] as Map<String, dynamic>);
    refs._extensionReferences
        .fromJson(json['extension'] as Map<String, dynamic>);
    refs._topLevelReferences.fromJson(json['topLevel'] as Map<String, dynamic>);

    return refs;
  }

  Set<Entity> get allEntities {
    var result = <Entity>{};

    result.addAll(_libraryReferences.entities);
    result.addAll(_classReferences.entities);
    result.addAll(_extensionReferences.entities);
    result.addAll(_topLevelReferences.entities);

    return result;
  }

  int get entityCount => allEntities.length;

  void addLibraryReference(String ref, Entity entity) {
    _libraryReferences.add(ref, entity);
  }

  void addClassReference(String ref, Entity entity) {
    _classReferences.add(ref, entity);
  }

  void addTopLevelReference(String ref, Entity entity) {
    _topLevelReferences.add(ref, entity);
  }

  void addExtensionReference(String ref, Entity entity) {
    _extensionReferences.add(ref, entity);
  }

  Set<Entity> getLibraryReferences(String ref) {
    return _libraryReferences._references[ref]!;
  }

  Map<String, int> get sortedLibraryReferences =>
      _libraryReferences.sortedReferences;

  Map<String, int> get sortedClassReferences =>
      _classReferences.sortedReferences;

  Map<String, int> get sortedExtensionReferences =>
      _extensionReferences.sortedReferences;

  Map<String, int> get sortedTopLevelReferences =>
      _topLevelReferences.sortedReferences;

  List<Entity> getReferencesToClass(String className) {
    var refs = _classReferences.referencesTo(className);
    return refs == null ? [] : refs.toList();
  }

  void combineWith(References references) {
    _libraryReferences.combineWith(references._libraryReferences);
    _classReferences.combineWith(references._classReferences);
    _extensionReferences.combineWith(references._extensionReferences);
    _topLevelReferences.combineWith(references._topLevelReferences);
  }

  Map toJson() {
    return {
      'library': _libraryReferences.toJson(),
      'class': _classReferences.toJson(),
      'extension': _extensionReferences.toJson(),
      'topLevel': _topLevelReferences.toJson(),
    };
  }
}

class EntityReferences {
  final Map<String, Set<Entity>> _references = {};

  EntityReferences();

  Set<Entity> get entities {
    var result = <Entity>{};
    for (var key in _references.keys) {
      result.addAll(_references[key]!);
    }
    return result;
  }

  void add(String ref, Entity entity) {
    _references.putIfAbsent(ref, () => {});
    _references[ref]!.add(entity);
  }

  Map<String, int> get sortedReferences => _sortByCount(_references);

  Map<String, int> _sortByCount(Map<String, Set<Entity>> refs) {
    var keys = refs.keys.toList();
    keys.sort((a, b) => refs[b]!.length - refs[a]!.length);
    return Map.fromIterable(keys, value: (key) => refs[key]!.length);
  }

  Set<Entity>? referencesTo(String className) {
    return _references[className];
  }

  void combineWith(EntityReferences other) {
    for (var entry in other._references.entries) {
      for (var entity in entry.value) {
        add(entry.key, entity);
      }
    }
  }

  void fromJson(Map<String, dynamic> json) {
    for (var key in json.keys) {
      var entities = (json[key] as List).cast<String>();
      for (var entity in entities) {
        add(key, Entity.fromJson(entity));
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      for (var entry in _references.entries)
        entry.key: entry.value.map((entity) => entity.toJson()).toList()
    };
  }
}
