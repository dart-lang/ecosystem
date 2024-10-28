// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:blast_repo/src/tweaks/drop_lint_tweak.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late DropLintTweak tweak;

  setUp(() async {
    tweak = DropLintTweak();
  });

  test('removes the dead items', () async {
    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - avoid_classes_with_only_static_members
    - avoid_null_checks_in_equality_operators
    - no_runtimeType_toString
    - package_api_docs
    - prefer_const_declarations
    - unsafe_html
    - use_if_null_to_convert_nulls_to_bools
''')
    ]).create();
    final dir = d.dir('foo').io;

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, hasLength(3));

    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - avoid_classes_with_only_static_members
    - no_runtimeType_toString
    - prefer_const_declarations
    - use_if_null_to_convert_nulls_to_bools
''')
    ]).validate();
  });

  test('handles no linter section', () async {
    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true
''')
    ]).create();
    final dir = d.dir('foo').io;

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isEmpty);

    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true
''')
    ]).validate();
  });

  test('handles no analysis options file', () async {
    await d.dir('foo', []).create();
    final dir = d.dir('foo').io;

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isEmpty);
  });

  test('handles no bad lints', () async {
    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - avoid_classes_with_only_static_members
    - no_runtimeType_toString
    - prefer_const_declarations
    - use_if_null_to_convert_nulls_to_bools
''')
    ]).create();
    final dir = d.dir('foo').io;

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isEmpty);

    await d.dir('foo', [
      d.file('analysis_options.yaml', r'''
analyzer:
  language:
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - avoid_classes_with_only_static_members
    - no_runtimeType_toString
    - prefer_const_declarations
    - use_if_null_to_convert_nulls_to_bools
''')
    ]).validate();
  });

  test('handles rules as map', skip: 'not implemented yet!', () async {
    print('TODO!');
  });
}
