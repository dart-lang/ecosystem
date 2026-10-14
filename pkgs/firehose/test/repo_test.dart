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
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
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
      final result = packages.isSinglePackageRepo;
      expect(result, false);
    });

    test('locatePackages', () {
      final result = packages.locatePackages();
      expect(result, isNotEmpty);
    });

    test('validate sorted', () {
      final result = packages.locatePackages();
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

    test('github release link with custom prefix', () {
      final github = GithubApi(
        repoSlug: RepositorySlug.full('dart-lang/ecosystem'),
      );
      final package = packages.locatePackages().first;
      final releaseUri = packages.calculateReleaseUri(
        package,
        github,
        tagPrefix: '',
      );
      expect(releaseUri.path, '/${github.repoSlug}/releases/new');

      final queryParams = releaseUri.queryParameters;
      expect(
        queryParams['tag'],
        packages.calculateRepoTag(package, tagPrefix: ''),
      );
      expect(queryParams['tag'], '${package.name}-${package.pubspec.version}');
    });
  });

  group('pub workspace repo', () {
    setUp(() {
      packages = Repository(
          Directory.fromUri(packageRoot.resolve('test_data/workspace_repo')));
    });

    test('locatePackages', () {
      final result = packages.locatePackages();
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
      final result = packages.locatePackages();
      expect(
          result,
          equals([
            isA<Package>().having((p) => p.name, 'name', 'pkg_1'),
            isA<Package>().having((p) => p.name, 'name', 'pkg_2'),
          ]));
    });
  });

  group('package discovery', () {
    late Directory repoDir;

    setUp(() {
      repoDir = Directory.systemTemp.createTempSync('firehose_repo_test');
      _writePackage(repoDir, 'pkgs/pkg_a');
      _writePackage(repoDir, 'pkgs/pkg_b', publishTo: 'none');
    });

    tearDown(() => repoDir.deleteSync(recursive: true));

    test('searches the file system only once', () {
      final repo = Repository(repoDir);
      final first = repo.locatePackages();
      final firstAll = repo.locatePackages(includeUnpublished: true);
      _writePackage(repoDir, 'pkgs/pkg_c');

      expect(repo.locatePackages(), orderedEquals(first));
      expect(
        repo.locatePackages(includeUnpublished: true),
        orderedEquals(firstAll),
      );
      expect(repo.isSinglePackageRepo, isFalse);
      expect(Repository(repoDir).locatePackages().map((p) => p.name),
          ['pkg_a', 'pkg_c']);
    });

    test('filters do not affect later results', () {
      final repo = Repository(repoDir);
      expect(repo.locatePackages(includeUnpublished: true).map((p) => p.name),
          ['pkg_a', 'pkg_b']);
      expect(
        repo.locatePackages(
          includeUnpublished: true,
          ignore: [Glob('pkgs/pkg_a')],
        ).map((p) => p.name),
        ['pkg_b'],
      );
      expect(
        repo.locatePackages(
          includeUnpublished: true,
          only: [Glob('pkgs/pkg_a')],
        ).map((p) => p.name),
        ['pkg_a'],
      );
      expect(repo.locatePackages(includeUnpublished: true).map((p) => p.name),
          ['pkg_a', 'pkg_b']);
      expect(repo.locatePackages().map((p) => p.name), ['pkg_a']);
    });
  });
}

void _writePackage(Directory repoDir, String relativePath,
    {String? publishTo}) {
  final dir = Directory(path.join(repoDir.path, relativePath))
    ..createSync(recursive: true);
  final name = path.basename(relativePath);
  File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
version: 1.0.0
${publishTo == null ? '' : 'publish_to: $publishTo'}
environment:
  sdk: ^3.0.0
''');
  File(path.join(dir.path, 'CHANGELOG.md')).writeAsStringSync('''
## 1.0.0

- Initial release.
''');
}
