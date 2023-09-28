// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A tool to deduplicate lints from analysis_options.yaml files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

void main(List<String> args) {
  if (args.length != 1) {
    print('usage: dart tool/dedups.dart <analysis-options-file>');
  }

  final file = File(args.first);
  print('De-duplicating lints for ${file.path}:');

  final yaml = loadYaml(file.readAsStringSync()) as YamlMap;

  final include = yaml['include'] as String?;
  if (include == null) {
    print('No duplicates found (file does not contain an include section).');
    return;
  }

  if (!include.startsWith('package:')) {
    print('include type not supported: $include');
    return;
  }

  final packageConfig = _findPackageConfig(file.parent)!;

  final includes = Lints.readFrom(include, packageConfig);
  void printLints(Lints lints) {
    print('  ${lints.include}, read ${lints.lints.length} lints');
    if (lints.parent != null) printLints(lints.parent!);
  }

  print('');
  printLints(includes);

  // Look for duplicates in the linter rules.
  var count = 0;
  final lints = (yaml['linter'] as YamlMap?)?['rules'] as YamlList?;
  if (lints != null) {
    print('');
    print('${lints.length} local lints');

    for (final lint in lints.cast<String>()) {
      final definingFile = includes.containingInclude(lint);
      if (definingFile != null) {
        if (count == 0) print('');

        count++;
        print('  duplicate: $lint [${definingFile.include}]');
      }
    }
  }

  print('');

  if (count == 0) {
    print('No duplicates found.');
  } else {
    print('$count duplicates.');
  }

  // TODO: Also handle the analyzer/language section.
}

Map<String, Directory>? _findPackageConfig(Directory dir) {
  if (dir.parent == dir) {
    return null;
  }

  final configFile =
      File(path.join(dir.path, '.dart_tool', 'package_config.json'));
  if (configFile.existsSync()) {
    return _parseConfigFile(configFile);
  } else {
    return _findPackageConfig(dir.parent);
  }
}

Map<String, Directory>? _parseConfigFile(File configFile) {
  final json =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (json['packages'] as List).cast<Map<String, dynamic>>();
  return Map.fromIterable(
    packages,
    key: (p) => (p as Map)['name'] as String,
    value: (p) {
      final rootUri = (p as Map)['rootUri'] as String;
      final filePath = Uri.parse(rootUri).toFilePath();
      if (path.isRelative(filePath)) {
        return Directory(
          path.normalize(path.join(configFile.parent.path, filePath)),
        );
      } else {
        return Directory(filePath);
      }
    },
  );
}

class Lints {
  static Lints readFrom(String include, Map<String, Directory> packages) {
    // "package:lints/recommended.yaml"
    final uri = Uri.parse(include);
    final package = uri.pathSegments[0];
    final filePath = uri.pathSegments[1];

    final dir = packages[package]!;
    final configFile = File(path.join(dir.path, 'lib', filePath));

    final yaml = loadYaml(configFile.readAsStringSync()) as YamlMap;
    final localInclude = yaml['include'] as String?;
    final lints = (yaml['linter'] as YamlMap?)?['rules'] as YamlList;

    return Lints._(
      parent:
          localInclude == null ? null : Lints.readFrom(localInclude, packages),
      include: include,
      lints: lints.cast<String>().toList(),
    );
  }

  final Lints? parent;
  final String include;
  final List<String> lints;

  Lints._({
    this.parent,
    required this.include,
    required this.lints,
  });

  Lints? containingInclude(String lint) {
    if (lints.contains(lint)) return this;
    return parent?.containingInclude(lint);
  }
}
