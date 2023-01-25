// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:firehose/src/repo.dart';
import 'package:test/test.dart';

void main() {
  group('repo', () {
    late Repository packages;

    setUp(() {
      packages = Repository();
    });

    test('isSinglePackageRepo', () {
      var result = packages.isSinglePackageRepo;
      expect(result, true);
    });

    test('locatePackages', () {
      var result = packages.locatePackages();
      expect(result, isNotEmpty);
    });
  });
}
