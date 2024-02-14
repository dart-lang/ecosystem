// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/tweaks/reformat_tweak.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late ReformatTweak tweak;
  late io.Directory singleRepo;
  late io.Directory multiRepo;
  late io.Directory nochangeRepo;

  setUp(() async {
    tweak = ReformatTweak();

    await d.dir('nochange', [
      d.file('pubspec.yaml', pubspec),
      d.file('something.dart', formatted),
    ]).create();
    nochangeRepo = d.dir('single').io;

    await d.dir('single', [
      d.file('pubspec.yaml', pubspec),
      d.file('something.dart', unformatted),
    ]).create();
    singleRepo = d.dir('single').io;

    await d.dir('multi', [
      d.dir('package1', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', unformatted),
      ]),
      d.dir('package2', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', unformatted),
      ]),
      d.dir('package3', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', formatted),
      ]),
    ]).create();

    nochangeRepo = d.dir('nochange').io;
    singleRepo = d.dir('single').io;
    multiRepo = d.dir('multi').io;
  });
  test('does nothing on formatted repo', () async {
    var results = await tweak.fix(nochangeRepo, 'my_org/my_repo');
    expect(results.fixes, isEmpty);

    await d.dir('nochange', [
      d.file('pubspec.yaml', pubspec),
      d.file('something.dart', formatted),
    ]).validate();
  });

  test('formats single package repo', () async {
    var results = await tweak.fix(singleRepo, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('single', [
      d.file('pubspec.yaml', pubspec),
      d.file('something.dart', formatted),
    ]).validate();
  });

  test('formats multi package repo', () async {
    var results = await tweak.fix(multiRepo, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('multi', [
      d.dir('package1', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', formatted),
      ]),
      d.dir('package2', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', formatted),
      ]),
      d.dir('package3', [
        d.file('pubspec.yaml', pubspec),
        d.file('something.dart', formatted),
      ]),
    ]).validate();
  });
}

final unformatted = '''
void main() {
var i = 0;
}
''';

final formatted = '''
void main() {
  var i = 0;
}
''';

final pubspec = '''
name: test_package
environment:
  sdk: ^3.0.0

dependencies:
  args: ^2.3.1

dev_dependencies:
  test: ^1.22.0
''';
