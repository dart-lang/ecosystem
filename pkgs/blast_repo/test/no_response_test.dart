// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:blast_repo/src/tweaks/no_reponse_tweak.dart';
import 'package:test/test.dart';

void main() {
  test('isDartLangOrgRepo', () {
    final result = isDartLangOrgRepo(io.Directory.current.parent.parent);

    expect(result, true);
  });
}
