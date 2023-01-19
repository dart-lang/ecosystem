// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/utils.dart';
import 'package:test/test.dart';

void main() {
  // We skip this test on github actions as that typically does a shallow clone.
  test('gitDefaultBranch', () {
    final result = gitDefaultBranch(io.Directory.current.parent.parent);

    expect(result, 'main');
  }, skip: io.Platform.environment['GITHUB_ACTIONS'] == 'true');
}
