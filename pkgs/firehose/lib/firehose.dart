// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:io';
import 'dart:math';

import 'package:firehose/src/repo.dart';
import 'package:path/path.dart' as path;

import 'src/github.dart';
import 'src/pub.dart';
import 'src/utils.dart';

const String _botSuffix = '[bot]';

const String _githubActionsUser = 'github-actions[bot]';

const String _publishBotTag = '## Package publishing';
const String _publishBotTag2 = '### Package publish validation';

const String _licenseBotTag = '### License Headers';

const String _changelogBotTag = '### Changelog entry';

const String _prHealthTag = '## PR Health';

const String _ignoreWarningsLabel = 'publish-ignore-warnings';

class Firehose {
  final Directory directory;

  Firehose(this.directory);

  Future<void> healthCheck(List argResult) async {
    print('Start health check for the checks $argResult');
    var checks = [
      if (argResult.contains('version')) validateCheck,
      if (argResult.contains('license')) licenseCheck,
      if (argResult.contains('changelog')) changelogCheck,
    ];
    await _healthCheck(checks);
  }

  Future<void> _healthCheck(
      List<Future<HealthCheckResult> Function(Github)> checks) async {
    var github = Github();

    // Do basic validation of our expected env var.
    if (!_expectEnv(github.githubAuthToken, 'GITHUB_TOKEN')) return;
    if (!_expectEnv(github.repoSlug, 'GITHUB_REPOSITORY')) return;
    if (!_expectEnv(github.issueNumber, 'ISSUE_NUMBER')) return;
    if (!_expectEnv(github.sha, 'GITHUB_SHA')) return;

    if ((github.actor ?? '').endsWith(_botSuffix)) {
      print('Skipping package validation for ${github.actor} PRs.');
      return;
    }

    var checked =
        await Future.wait(checks.map((check) => check(github)).toList());
    await writeInComment(github, checked);

    github.close();
  }

  Future<HealthCheckResult> validateCheck(Github github) async {
    var results = await _validate(github);

    var markdownTable = '''
| Package | Version | Status | Publish tag (post-merge) |
| :--- | ---: | :--- | ---: |
${results.describeAsMarkdown}

    ''';

    return HealthCheckResult(
      _publishBotTag2,
      results.severity,
      markdownTable,
    );
  }

  Future<HealthCheckResult> licenseCheck(Github github) async {
    final license = '''
// Copyright (c) ${DateTime.now().year}, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.''';

    var filePaths = await _getFilesWithoutLicenses(github);

    var markdownResult = '''
Some `.dart` files were found to not have license headers. Please add the following header to all listed files:
```
$license
```

| Files |
| :--- |
${filePaths.map((e) => '|$e|').join('\n')}

Either manually or by running the following in your repository directory

```
dart pub global activate --source git https://github.com/mosuem/file_licenser
dart pub global run file_licenser .
```

'''; //TODO: replace by pub.dev version

    return HealthCheckResult(
      _licenseBotTag,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> changelogCheck(Github github) async {
    var filePaths = await _packagesWithoutChangelog(github);

    final markdownResult = '''
Changes to these files need to be accounted for in their respective changelogs:

| Package | Files |
| :--- | :--- |
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => path.relative(e, from: Directory.current.path)).join('<br />')} |').join('\n')}
''';

    return HealthCheckResult(
      _changelogBotTag,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<Map<Package, List<String>>> _packagesWithoutChangelog(
      Github github) async {
    final repo = Repository();
    final packages = repo.locatePackages();

    final files = await github.listFilesForPR();
    print('Collecting packages without changed changelogs:');
    final packagesWithoutChangedChangelog = packages.where((package) {
      var changelogPath = package.changelog.file.path;
      var changelog =
          path.relative(changelogPath, from: Directory.current.path);
      return !files.contains(changelog);
    }).toList();
    print('Done, found ${packagesWithoutChangedChangelog.length} packages.');

    print('Collecting files without license headers in those packages:');
    var packagesWithChanges = <Package, List<String>>{};
    for (final file in files) {
      for (final package in packagesWithoutChangedChangelog) {
        if (fileNeedsEntryInChangelog(package, file)) {
          print(file);
          packagesWithChanges.update(
            package,
            (changedFiles) => [...changedFiles, file],
            ifAbsent: () => [file],
          );
        }
      }
    }
    print('''
Done, found ${packagesWithChanges.length} packages with a need for a changelog.''');
    return packagesWithChanges;
  }

  bool fileNeedsEntryInChangelog(Package package, String file) {
    //TODO: Add conditions, such as file is not a markdown etc. Find out what is
    //sensible.
    var directoryPath = package.directory.path;
    var directory = path.relative(directoryPath, from: Directory.current.path);
    return path.isWithin(directory, file);
  }

  Future<List<String>> _getFilesWithoutLicenses(Github github) async {
    var dir = Directory.current;
    var dartFiles = await dir
        .list(recursive: true)
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    print('Collecting files without license headers:');
    var filesWithoutLicenses = dartFiles
        .map((file) {
          var fileContents = File(file.path).readAsStringSync();
          var fileContainsCopyright = fileContents.contains('// Copyright (c)');
          if (!fileContainsCopyright) {
            var relativePath =
                path.relative(file.path, from: Directory.current.path);
            print(relativePath);
            return relativePath;
          }
        })
        .whereType<String>()
        .toList();
    print('''
Done, found ${filesWithoutLicenses.length} files without license headers''');
    return filesWithoutLicenses;
  }

  /// Validate the packages in the repository.
  ///
  /// This method is intended to run in the context of a PR. It will:
  /// - determine the set of packages in the repo
  /// - validate that the changelog version == the pubspec version
  /// - provide feedback on the PR (via a PR comment) about packages which are
  ///   ready to publish
  Future<void> validate() async {
    var github = Github();

    // Do basic validation of our expected env var.
    if (!_expectEnv(github.githubAuthToken, 'GITHUB_TOKEN')) return;
    if (!_expectEnv(github.repoSlug, 'GITHUB_REPOSITORY')) return;
    if (!_expectEnv(github.issueNumber, 'ISSUE_NUMBER')) return;
    if (!_expectEnv(github.sha, 'GITHUB_SHA')) return;

    if ((github.actor ?? '').endsWith(_botSuffix)) {
      print('Skipping package validation for ${github.actor} PRs.');
      return;
    }

    var results = await _validate(github);

    var markdownTable = '''
| Package | Version | Status | Publish tag (post-merge) |
| :--- | ---: | :--- | ---: |
${results.describeAsMarkdown}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
''';
    github.appendStepSummary(markdownTable);

    var existingCommentId = await allowFailure(
      github.findCommentId(
        github.repoSlug!,
        github.issueNumber!,
        user: _githubActionsUser,
        searchTerm: _publishBotTag,
      ),
      logError: print,
    );

    if (results.hasSuccess) {
      var commentText = '$_publishBotTag\n\n$markdownTable';

      if (existingCommentId == null) {
        await allowFailure(
          github.createComment(
              github.repoSlug!, github.issueNumber!, commentText),
          logError: print,
        );
      } else {
        await allowFailure(
          github.updateComment(
              github.repoSlug!, existingCommentId, commentText),
          logError: print,
        );
      }
    } else {
      if (results.hasError && exitCode == 0) {
        exitCode = 1;
      }

      if (existingCommentId != null) {
        await allowFailure(
          github.deleteComment(github.repoSlug!, existingCommentId),
          logError: print,
        );
      }
    }

    github.close();
  }

  Future<void> writeInComment(
    Github github,
    List<HealthCheckResult> results,
  ) async {
    var commentText = results.map((e) {
      var markdown = e.markdown;
      var s = '''
<details>
<summary${e.severity == Severity.error ? ' open' : ''}>
Details
</summary>

$markdown
</details>

''';
      return '${e.tag} ${e.severity.emoji}\n\n$s';
    }).join('\n');

    var summary = '$_prHealthTag\n\n$commentText';
    github.appendStepSummary(summary);

    var repoSlug = github.repoSlug!;
    var issueNumber = github.issueNumber!;

    var existingCommentId = await allowFailure(
      github.findCommentId(
        repoSlug,
        issueNumber,
        user: _githubActionsUser,
        searchTerm: _prHealthTag,
      ),
      logError: print,
    );

    if (existingCommentId == null) {
      await allowFailure(
        github.createComment(repoSlug, issueNumber, summary),
        logError: print,
      );
    } else {
      await allowFailure(
        github.updateComment(repoSlug, existingCommentId, summary),
        logError: print,
      );
    }

    if (results.any((result) => result.severity == Severity.error) &&
        exitCode == 0) {
      exitCode = 1;
    }
  }

  Future<VerificationResults> _validate(Github github) async {
    var repo = Repository();
    var packages = repo.locatePackages();

    var pub = Pub();

    var results = VerificationResults();

    for (var package in packages) {
      var repoTag = repo.calculateRepoTag(package);

      print('');
      print('Validating $package:${package.name}');

      print('pubspec:');
      var pubspecVersion = package.pubspec.version;
      if (pubspecVersion == null) {
        var result = Result.fail(
          package,
          "no version specified (perhaps you need a' publish_to: none' entry?)",
        );
        print(result);
        results.addResult(result);
        continue;
      }
      print('  - version: $pubspecVersion');

      var changelogVersion = package.changelog.latestVersion;
      print('changelog:');
      print(package.changelog.describeLatestChanges.trimRight());

      if (pubspecVersion != changelogVersion) {
        var result = Result.fail(
          package,
          'pubspec version ($pubspecVersion) and changelog ($changelogVersion) '
          "don't agree",
        );
        print(result);
        results.addResult(result);
        continue;
      }

      if (await pub.hasPublishedVersion(package.name, pubspecVersion)) {
        var result = Result.info(package, 'already published at pub.dev');
        print(result);
        results.addResult(result);
      } else if (package.pubspec.isPreRelease) {
        var result = Result.info(
          package,
          'version $pubspecVersion is pre-release; no publish necessary',
        );
        print(result);
        results.addResult(result);
      } else {
        var code = await runCommand('dart',
            args: ['pub', 'publish', '--dry-run'], cwd: package.directory);

        final ignoreWarnings = github.prLabels.contains(_ignoreWarningsLabel);

        if (code != 0 && !ignoreWarnings) {
          exitCode = code;
          var message =
              'pub publish dry-run failed; add the `$_ignoreWarningsLabel` '
              'label to ignore';
          github.notice(message: message);
          results.addResult(Result.fail(package, message));
        } else {
          var result = Result.success(package, '**ready to publish**', repoTag,
              repo.calculateReleaseUri(package, github));
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
    var success = await _publish();
    if (!success && exitCode == 0) {
      exitCode = 1;
    }
  }

  Future<bool> _publish() async {
    var github = Github();

    if (!_expectEnv(github.refName, 'GITHUB_REF_NAME')) return false;

    // Validate the git tag.
    var tag = Tag(github.refName!);
    if (!tag.valid) {
      stderr.writeln("Git tag not in expected format: '$tag'");
      return false;
    }

    print("Publishing '$tag'");
    print('');

    var repo = Repository();
    var packages = repo.locatePackages();
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
      var name = tag.package;
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
    var pubspecVersion = package.pubspec.version;
    print('  version: $pubspecVersion');

    print('changelog:');
    print(package.changelog.describeLatestChanges);
    var changelogVersion = package.changelog.latestVersion;

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

    var result = await runCommand('dart',
        args: ['pub', 'publish', '--force'], cwd: package.directory);
    if (result != 0) {
      exitCode = result;
    }
    return result == 0;
  }

  bool _expectEnv(String? value, String name) {
    if (value == null) {
      print("Expected environment variable not found: '$name'");
      return false;
    } else {
      return true;
    }
  }
}

class VerificationResults {
  final List<Result> results = [];

  void addResult(Result result) => results.add(result);

  Severity get severity =>
      Severity.values[results.map((e) => e.severity.index).reduce(max)];

  bool get hasSuccess => results.any((r) => r.severity == Severity.success);

  bool get hasError => results.any((r) => r.severity == Severity.error);

  String get describeAsMarkdown {
    results.sort((a, b) => Enum.compareByIndex(a.severity, b.severity));

    return results.map((r) {
      var sev = r.severity == Severity.error ? '(error) ' : '';
      var tag = r.gitTag == null ? '' : '`${r.gitTag}`';
      var publishReleaseUri = r.publishReleaseUri;
      if (publishReleaseUri != null) {
        tag = '[$tag]($publishReleaseUri)';
      }

      return '| package:${r.package.name} | ${r.package.version} | '
          '$sev${r.message} | $tag |';
    }).join('\n');
  }
}

class HealthCheckResult {
  final String tag;
  final Severity severity;
  final String markdown;

  HealthCheckResult(this.tag, this.severity, this.markdown);
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

enum Severity {
  success,
  info,
  error;

  String get emoji => switch (this) {
        Severity.info => ':heavy_check_mark:',
        Severity.error => ':exclamation:',
        success => ':heavy_check_mark:',
      };
}
