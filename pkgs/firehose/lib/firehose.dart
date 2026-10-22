// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

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
const String _publishBotDescription = 'If you have publishing permissions, '
    'you can use the links below to publish the changes after merging this PR.';

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

    await inLogGroup('Preparing PR comment', () async {
      final existingCommentId = await allowFailure(
        github.findCommentId(
          user: _githubActionsUser,
          searchTerm: _publishBotTag,
        ),
        logError: print,
      );

      if (existingCommentId != null) {
        final idFile = File('./output/commentId');
        print('''
Saving existing comment id $existingCommentId to file ${idFile.path}''');
        await idFile.create(recursive: true);
        await idFile.writeAsString(existingCommentId.toString());
      }

      if (results.hasSuccess || existingCommentId != null) {
        final description =
            results.hasSuccess ? '$_publishBotDescription\n\n' : '';
        final commentText = '$_publishBotTag\n\n'
            '$description'
            '$markdownTable';

        final commentFile = File('./output/comment.md');
        print('Saving comment markdown to file ${commentFile.path}');
        await commentFile.create(recursive: true);
        await commentFile.writeAsString(commentText);
      }
    });

    // Print the release links last, outside of any group, so they are easy to
    // find in the log even if the PR comment can't be written.
    print('');
    print(results.describeForLog());

    if (results.hasError && exitCode == 0) {
      exitCode = 1;
    }

    github.close();
  }

  Future<VerificationResults> verify(GithubApi github, {Pub? pub}) async {
    final repo = Repository(directory);
    final packages = await inLogGroup(
      'Locating packages',
      () => repo.locatePackages(ignore: ignoredPackages),
    );

    final filesInPR = await allowFailure(
      github.listFilesForPR(directory, ignoredPackages),
      logError: print,
    );
    final relevantFiles = filesInPR?.where((f) => f.status.isRelevant).toList();

    final pubClient = pub ?? Pub();

    Future<List<GitFile>?>? g3FilesFuture;
    Future<List<GitFile>?> getG3Files() =>
        g3FilesFuture ??= allowFailure<List<GitFile>?>(
          github.listFilesSinceRef(directory, 'g3', ignoredPackages),
          logError: print,
        );

    final results = VerificationResults();

    for (final package in packages) {
      final packageFiles =
          relevantFiles?.where((f) => f.isInPackage(package)).toList();
      final isAffected = packageFiles == null || packageFiles.isNotEmpty;

      final result = await inLogGroup(
        'Validating package:${package.name} ${package.version}',
        () async {
          final result = await _verifyPackage(
            package,
            repo,
            github,
            pubClient,
            getG3Files: getG3Files,
            packageFiles: packageFiles,
            isAffected: isAffected,
          );
          print(result);
          return result;
        },
      );
      results.addResult(result);
    }

    if (pub == null) {
      pubClient.close();
    }

    return results;
  }

  /// Validates a single [package] and returns the result.
  ///
  /// The [packageFiles] are the files in [package] modified by the PR, or
  /// `null` if the files in the PR could not be determined.
  Future<Result> _verifyPackage(
    Package package,
    Repository repo,
    GithubApi github,
    Pub pubClient, {
    required Future<List<GitFile>?> Function() getG3Files,
    required List<GitFile>? packageFiles,
    required bool isAffected,
  }) async {
    print('pubspec:');
    final pubspecVersion = package.pubspec.version?.toString();
    if (pubspecVersion == null) {
      return Result.fail(
        package,
        "no version specified (perhaps you need a' publish_to: none' entry?)",
        isAffected: isAffected,
      );
    }
    print('  - version: $pubspecVersion');

    final changelogVersion = package.changelog.latestVersion;
    print('changelog:');
    print(package.changelog.describeLatestChanges.trimRight());

    if (pubspecVersion != changelogVersion) {
      return Result.fail(
        package,
        'pubspec version ($pubspecVersion) and changelog ($changelogVersion) '
        "don't agree",
        isAffected: isAffected,
      );
    }

    final hasWarningsLabel = github.prLabels.contains(_ignoreWarningsLabel);

    if (await pubClient.hasPublishedVersion(package.name, pubspecVersion)) {
      final hasNonChangelogChanges = packageFiles != null &&
          packageFiles.any(
            (f) =>
                !path.equals(
                  f.pathInRepository,
                  package.changelog.file.path,
                ) &&
                !path.split(f.filename).contains('.github'),
          );
      if (hasNonChangelogChanges && !hasWarningsLabel) {
        return Result.fail(
          package,
          'version $pubspecVersion is already published at pub.dev; '
          'bump to a `-wip` version (or add the `$_ignoreWarningsLabel` '
          'label to ignore)',
          isAffected: isAffected,
        );
      }
      return Result.info(
        package,
        Result.alreadyPublishedMessage,
        isAffected: isAffected,
      );
    }

    if (package.pubspec.version!.wip) {
      return Result.info(
        package,
        Result.wipMessage,
        isAffected: isAffected,
      );
    }

    final g3Files = await getG3Files();
    if (g3Files != null && !hasWarningsLabel) {
      final pubspecPath = path.join(package.directory.path, 'pubspec.yaml');
      final hasUnsyncedG3Changes = g3Files.any(
        (f) =>
            f.status.isRelevant &&
            f.isInPackage(package) &&
            !path.equals(f.pathInRepository, pubspecPath) &&
            !path.equals(f.pathInRepository, package.changelog.file.path) &&
            !path.split(f.filename).contains('.github'),
      );
      if (hasUnsyncedG3Changes) {
        return Result.fail(
          package,
          'package has changes not yet synced to google3 '
          '(or add the `$_ignoreWarningsLabel` label to ignore)',
          isAffected: isAffected,
        );
      }
    }

    const preReleaseText =
        'consider publishing the package as a pre-release instead';

    final result = await _runPublish(package, dryRun: true, force: false);

    final hasPreReleaseText = result.stdout.contains(preReleaseText);
    final ignoreWarnings = hasPreReleaseText || hasWarningsLabel;

    if (result.code != 0 && !ignoreWarnings) {
      exitCode = result.code;
      final message =
          'pub publish dry-run failed; add the `$_ignoreWarningsLabel` '
          'label to ignore';
      github.notice(message: message);
      return Result.fail(package, message, isAffected: isAffected);
    }

    return Result.success(
      package,
      '**ready to publish**',
      gitTag: repo.calculateRepoTag(package, tagPrefix: tagPrefix),
      publishReleaseUri: repo.calculateReleaseUri(
        package,
        github,
        tagPrefix: tagPrefix,
      ),
      isAffected: isAffected,
    );
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
    final tag = Tag(github.refName!, prefix: tagPrefix);
    if (!tag.valid) {
      stderr.writeln("Git tag not in expected format: '$tag'");
      return false;
    }

    print("Publishing '$tag'");
    print('');

    final repo = Repository();
    final packages = await inLogGroup('Locating packages', () {
      final packages = repo.locatePackages();
      print('');
      print('Repository packages:');
      for (final package in packages) {
        print('  $package');
      }
      return packages;
    });
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
        "Pubspec version ($pubspecVersion) and git tag ($tag) don't agree.",
      );
      return false;
    }

    if (pubspecVersion != changelogVersion) {
      stderr.writeln(
        'Pubspec version ($pubspecVersion) and changelog version '
        "($changelogVersion) don't agree.",
      );
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
      args: ['pub', 'publish', if (dryRun) '--dry-run', if (force) '--force'],
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

  /// A plain text description of the results which need action, for the end
  /// of the workflow log.
  ///
  /// Lists any errors, and the links to create a GitHub release for each
  /// package which is ready to publish.
  String describeForLog() {
    final buffer = StringBuffer();

    final errors = results.where((r) => r.severity == Severity.error);
    if (errors.isNotEmpty) {
      buffer.writeln('Packages with errors:');
      for (final r in errors) {
        buffer.writeln('  package:${r.package.name} ${r.package.version}: '
            '${r.message}');
      }
      buffer.writeln();
    }

    final ready = results.where((r) => r.severity == Severity.success);
    if (ready.isEmpty) {
      buffer.writeln('No packages are ready to publish.');
    } else {
      buffer
        ..writeln('Packages ready to publish:')
        ..writeln(_publishBotDescription)
        ..writeln();
      for (final r in ready) {
        final tag = r.gitTag == null ? '' : ' (${r.gitTag})';
        buffer.writeln('  package:${r.package.name} ${r.package.version}$tag');
        final publishReleaseUri = r.publishReleaseUri;
        if (publishReleaseUri != null) {
          buffer.writeln('    $publishReleaseUri');
        }
      }
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
