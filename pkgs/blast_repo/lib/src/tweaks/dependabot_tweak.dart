// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;
import 'package:yaml_edit/yaml_edit.dart';

import '../repo_tweak.dart';

final _instance = DependabotTweak._();

class DependabotTweak extends RepoTweak {
  factory DependabotTweak() => _instance;

  DependabotTweak._()
      : super(
          id: 'dependabot',
          description: 'ensure "$_filePath" exists and has the correct content',
        );

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) {
    final file = _dependabotFile(checkout);

    if (file == null) {
      File(p.join(checkout.path, _filePath))
          .writeAsStringSync(dependabotDefaultContent);
      return FixResult(fixes: ['Created $_filePath']);
    }

    final contentString = file.readAsStringSync();

    final newContent = doDependabotFix(contentString, sourceUrl: file.uri);
    if (newContent == contentString) {
      return FixResult.noFixesMade;
    }
    file.writeAsStringSync(newContent);
    return FixResult(fixes: ['Updated $_filePath']);
  }

  File? _dependabotFile(Directory checkout) {
    for (var option in _options) {
      final file = File(p.join(checkout.path, option));
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }
}

String doDependabotFix(String input, {Uri? sourceUrl}) {
  final contentYaml = yaml.loadYaml(
    input,
    sourceUrl: sourceUrl,
  );

  if (contentYaml is! yaml.YamlMap) {
    throw Exception('Not sure what to do. The source file is not a map!');
  }

  final version = contentYaml['version'];
  if (version != 2) {
    throw Exception('Not sure what to do. The version is not `2`!');
  }

  final editor = YamlEditor(input);

  final updates = contentYaml[_updatesKey];
  if (updates is! List) {
    throw Exception(
      'Not sure what to do. There is no "updates" value as a List',
    );
  }

  var found = false;
  for (var i = 0; i < updates.length; i++) {
    final value = updates[i];
    if (value is! Map) {
      continue;
    }

    final packageEcosystem = value[_packageEcosystemKey];
    if (packageEcosystem is! String) {
      throw Exception(
        'Not sure what to do with a $_packageEcosystemKey that is not String',
      );
    }

    if (packageEcosystem != 'github-actions') {
      continue;
    }

    found = true;

    if (_allowedActionValues().any(
      (element) => const DeepCollectionEquality().equals(element, value),
    )) {
      break;
    }

    editor.update([_updatesKey, i], _githubActionValue(_monthlyFrequency));
  }

  if (!found) {
    editor.appendToList([_updatesKey], _githubActionValue(_monthlyFrequency));
  }

  return editor.toString();
}

const _filePath = '.github/dependabot.yml';

const _options = [
  _filePath,
  '.github/dependabot.yaml',
];

final dependabotDefaultContent = _correctOutput();

String _correctOutput() {
  final editor = YamlEditor('''
# Dependabot configuration file.
# See https://docs.github.com/en/code-security/dependabot/dependabot-version-updates

version: 2
updates: null
''')
    ..update([
      _updatesKey
    ], [
      _githubActionValue(_monthlyFrequency),
    ]);

  return editor.toString();
}

const _updatesKey = 'updates';

const _monthlyFrequency = 'monthly';
const dependabotAllowedFrequencies = {'daily', 'weekly', _monthlyFrequency};

Iterable<Object> _allowedActionValues() =>
    dependabotAllowedFrequencies.map(_githubActionValue);

const _packageEcosystemKey = 'package-ecosystem';

Map<String, Object> _githubActionValue(String frequency) => {
      _packageEcosystemKey: 'github-actions',
      'directory': '/',
      'schedule': {'interval': frequency}
    };
