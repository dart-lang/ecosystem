// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:firehose/src/github.dart';
import 'package:firehose/src/repo.dart';
import 'package:github/github.dart' show RepositorySlug;
import 'package:test/test.dart';

void main() {
  late Repository packages;
  late Uri packageRoot;

  setUpAll(() async {
    packageRoot = (await Isolate.resolvePackageUri(
            Uri.parse('package:firehose/test.dart')))!
        .resolve('../');
  });

  group('repo', () {
    setUp(() {
      // Look up two levels from the package directory to get the repo dir.
      packages = Repository(Directory.fromUri(packageRoot.resolve('../../')));
    });

    test('isSinglePackageRepo', () {
      var result = packages.isSinglePackageRepo;
      expect(result, false);
    });

    test('locatePackages', () {
      var result = packages.locatePackages();
      expect(result, isNotEmpty);
    });

    test('validate sorted', () {
      var result = packages.locatePackages();
      var sorted = true;
      for (var i = 1; i < result.length; i++) {
        final a = result[i - 1];
        final b = result[i];

        sorted &= a.name.compareTo(b.name) <= 0;
      }
      expect(sorted, isTrue);
    });

    test('github release link', () {
      final github = GithubApi(
        repoSlug: RepositorySlug.full('dart-lang/ecosystem'),
      );
      final package = packages.locatePackages().first;
      final releaseUri = packages.calculateReleaseUri(package, github);
      expect(releaseUri.path, '/${github.repoSlug}/releases/new');

      final queryParams = releaseUri.queryParameters;
      expect(queryParams['tag'], packages.calculateRepoTag(package));
      expect(queryParams['title'],
          allOf(contains(package.name), contains(package.version.toString())));
      expect(queryParams['body'], package.changelog.describeLatestChanges);
    });
  });

  group('pub workspace repo', () {
    setUp(() {
      packages = Repository(
          Directory.fromUri(packageRoot.resolve('test_data/workspace_repo')));
    });

    test('locatePackages', () {
      var result = packages.locatePackages();
      expect(
          result,
          equals([
            isA<Package>().having((p) => p.name, 'name', 'pkg_1'),
            isA<Package>().having((p) => p.name, 'name', 'pkg_2'),
          ]));
    });
  });

  group('repo with an unpublished root package', () {
    setUp(() {
      packages = Repository(Directory.fromUri(
          packageRoot.resolve('test_data/root_unpublished_pkg')));
    });

    test('locatePackages', () {
      var result = packages.locatePackages();
      expect(
          result,
          equals([
            isA<Package>().having((p) => p.name, 'name', 'pkg_1'),
            isA<Package>().having((p) => p.name, 'name', 'pkg_2'),
          ]));
    });
  });
}
