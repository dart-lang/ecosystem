// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firehose/firehose.dart';
import 'package:firehose/src/local_github_api.dart';
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
        ..addResult(
            Result.info(pkgA, 'WIP (no publish necessary)', isAffected: true))
        ..addResult(Result.info(pkgB, 'already published at pub.dev',
            isAffected: true));

      expect(results.visibleResults.length, 2);
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

      expect(results.visibleResults.length, 2);
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
        ..addResult(
            Result.info(pkgB, 'WIP (no publish necessary)', isAffected: true))
        ..addResult(
            Result.info(pkgC, 'WIP (no publish necessary)', isAffected: false))
        ..addResult(
            Result.info(pkgD, 'WIP (no publish necessary)', isAffected: false))
        ..addResult(Result.info(pkgE, 'already published at pub.dev',
            isAffected: false));

      expect(results.visibleResults.length, 2);
      expect(results.hiddenResults.length, 3);

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown, contains('| package:pkg_1 |'));
      expect(markdown, contains('| **package:pkg_2** ⭐ |'));
      expect(markdown, isNot(contains('| package:package1 |')));
      expect(markdown, isNot(contains('| package:package2 |')));
      expect(markdown, isNot(contains('| package:package3 |')));

      expect(markdown, contains('1 already published.'));
      expect(markdown, contains('2 WIP (no publish necessary).'));
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
        ..addResult(Result.info(pkgA, 'already published at pub.dev',
            isAffected: false))
        ..addResult(
            Result.info(pkgB, 'WIP (no publish necessary)', isAffected: false));

      expect(results.visibleResults, isEmpty);
      expect(results.hiddenResults.length, 2);

      final markdown = results.describeAsMarkdown(withTag: false);
      expect(markdown,
          equals('1 already published.\n1 WIP (no publish necessary).'));
    });
  });

  group('Firehose.verify with LocalGithubApi', () {
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
  });
}
