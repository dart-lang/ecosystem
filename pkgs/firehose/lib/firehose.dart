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

const String _botSuffix = '[bot]';

const String _githubActionsUser = 'github-actions[bot]';

const String _publishBotTag = '## Package publishing';

const String _ignoreWarningsLabel = 'publish-ignore-warnings';

class Firehose {
  final Directory directory;
  final bool useFlutter;
  final List<Glob> ignoredPackages;

  Firehose(this.directory, this.useFlutter, this.ignoredPackages);

  /// Validate the packages in the repository.
  ///
  /// This method is intended to run in the context of a PR. It will:
  /// - determine the set of packages in the repo
  /// - validate that the changelog version == the pubspec version
  /// - provide feedback on the PR (via a PR comment) about packages which are
  ///   ready to publish
  Future<void> validate() async {
    final github = GithubApi();

    // Do basic validation of our expected env var.
    if (!expectEnv(github.githubAuthToken, 'GITHUB_TOKEN')) return;
    if (!expectEnv(github.repoSlug?.fullName, 'GITHUB_REPOSITORY')) return;
    if (!expectEnv(github.issueNumber?.toString(), 'ISSUE_NUMBER')) return;
    if (!expectEnv(github.sha, 'GITHUB_SHA')) return;

    if ((github.actor ?? '').endsWith(_botSuffix)) {
      print('Skipping package validation for ${github.actor} PRs.');
      return;
    }

    final results = await verify(github);

    final markdownTable = '''
| Package | Version | Status | Publish tag (post-merge) |
| :--- | ---: | :--- | ---: |
${results.describeAsMarkdown()}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
''';
    github.appendStepSummary(markdownTable);

    final existingCommentId = await allowFailure(
      github.findCommentId(
        user: _githubActionsUser,
        searchTerm: _publishBotTag,
      ),
      logError: print,
    );

    if (results.hasSuccess) {
      final commentText = '$_publishBotTag\n\n$markdownTable';

      if (existingCommentId != null) {
        final idFile = File('./output/commentId');
        print('''
Saving existing comment id $existingCommentId to file ${idFile.path}''');
        await idFile.create(recursive: true);
        await idFile.writeAsString(existingCommentId.toString());
      }

      final commentFile = File('./output/comment.md');
      print('Saving comment markdown to file ${commentFile.path}');
      await commentFile.create(recursive: true);
      await commentFile.writeAsString(commentText);
    } else {
      if (results.hasError && exitCode == 0) {
        exitCode = 1;
      }
    }

    github.close();
  }

  Future<VerificationResults> verify(GithubApi github) async {
    final repo = Repository(directory);
    final packages = repo.locatePackages(ignore: ignoredPackages);

    final pub = Pub();

    final results = VerificationResults();

    for (var package in packages) {
      final repoTag = repo.calculateRepoTag(package);

      print('');
      print('Validating $package:${package.name}');

      print('pubspec:');
      final pubspecVersion = package.pubspec.version?.toString();
      if (pubspecVersion == null) {
        final result = Result.fail(
          package,
          "no version specified (perhaps you need a' publish_to: none' entry?)",
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
        );
        print(result);
        results.addResult(result);
        continue;
      }

      if (await pub.hasPublishedVersion(package.name, pubspecVersion)) {
        final result = Result.info(package, 'already published at pub.dev');
        print(result);
        results.addResult(result);
      } else if (package.pubspec.version!.wip) {
        final result = Result.info(package, 'WIP (no publish necessary)');
        print(result);
        results.addResult(result);
      } else {
        const preReleaseText =
            'consider publishing the package as a pre-release instead';

        final result = await _runPublish(package, dryRun: true, force: false);

        final hasPreReleaseText = result.stdout.contains(preReleaseText);
        final hasWarningsLabel = github.prLabels.contains(_ignoreWarningsLabel);
        final ignoreWarnings = hasPreReleaseText || hasWarningsLabel;

        if (result.code != 0 && !ignoreWarnings) {
          exitCode = result.code;
          final message =
              'pub publish dry-run failed; add the `$_ignoreWarningsLabel` '
              'label to ignore';
          github.notice(message: message);
          results.addResult(Result.fail(package, message));
        } else {
          final result = Result.success(package, '**ready to publish**',
              repoTag, repo.calculateReleaseUri(package, github));
          print(result);
          results.addResult(result);
        }
      }
    }

    pub.close();

    return results;
  }

  /// Publish the indicated package in the repository.
  ///
  /// This is intended to be run on a github workflow in response to a git tag.
  /// It will:
  /// - validate the tag
  /// - validate the package exists
  /// - validate changelog and pubspec versions
  /// - perform a publish
  Future publish() async {
    final success = await _publish();
    if (!success && exitCode == 0) {
      exitCode = 1;
    }
  }

  Future<bool> _publish() async {
    final github = GithubApi();

    if (!expectEnv(github.refName, 'GITHUB_REF_NAME')) return false;

    // Validate the git tag.
    final tag = Tag(github.refName!);
    if (!tag.valid) {
      stderr.writeln("Git tag not in expected format: '$tag'");
      return false;
    }

    print("Publishing '$tag'");
    print('');

    final repo = Repository();
    final packages = repo.locatePackages();
    print('');
    print('Repository packages:');
    for (var package in packages) {
      print('  $package');
    }
    print('');

    // Find package to publish.
    Package package;
    if (repo.isSinglePackageRepo) {
      if (packages.isEmpty) {
        stderr.writeln('No publishable package found.');
        return false;
      }
      package = packages.first;
    } else {
      final name = tag.package;
      if (name == null) {
        stderr.writeln("Tag does not include package name ('$tag').");
        return false;
      }
      if (!packages.any((p) => p.name == name)) {
        stderr.writeln("Tag does not match a repo package ('$tag').");
        return false;
      }
      package = packages.firstWhere((p) => p.name == name);
    }

    print('');
    print('Publishing ${'package:${package.name}'}');
    print('');

    print('pubspec:');
    final pubspecVersion = package.pubspec.version?.toString();
    print('  version: $pubspecVersion');

    print('changelog:');
    print(package.changelog.describeLatestChanges);
    final changelogVersion = package.changelog.latestVersion;

    if (pubspecVersion != tag.version) {
      stderr.writeln(
          "Pubspec version ($pubspecVersion) and git tag ($tag) don't agree.");
      return false;
    }

    if (pubspecVersion != changelogVersion) {
      stderr.writeln('Pubspec version ($pubspecVersion) and changelog version '
          "($changelogVersion) don't agree.");
      return false;
    }

    await runCommand('dart', args: ['pub', 'get'], cwd: package.directory);
    print('');

    final result = await _runPublish(package, dryRun: false, force: true);
    if (result.code != 0) {
      exitCode = result.code;
    }
    return result.code == 0;
  }

  Future<CommandResult> _runPublish(
    Package package, {
    required bool dryRun,
    required bool force,
  }) async {
    String command;
    if (useFlutter) {
      command = 'flutter';
    } else {
      command = 'dart';
    }
    return await runCommand(
      command,
      args: [
        'pub',
        'publish',
        if (dryRun) '--dry-run',
        if (force) '--force',
      ],
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

  String describeAsMarkdown({bool withTag = true}) => results.map((r) {
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
        return '| package:${r.package.name} | ${r.package.version} | '
            '$sev${r.message}$tagColumn |';
      }).join('\n');
}

class Result {
  final Severity severity;
  final Package package;
  final String message;
  final String? gitTag;
  final Uri? publishReleaseUri;

  Result(this.severity, this.package, this.message,
      [this.gitTag, this.publishReleaseUri]);

  factory Result.fail(Package package, String message) =>
      Result(Severity.error, package, message);

  factory Result.info(Package package, String message) =>
      Result(Severity.info, package, message);

  factory Result.success(Package package, String message,
          [String? gitTag, Uri? publishReleaseUri]) =>
      Result(Severity.success, package, message, gitTag, publishReleaseUri);

  @override
  String toString() {
    final details = gitTag == null ? '' : ' ($gitTag)';
    return severity == Severity.error
        ? 'error: $message$details'
        : '$message$details';
  }
}
