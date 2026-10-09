// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:firehose/firehose.dart';
import 'package:firehose/src/health/health.dart';
import 'package:firehose/src/local_github_api.dart';
import 'package:firehose/src/pub.dart';
import 'package:test/test.dart';

void main() {
  group('VerificationResults', () {
    late Repository repo;
    late Package pkgA;
    late Package pkgB;
    late Package pkgC;
    late Package pkgD;
    late Package pkgE;

    setUp(() {
      repo = Repository();
      pkgA = Package(Directory('test_data/workspace_repo/pkg_1'), repo);
      pkgB = Package(Directory('test_data/workspace_repo/pkg_2'), repo);
      pkgC = Package(Directory('test_data/test_repo/pkgs/package1'), repo);
      pkgD = Package(Directory('test_data/test_repo/pkgs/package2'), repo);
      pkgE = Package(Directory('test_data/test_repo/pkgs/package3'), repo);
    });

    test('all packages affected are visible in table and highlighted', () {
      final results = VerificationResults()
        ..addResult(Result.info(pkgA, Result.wipMessage, isAffected: true))
        ..addResult(Result.info(pkgB, Result.alreadyPublishedMessage,
            isAffected: true));

      expect(results.visibleResults, hasLength(2));
      expect(results.hiddenResults, isEmpty);

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown, contains('| **package:pkg_1** ⭐ |'));
      expect(markdown, contains('| **package:pkg_2** ⭐ |'));
      expect(markdown, isNot(contains('already published.')));
      expect(markdown, isNot(contains('WIP (no publish necessary).')));
    });

    test('unaffected ready-to-publish and error packages are not starred', () {
      final results = VerificationResults()
        ..addResult(
            Result.success(pkgA, '**ready to publish**', isAffected: false))
        ..addResult(Result.fail(pkgB, 'version mismatch', isAffected: false));

      expect(results.visibleResults, hasLength(2));
      expect(results.hiddenResults, isEmpty);

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown, contains('| package:pkg_1 |'));
      expect(markdown, contains('| package:pkg_2 |'));
      expect(markdown, isNot(contains('⭐')));
    });

    test('unaffected WIP and already-published packages are summarized', () {
      final results = VerificationResults()
        ..addResult(
            Result.success(pkgA, '**ready to publish**', isAffected: false))
        ..addResult(Result.info(pkgB, Result.wipMessage, isAffected: true))
        ..addResult(Result.info(pkgC, Result.wipMessage, isAffected: false))
        ..addResult(Result.info(pkgD, Result.wipMessage, isAffected: false))
        ..addResult(Result.info(pkgE, Result.alreadyPublishedMessage,
            isAffected: false));

      expect(results.visibleResults, hasLength(2));
      expect(results.hiddenResults, hasLength(3));

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown, contains('| package:pkg_1 |'));
      expect(markdown, contains('| **package:pkg_2** ⭐ |'));
      expect(markdown, isNot(contains('| package:package1 |')));
      expect(markdown, isNot(contains('| package:package2 |')));
      expect(markdown, isNot(contains('| package:package3 |')));

      expect(markdown, contains('* 1 already published.'));
      expect(markdown, contains('* 2 WIP (no publish necessary).'));
    });

    test('summary omitted when counts are zero', () {
      final results = VerificationResults()
        ..addResult(
            Result.success(pkgA, '**ready to publish**', isAffected: true));

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown, contains('| **package:pkg_1** ⭐ |'));
      expect(markdown, isNot(contains('already published.')));
      expect(markdown, isNot(contains('WIP (no publish necessary).')));
    });

    test('only summary when no packages visible in table', () {
      final results = VerificationResults()
        ..addResult(Result.info(pkgA, Result.alreadyPublishedMessage,
            isAffected: false))
        ..addResult(Result.info(pkgB, Result.wipMessage, isAffected: false));

      expect(results.visibleResults, isEmpty);
      expect(results.hiddenResults, hasLength(2));

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(
        markdown,
        equals('* 1 already published.\n* 1 WIP (no publish necessary).'),
      );
    });

    test('log description lists release links and errors', () {
      final releaseUri = Uri.parse(
          'https://github.com/dart-lang/ecosystem/releases/new?tag=pkg_1-v1.0.0');
      final results = VerificationResults()
        ..addResult(Result.success(
          pkgA,
          '**ready to publish**',
          gitTag: 'pkg_1-v1.0.0',
          publishReleaseUri: releaseUri,
        ))
        ..addResult(Result.fail(pkgB, 'version mismatch'))
        ..addResult(Result.info(pkgC, Result.wipMessage, isAffected: true));

      final log = results.describeForLog();
      expect(log, contains('Packages with errors:'));
      expect(
          log, contains('  package:pkg_2 ${pkgB.version}: version mismatch'));
      expect(log, contains('Packages ready to publish:'));
      expect(log, contains('  package:pkg_1 ${pkgA.version} (pkg_1-v1.0.0)'));
      expect(log, contains('    $releaseUri'));
      expect(log, isNot(contains('package1')));
      expect(log.trimRight(), endsWith('$releaseUri'));
    });

    test('log description with nothing ready to publish', () {
      final results = VerificationResults()
        ..addResult(Result.info(pkgA, Result.alreadyPublishedMessage))
        ..addResult(Result.info(pkgB, Result.wipMessage));

      expect(results.describeForLog(), 'No packages are ready to publish.');
    });
  });

  group('Firehose.verify with LocalGithubApi', () {
    test('locates packages once and groups the output per package', () async {
      final testDir = Directory('test_data/test_repo');
      final firehose = Firehose(testDir, false, []);
      final pub = _FakePub(publishedVersions: {
        ('package1', '1.0.0'),
        ('package2', '1.0.0'),
        ('package3', '1.0.0'),
        ('package4', '1.2.0'),
        ('package5', '1.2.0'),
      });
      final github = LocalGithubApi(prLabels: [], files: []);

      final lines = <String>[];
      await runZoned(
        () => firehose.verify(github, pub: pub),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => lines.addAll(line.split('\n')),
        ),
      );

      for (final name in ['package1', 'package2', 'package3']) {
        expect(
          lines.where((l) =>
              l.startsWith('Found package at') && l.contains('pkgs/$name')),
          hasLength(1),
        );
      }
      expect(lines.first, '::group::Locating packages');
      expect(
        lines.where((l) => l.startsWith('::group::Validating')),
        [
          '::group::Validating package:package1 1.0.0',
          '::group::Validating package:package2 1.0.0',
          '::group::Validating package:package3 1.0.0',
          '::group::Validating package:package4 1.2.0',
          '::group::Validating package:package5 1.2.0',
        ],
      );

      // Groups can't be nested; every group must be closed before the next
      // one opens.
      var inGroup = false;
      for (final line in lines) {
        if (line.startsWith('::group::')) {
          expect(inGroup, isFalse, reason: 'Nested group at "$line"');
          inGroup = true;
        } else if (line == '::endgroup::') {
          expect(inGroup, isTrue, reason: 'Unmatched ::endgroup::');
          inGroup = false;
        }
      }
      expect(inGroup, isFalse);
    });
    test('filters packages based on PR file changes', () async {
      final testDir = Directory('test_data/test_repo');
      final firehose = Firehose(testDir, false, []);
      final github = LocalGithubApi(
        prLabels: [],
        files: [
          GitFile(
            'pkgs/package1/lib/package1.dart',
            FileStatus.modified,
            testDir,
          ),
        ],
      );

      final results = await firehose.verify(github);
      final affectedResults =
          results.results.where((r) => r.isAffected).toList();
      final unaffectedResults =
          results.results.where((r) => !r.isAffected).toList();

      expect(affectedResults.map((r) => r.package.name), ['package1']);
      expect(
        unaffectedResults.map((r) => r.package.name),
        containsAll(['package2', 'package3', 'package4', 'package5']),
      );
    });

    test(
        'fails when a modified package has an already-published version '
        'on pub.dev', () async {
      final testDir = Directory('test_data/test_repo');
      final firehose = Firehose(testDir, false, []);
      final pub = _FakePub(publishedVersions: {
        ('package1', '1.0.0'),
        ('package2', '1.0.0'),
      });
      final github = LocalGithubApi(
        prLabels: [],
        files: [
          GitFile(
            'pkgs/package1/lib/package1.dart',
            FileStatus.modified,
            testDir,
          ),
        ],
      );

      final results = await firehose.verify(github, pub: pub);
      final pkg1Result =
          results.results.firstWhere((r) => r.package.name == 'package1');
      final pkg2Result =
          results.results.firstWhere((r) => r.package.name == 'package2');

      expect(pkg1Result.severity, Severity.error);
      expect(pkg1Result.message, contains('bump to a `-wip` version'));
      expect(pkg2Result.severity, Severity.info);
      expect(pkg2Result.message, Result.alreadyPublishedMessage);
    });

    test(
        'allows standalone CHANGELOG.md fix or publish-ignore-warnings '
        'on already-published version', () async {
      final testDir = Directory('test_data/test_repo');
      final firehose = Firehose(testDir, false, []);
      final pub = _FakePub(publishedVersions: {
        ('package1', '1.0.0'),
        ('package2', '1.0.0'),
      });
      final changelogOnlyGithub = LocalGithubApi(
        prLabels: [],
        files: [
          GitFile(
            'pkgs/package1/CHANGELOG.md',
            FileStatus.modified,
            testDir,
          ),
        ],
      );
      final changelogOnlyResults =
          await firehose.verify(changelogOnlyGithub, pub: pub);
      final pkg1ChangelogOnly = changelogOnlyResults.results
          .firstWhere((r) => r.package.name == 'package1');
      expect(pkg1ChangelogOnly.severity, Severity.info);
      expect(pkg1ChangelogOnly.message, Result.alreadyPublishedMessage);

      final labeledGithub = LocalGithubApi(
        prLabels: ['publish-ignore-warnings'],
        files: [
          GitFile(
            'pkgs/package1/lib/package1.dart',
            FileStatus.modified,
            testDir,
          ),
        ],
      );
      final labeledResults = await firehose.verify(labeledGithub, pub: pub);
      final pkg1Labeled = labeledResults.results
          .firstWhere((r) => r.package.name == 'package1');
      expect(pkg1Labeled.severity, Severity.info);
      expect(pkg1Labeled.message, Result.alreadyPublishedMessage);

      final singlePkgDir = Directory.systemTemp.createTempSync();
      addTearDown(() => singlePkgDir.deleteSync(recursive: true));
      File('${singlePkgDir.path}/pubspec.yaml').writeAsStringSync('''
name: single_pkg
version: 1.0.0
environment:
  sdk: ^3.0.0
''');
      File('${singlePkgDir.path}/CHANGELOG.md').writeAsStringSync('''
## 1.0.0

- Initial release.
''');
      final singleFirehose = Firehose(singlePkgDir, false, []);
      final singlePub = _FakePub(publishedVersions: {('single_pkg', '1.0.0')});
      final workflowOnlyGithub = LocalGithubApi(
        prLabels: [],
        files: [
          GitFile(
            '.github/workflows/publish.yaml',
            FileStatus.modified,
            singlePkgDir,
          ),
        ],
      );
      final workflowResults =
          await singleFirehose.verify(workflowOnlyGithub, pub: singlePub);
      expect(workflowResults.results.single.severity, Severity.info);
      expect(
        workflowResults.results.single.message,
        Result.alreadyPublishedMessage,
      );
    });
  });

  group('Health.isRollConfirmed', () {
    test('recognizes CONFIRMED_PACKAGE_ROLL=true', () {
      expect(
        Health.isRollConfirmed(
            'Ready to release\nCONFIRMED_PACKAGE_ROLL=true', 'foo'),
        isTrue,
      );
    });

    test('recognizes ROLLED_TO and ROLLED_TO_<pkg>', () {
      expect(
        Health.isRollConfirmed('ROLLED_TO=abc1234', 'foo'),
        isTrue,
      );
      expect(
        Health.isRollConfirmed('ROLLED_TO_foo=abc1234', 'foo'),
        isTrue,
      );
      expect(
        Health.isRollConfirmed('ROLLED_TO_bar=abc1234', 'foo'),
        isFalse,
      );
    });

    test('returns false when roll confirmation is absent', () {
      expect(
        Health.isRollConfirmed('Normal PR description', 'foo'),
        isFalse,
      );
    });
  });

  group('bin/comment.dart CLI', () {
    test('delete command exits with code 64 on missing or empty comment ID',
        () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['bin/comment.dart', 'delete', '--comment-id', '0'],
      );
      expect(result.exitCode, 64);
      expect(result.stderr, contains('Invalid comment ID'));
    });

    test('delete command fails when required option is omitted', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['bin/comment.dart', 'delete'],
      );
      expect(result.exitCode, 64);
      expect(result.stderr, contains('Invalid comment ID'));
    });
  });
}

class _FakePub extends Pub {
  final Set<(String, String)> publishedVersions;

  _FakePub({required this.publishedVersions});

  @override
  Future<bool> hasPublishedVersion(String name, String version) async =>
      publishedVersions.contains((name, version));
}
