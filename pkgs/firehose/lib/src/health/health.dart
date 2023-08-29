// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:firehose/firehose.dart';

import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'changelog.dart';
import 'coverage.dart';
import 'license.dart';
import 'package:path/path.dart' as path;

const String _botSuffix = '[bot]';

const String _githubActionsUser = 'github-actions[bot]';

const String _publishBotTag2 = '### Package publish validation';

const String _licenseBotTag = '### License Headers';

const String _changelogBotTag = '### Changelog Entry';

const String _coverageBotTag = '### Coverage';

const String _breakingBotTag = '### Breaking changes';

const String _prHealthTag = '## PR Health';

class Health {
  final Directory directory;

  Health(this.directory);

  Future<void> healthCheck(List args, bool coverageweb) async {
    var github = Github();

    // Do basic validation of our expected env var.
    if (!expectEnv(github.githubAuthToken, 'GITHUB_TOKEN')) return;
    if (!expectEnv(github.repoSlug, 'GITHUB_REPOSITORY')) return;
    if (!expectEnv(github.issueNumber, 'ISSUE_NUMBER')) return;
    if (!expectEnv(github.sha, 'GITHUB_SHA')) return;

    if ((github.actor ?? '').endsWith(_botSuffix)) {
      print('Skipping package validation for ${github.actor} PRs.');
      return;
    }

    print('Start health check for the checks $args');
    var checks = [
      if (args.contains('version') &&
          !github.prLabels.contains('skip-validate-check'))
        validateCheck,
      if (args.contains('license') &&
          !github.prLabels.contains('skip-license-check'))
        licenseCheck,
      if (args.contains('changelog') &&
          !github.prLabels.contains('skip-changelog-check'))
        changelogCheck,
      if (args.contains('coverage') &&
          !github.prLabels.contains('skip-coverage-check'))
        (Github github) => coverageCheck(github, coverageweb),
      if (args.contains('breaking') &&
          !github.prLabels.contains('skip-breaking-check'))
        breakingCheck,
    ];

    var checked =
        await Future.wait(checks.map((check) => check(github)).toList());
    await writeInComment(github, checked);

    github.close();
  }

  Future<HealthCheckResult> validateCheck(Github github) async {
    var results = await Firehose(directory).verify(github);

    var markdownTable = '''
| Package | Version | Status |
| :--- | ---: | :--- |
${results.describeAsMarkdown(withTag: false)}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
    ''';

    return HealthCheckResult(
      'validate',
      _publishBotTag2,
      results.severity,
      markdownTable,
    );
  }

  Future<HealthCheckResult> breakingCheck(Github github) async {
    final repo = Repository();
    final packages = repo.locatePackages();
    var totalOut = '';
    var baseDirectory = Directory('../base_repo');
    for (var package in packages) {
      var currentPath =
          path.relative(package.directory.path, from: Directory.current.path);
      var basePackage = path.join(baseDirectory.path, currentPath);
      print('Look for changes in $currentPath with base $basePackage');
      var getApiTool = Process.runSync(
          'dart', ['pub', 'global', 'activate', 'dart_apitool']);
      print('getApiTool: err:${getApiTool.stderr}, out:${getApiTool.stdout}');
      if (getApiTool.exitCode != 0) {
        throw ProcessException('dart pub global', ['activate dart_apitool'],
            'Failed to install api tool');
      }
      var runApiTool = Process.runSync(
        'dart-apitool',
        [
          'diff',
          '--old',
          basePackage,
          '--new',
          '.',
        ],
        workingDirectory: currentPath,
      );
      print('runApiTool: err:${runApiTool.stderr}, out:${runApiTool.stdout}');
      totalOut += runApiTool.stdout.toString();
    }
    return HealthCheckResult(
      'breaking',
      _breakingBotTag,
      Severity.info,
      '''
$totalOut
''',
    );
  }

  Future<HealthCheckResult> licenseCheck(Github github) async {
    var files = await Github().listFilesForPR();
    var allFilePaths = await getFilesWithoutLicenses(Directory.current);

    var groupedPaths = allFilePaths
        .groupListsBy((path) => files.any((f) => f.relativePath == path));

    var unchangedFilesPaths = groupedPaths[false] ?? [];
    var unchangedMarkdown = '''
<details>
<summary>
Unrelated files missing license headers
</summary>

| Files |
| :--- |
${unchangedFilesPaths.map((e) => '|$e|').join('\n')}
</details>
''';

    var changedFilesPaths = groupedPaths[true] ?? [];
    var markdownResult = '''
```
$license
```

| Files |
| :--- |
${changedFilesPaths.isNotEmpty ? changedFilesPaths.map((e) => '|$e|').join('\n') : '| _no missing headers_  |'}

All source files should start with a [license header](https://github.com/dart-lang/ecosystem/wiki/License-Header).

${unchangedFilesPaths.isNotEmpty ? unchangedMarkdown : ''}

''';

    return HealthCheckResult(
      'license',
      _licenseBotTag,
      changedFilesPaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> changelogCheck(Github github) async {
    var filePaths = await packagesWithoutChangelog(github);

    final markdownResult = '''
| Package | Changed Files |
| :--- | :--- |
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => e.relativePath).join('<br />')} |').join('\n')}

Changes to files need to be [accounted for](https://github.com/dart-lang/ecosystem/wiki/Changelog) in their respective changelogs.
''';

    return HealthCheckResult(
      'changelog',
      _changelogBotTag,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> coverageCheck(
    Github github,
    bool coverageWeb,
  ) async {
    var coverage = await Coverage(coverageWeb).compareCoverages();

    var markdownResult = '''
| File | Coverage |
| :--- | :--- |
${coverage.coveragePerFile.entries.map((e) => '|${e.key}| ${e.value.toMarkdown()} |').join('\n')}

This check for [test coverage](https://github.com/dart-lang/ecosystem/wiki/Test-Coverage) is informational (issues shown here will not fail the PR).
''';

    return HealthCheckResult(
      'coverage',
      _coverageBotTag,
      Severity.values[coverage.coveragePerFile.values
          .map((change) => change.severity.index)
          .fold(0, max)],
      markdownResult,
    );
  }

  Future<void> writeInComment(
    Github github,
    List<HealthCheckResult> results,
  ) async {
    var commentText = results.map((result) {
      var markdown = result.markdown;
      var isWorseThanInfo = result.severity.index >= Severity.warning.index;
      var s = '''
<details${isWorseThanInfo ? ' open' : ''}>
<summary>
Details
</summary>

$markdown

${isWorseThanInfo ? 'This check can be disabled by tagging the PR with `skip-${result.name}-check`' : ''}
</details>

''';
      return '${result.tag} ${result.severity.emoji}\n\n$s';
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

    if (existingCommentId != null) {
      var idFile = File('./output/commentId');
      print('''
Saving existing comment id $existingCommentId to file ${idFile.path}''');
      await idFile.create(recursive: true);
      await idFile.writeAsString(existingCommentId.toString());
    }

    var commentFile = File('./output/comment.md');
    print('Saving comment markdown to file ${commentFile.path}');
    await commentFile.create(recursive: true);
    await commentFile.writeAsString(summary);

    if (results.any((result) => result.severity == Severity.error) &&
        exitCode == 0) {
      exitCode = 1;
    }
  }
}

class HealthCheckResult {
  final String name;
  final String tag;
  final Severity severity;
  final String markdown;

  HealthCheckResult(this.name, this.tag, this.severity, this.markdown);
}
