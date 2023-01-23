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
      ])
    ]).create();
    dir = d.dir('foo').io;
  });

  test('customized to github org', () async {
    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('foo', [
      d.dir('.github', [
        d.dir('workflows', [
          d.file('publish.yaml', contains('my_org')),
        ]),
      ])
    ]).validate();
  });

  test('updates readme', () async {
    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('foo',
        [d.file('README.md', contains('Publishing automation'))]).validate();
  });
}
