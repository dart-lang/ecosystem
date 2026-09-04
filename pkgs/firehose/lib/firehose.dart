// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:glob/glob.dart';

import 'src/github.dart';
import 'src/pub.dart';
import 'src/repo.dart';
import 'src/utils.dart';

export 'src/changelog.dart' show Changelog;
export 'src/github.dart' show FileStatus, GitFile, GithubApi;
export 'src/repo.dart' show Package, Repository;
export 'src/utils.dart' show Severity;

const String _ignoreWarningsLabel = 'publish-ignore-warnings';

class Firehose {
  final Directory directory;
  final bool useFlutter;
  final List<Glob> ignoredPackages;
  final String tagPrefix;

  Firehose(
    this.directory,
    this.useFlutter,
    this.ignoredPackages, {
    this.tagPrefix = 'v',
  });

  Future<VerificationResults> verify(GithubApi github) async {
    final repo = Repository(directory);
    final packages = repo.locatePackages(ignore: ignoredPackages);

    final filesInPR = await allowFailure(
      github.listFilesForPR(directory, ignoredPackages),
      logError: print,
    );
    final relevantFiles = filesInPR?.where((f) => f.status.isRelevant).toList();

    final pub = Pub();

    final results = VerificationResults();

    for (final package in packages) {
      final isAffected = relevantFiles == null ||
          relevantFiles.any((f) => f.isInPackage(package));

      final repoTag = repo.calculateRepoTag(package, tagPrefix: tagPrefix);

      print('');
      print('Validating $package:${package.name}');

      print('pubspec:');
      final pubspecVersion = package.pubspec.version?.toString();
      if (pubspecVersion == null) {
        final result = Result.fail(
          package,
          "no version specified (perhaps you need a' publish_to: none' entry?)",
          isAffected: isAffected,
        );
        print(result);
        results.addResult(result);
        continue;
      }
      print('  - version: $pubspecVersion');

      final changelogVersion = package.changelog.latestVersion;
      print('changelog:');
      print(package.changelog.describeLatestChanges.trimRight());

      if (pubspecVersion != changelogVersion) {
        final result = Result.fail(
          package,
          'pubspec version ($pubspecVersion) and changelog ($changelogVersion) '
          "don't agree",
          isAffected: isAffected,
        );
        print(result);
        results.addResult(result);
        continue;
      }

      if (await pub.hasPublishedVersion(package.name, pubspecVersion)) {
        final result = Result.info(
          package,
          Result.alreadyPublishedMessage,
          isAffected: isAffected,
        );
        print(result);
        results.addResult(result);
      } else if (package.pubspec.version!.wip) {
        final result = Result.info(
          package,
          Result.wipMessage,
          isAffected: isAffected,
        );
        print(result);
        results.addResult(result);
      } else {
        const preReleaseText =
            'consider publishing the package as a pre-release instead';

        final result = await _runPublish(package, dryRun: true);

        final hasPreReleaseText = result.stdout.contains(preReleaseText);
        final hasWarningsLabel = github.prLabels.contains(_ignoreWarningsLabel);
        final ignoreWarnings = hasPreReleaseText || hasWarningsLabel;

        if (result.code != 0 && !ignoreWarnings) {
          exitCode = result.code;
          final message =
              'pub publish dry-run failed; add the `$_ignoreWarningsLabel` '
              'label to ignore';
          github.notice(message: message);
          results.addResult(
            Result.fail(package, message, isAffected: isAffected),
          );
        } else {
          final result = Result.success(
            package,
            '**ready to publish**',
            gitTag: repoTag,
            publishReleaseUri: repo.calculateReleaseUri(
              package,
              github,
              tagPrefix: tagPrefix,
            ),
            isAffected: isAffected,
          );
          print(result);
          results.addResult(result);
        }
      }
    }

    pub.close();

    return results;
  }

  Future<CommandResult> _runPublish(
    Package package, {
    required bool dryRun,
  }) async {
    final command = useFlutter ? 'flutter' : 'dart';
    return await runCommand(
      command,
      args: ['pub', 'publish', if (dryRun) '--dry-run'],
      cwd: package.directory,
    );
  }
}

class VerificationResults {
  final List<Result> results = [];

  void addResult(Result result) => results.add(result);

  Severity get severity =>
      Severity.values[results.map((e) => e.severity.index).fold(0, max)];

  bool get hasSuccess => results.any((r) => r.severity == Severity.success);

  bool get hasError => results.any((r) => r.severity == Severity.error);

  Iterable<Result> get visibleResults =>
      results.where((r) => r.isVisibleInTable);

  Iterable<Result> get hiddenResults =>
      results.where((r) => !r.isVisibleInTable);

  String describeAsMarkdown({bool withTag = true}) {
    final buffer = StringBuffer();
    for (final r in visibleResults) {
      final sev = r.severity == Severity.error ? '(error) ' : '';
      var tagColumn = '';
      if (withTag) {
        var tag = r.gitTag == null ? '' : '`${r.gitTag}`';
        final publishReleaseUri = r.publishReleaseUri;
        if (publishReleaseUri != null) {
          tag = '[$tag]($publishReleaseUri)';
        }

        tagColumn = ' | $tag';
      }
      final pkgName = r.isAffected
          ? '**package:${r.package.name}** ⭐'
          : 'package:${r.package.name}';
      buffer.writeln(
        '| $pkgName | ${r.package.version} | '
        '$sev${r.message}$tagColumn |',
      );
    }

    final hidden = hiddenResults.toList();
    final alreadyPublishedCount =
        hidden.where((r) => r.message == Result.alreadyPublishedMessage).length;
    final wipCount = hidden.where((r) => r.message == Result.wipMessage).length;

    final summaryLines = <String>[];
    if (alreadyPublishedCount > 0) {
      summaryLines.add('* $alreadyPublishedCount already published.');
    }
    if (wipCount > 0) {
      summaryLines.add('* $wipCount WIP (no publish necessary).');
    }

    if (summaryLines.isNotEmpty) {
      if (visibleResults.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(summaryLines.join('\n'));
    }

    return buffer.toString().trimRight();
  }
}

class Result {
  static const String alreadyPublishedMessage = 'already published at pub.dev';
  static const String wipMessage = 'WIP (no publish necessary)';

  final Severity severity;
  final Package package;
  final String message;
  final String? gitTag;
  final Uri? publishReleaseUri;
  final bool isAffected;

  Result(
    this.severity,
    this.package,
    this.message, [
    this.gitTag,
    this.publishReleaseUri,
    this.isAffected = false,
  ]);

  factory Result.fail(
    Package package,
    String message, {
    bool isAffected = false,
  }) =>
      Result(Severity.error, package, message, null, null, isAffected);

  factory Result.info(
    Package package,
    String message, {
    bool isAffected = false,
  }) =>
      Result(Severity.info, package, message, null, null, isAffected);

  factory Result.success(
    Package package,
    String message, {
    String? gitTag,
    Uri? publishReleaseUri,
    bool isAffected = false,
  }) =>
      Result(Severity.success, package, message, gitTag, publishReleaseUri,
          isAffected);

  bool get isVisibleInTable =>
      isAffected || severity == Severity.success || severity == Severity.error;

  @override
  String toString() {
    final details = gitTag == null ? '' : ' ($gitTag)';
    return severity == Severity.error
        ? 'error: $message$details'
        : '$message$details';
  }
}
