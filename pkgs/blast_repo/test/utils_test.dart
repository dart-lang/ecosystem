// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/utils.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  // We skip this test on github actions as that typically does a shallow clone.
  test('gitDefaultBranch', () {
    final result = gitDefaultBranch(io.Directory.current.parent.parent);

    expect(result, 'main');
  }, skip: io.Platform.environment['GITHUB_ACTIONS'] == 'true');

  test('latestStableVersion', () {
    expect(latestStableVersion([]), isNull);

    expect(
      latestStableVersion([Version.parse('1.0.0')]),
      Version.parse('1.0.0'),
    );

    expect(
      latestStableVersion([Version.parse('1.0.0'), Version.parse('2.0.0')]),
      Version.parse('2.0.0'),
    );

    expect(
      latestStableVersion([Version.parse('2.0.0'), Version.parse('1.0.0')]),
      Version.parse('2.0.0'),
    );

    expect(
      latestStableVersion([
        Version.parse('1.0.0'),
        Version.parse('2.0.0'),
        Version.parse('3.0.0-dev'),
      ]),
      Version.parse('2.0.0'),
    );
  });
}
