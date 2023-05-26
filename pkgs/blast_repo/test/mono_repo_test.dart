// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/tweaks/mono_repo_tweak.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late MonoRepoTweak tweak;
  late io.Directory dir;

  setUp(() async {
    tweak = MonoRepoTweak();
    await d.dir('foo', [
      d.file('mono_repo.yaml', '# foo bar\n'),
    ]).create();
    dir = d.dir('foo').io;
  });

  test('recognizes mono_repo repo', () async {
    expect(tweak.shouldRunByDefault(dir, 'my_org/my_repo'), true);
  });

  test('ignores non-managed repo', () async {
    await d.dir('foo', [
      d.file('README.md', '# package name\n\n'),
    ]).create();
    dir = d.dir('foo').io;

    expect(tweak.shouldRunByDefault(dir, 'my_org/my_repo'), true);
  });
}
