// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../repo_tweak.dart';

final _instance = DropLintTweak._();

class DropLintTweak extends RepoTweak {
  factory DropLintTweak() => _instance;

  DropLintTweak._()
      : super(
          id: 'drop-lint',
          description: 'Drop deprecated lints from analysis_options.yaml',
        );

  @override
  bool shouldRunByDefault(Directory checkout, String repoSlug) => true;

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) async {
    final analysisOptionsFile =
        File(p.join(checkout.path, 'analysis_options.yaml'));

    if (!analysisOptionsFile.existsSync()) {
      return FixResult.noFixesMade;
    }

    final yamlSource = loadYaml(
      analysisOptionsFile.readAsStringSync(),
      sourceUrl: analysisOptionsFile.uri,
    );

    if (yamlSource is YamlMap) {
      final linterNode = yamlSource['linter'];
      if (linterNode is YamlMap) {
        final rules = linterNode['rules'];

        if (rules is YamlList) {
          final fixes = <String>{};
          final badIndexes = rules
              .mapIndexed((index, value) {
                if (_deprecatedLints.contains(value)) {
                  fixes.add('Removed "$value".');
                  return index;
                }
                return -1;
              })
              .where((e) => e >= 0)
              .toList();

          final editor = YamlEditor(analysisOptionsFile.readAsStringSync());
          for (var index in badIndexes.reversed) {
            editor.remove(['linter', 'rules', index]);
          }

          analysisOptionsFile.writeAsStringSync(editor.toString(),
              mode: FileMode.writeOnly);

          return FixResult(fixes: fixes.toList()..sort());
        }

        if (rules == null) {
          return FixResult(fixes: []);
        }

        throw UnimplementedError('not sure what to do with $rules');
      }
    }

    return FixResult(fixes: []);
  }
}

final _deprecatedLints = {
  'avoid_null_checks_in_equality_operators',
  'package_api_docs',
  'unsafe_html',
};
