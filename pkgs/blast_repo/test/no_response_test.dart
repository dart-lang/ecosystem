// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/tweaks/no_reponse_tweak.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late NoResponseTweak tweak;
  late io.Directory dir;

  setUp(() async {
    tweak = NoResponseTweak();
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

  test('creates file', () async {
    var results = await tweak.fix(dir, 'my_org/my_repo');
    expect(results.fixes, isNotEmpty);

    await d.dir('foo', [
      d.dir('.github', [
        d.dir('workflows', [
          d.file('no-response.yml', contains('my_org')),
          d.file('no-response.yml', contains('actions/stale')),
          d.file('no-response.yml', contains('"needs-info"')),
        ]),
      ])
    ]).validate();
  });
}
