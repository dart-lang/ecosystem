// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
@TestOn('vm')
library;

import 'package:firehose/src/github.dart';
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

    test('github release link', () {
      final github = Github();
      final package = packages.locatePackages().single;
      final releaseUri = packages.calculateReleaseUri(package, github);
      expect(releaseUri.path, '/${github.repoSlug}/releases/new');
      final queryParams = releaseUri.queryParameters;
      expect(queryParams['tag'], packages.calculateRepoTag(package));
      expect(queryParams['title'],
          allOf(contains(package.name), contains(package.version.toString())));
      expect(queryParams['body'], package.changelog.describeLatestChanges);
    });
  });
}
