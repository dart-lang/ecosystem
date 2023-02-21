// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart' as yaml;

void main() {
  late String content;

  setUp(() {
    return content = File('lib/analysis_options.yaml').readAsStringSync();
  });

  test('well-formed', () {
    var result = yaml.loadYaml(content);
    check(result).isA<Map>();
  });

  test('references recommended', () {
    var result = yaml.loadYaml(content) as yaml.YamlMap;
    check(result['include']).equals('package:lints/recommended.yaml');
  });

  test('defines linter rules', () {
    var result = yaml.loadYaml(content) as yaml.YamlMap;
    check((result['linter'] as Map)['rules'] as List).isNotEmpty();
  });
}
