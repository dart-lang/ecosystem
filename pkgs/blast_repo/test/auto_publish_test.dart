// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/tweaks/auto_publish_tweak.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late AutoPublishTweak tweak;
  late io.Directory dir;

  setUp(() async {
    tweak = AutoPublishTweak();
    await d.dir('foo', [
      d.file('README.md', '# package name\n\n'),
      d.dir('.github', [
        d.dir('workflows', [
          d.file('build.yaml', '# hello world'),
        ]),
      ]),
    ]).create();
    dir = d.dir('foo').io;
  });

  test('customized to github org (single-package)', () async {
    await d.dir('foo', [
      d.file('pubspec.yaml', 'name: foo\nversion: 1.0.0\n'),
    ]).create();

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('foo', [
      d.dir('.github', [
        d.dir('workflows', [
          d.file(
            'publish.yaml',
            allOf(
              contains('my_org'),
              contains("'v[0-9]+.[0-9]+.[0-9]+*'"),
              contains('dart-lang/setup-dart/.github/workflows/publish.yml@'),
              isNot(contains('working-directory:')),
              isNot(contains('pull_request:')),
            ),
          ),
        ]),
      ]),
    ]).validate();
  });

  test('creates one workflow per publishable package in mono-repo', () async {
    await d.dir('foo', [
      d.dir('.github', [
        d.dir('workflows', [
          d.file('publish.yaml', '# legacy workflow'),
        ]),
      ]),
      d.dir('pkgs', [
        d.dir('pkg_a', [
          d.file('pubspec.yaml', 'name: pkg_a\nversion: 1.0.0\n'),
        ]),
        d.dir('pkg_b', [
          d.file(
            'pubspec.yaml',
            'name: pkg_b\nversion: 2.0.0\n'
                'dependencies:\n  flutter:\n    sdk: flutter\n',
          ),
        ]),
        d.dir('internal_pkg', [
          d.file(
            'pubspec.yaml',
            'name: internal_pkg\nversion: 0.1.0\npublish_to: none\n',
          ),
        ]),
      ]),
    ]).create();

    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);
    expect(
      io.File('${dir.path}/.github/workflows/publish.yaml').existsSync(),
      isFalse,
    );
    expect(
      io.File(
        '${dir.path}/.github/workflows/publish_internal_pkg.yaml',
      ).existsSync(),
      isFalse,
    );

    await d.dir('foo', [
      d.dir('.github', [
        d.dir('workflows', [
          d.file(
            'publish_pkg_a.yaml',
            allOf(
              contains('my_org'),
              contains("'pkg_a-v[0-9]+.[0-9]+.[0-9]+*'"),
              contains('working-directory: pkgs/pkg_a'),
              contains('use-flutter: false'),
            ),
          ),
          d.file(
            'publish_pkg_b.yaml',
            allOf(
              contains('my_org'),
              contains("'pkg_b-v[0-9]+.[0-9]+.[0-9]+*'"),
              contains('working-directory: pkgs/pkg_b'),
              contains('use-flutter: true'),
            ),
          ),
        ]),
      ]),
    ]).validate();
  });
}
