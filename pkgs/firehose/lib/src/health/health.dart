// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../../firehose.dart';
import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'changelog.dart';
import 'coverage.dart';
import 'license.dart';

const String _botSuffix = '[bot]';

const String _githubActionsUser = 'github-actions[bot]';

const String _publishBotTag2 = '### Package publish validation';

const String _licenseBotTag = '### License Headers';

const String _changelogBotTag = '### Changelog Entry';

const String _doNotSubmitBotTag = '### Do Not Submit';

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
      if (args.contains('do-not-submit') &&
          !github.prLabels.contains('skip-do-not-submit-check'))
        doNotSubmitCheck,
    ];

    var checked =
        await Future.wait(checks.map((check) => check(github)).toList());
    await writeInComment(github, checked);

    github.close();
  }

  Future<HealthCheckResult> validateCheck(Github github) async {
    //TODO: Add Flutter support for PR health checks
    var results = await Firehose(directory, false).verify(github);

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
    var changeForPackage = <Package, BreakingChange>{};
    var baseDirectory = Directory('../base_repo');
    for (var package in packages) {
      var currentPath =
          path.relative(package.directory.path, from: Directory.current.path);
      var basePackage = path.relative(
        path.join(baseDirectory.absolute.path, currentPath),
        from: currentPath,
      );
      print('Look for changes in $currentPath with base $basePackage');
      var runApiTool = Process.runSync(
        'dart',
        [
          ...['pub', 'global', 'run'],
          'dart_apitool:main',
          'diff',
          ...['--old', basePackage],
          ...['--new', '.'],
          ...['--report-format', 'json'],
          ...['--report-file-path', 'report.json'],
        ],
        workingDirectory: currentPath,
      );
      print(runApiTool.stderr);
      print(runApiTool.stdout);

      final reportFile = File(path.join(currentPath, 'report.json'));
      var fullReportString = reportFile.readAsStringSync();
      var decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
      var report = decoded['report'] as Map<String, dynamic>;

      var formattedChanges = const JsonEncoder.withIndent('  ').convert(report);
      print('Breaking change report:\n$formattedChanges');

      BreakingLevel breakingLevel;
      if ((report['noChangesDetected'] as bool?) ?? false) {
        breakingLevel = BreakingLevel.none;
      } else {
        if ((report['breakingChanges'] as Map? ?? {}).isNotEmpty) {
          breakingLevel = BreakingLevel.breaking;
        } else if ((report['nonBreakingChanges'] as Map? ?? {}).isNotEmpty) {
          breakingLevel = BreakingLevel.nonBreaking;
        } else {
          breakingLevel = BreakingLevel.none;
        }
      }

      var oldPackage = Package(
        Directory(path.join(baseDirectory.path, currentPath)),
        package.repository,
      );
      changeForPackage[package] = BreakingChange(
        level: breakingLevel,
        oldVersion: oldPackage.version!,
        newVersion: package.version!,
      );
    }
    return HealthCheckResult(
      'breaking',
      _breakingBotTag,
      changeForPackage.values.any((element) => !element.versionIsFine)
          ? Severity.warning
          : Severity.info,
      '''
| Package | Change | Current Version | New Version | Needed Version | Looking good? |
| :--- | :--- | ---: | ---: | ---: | ---: |
${changeForPackage.entries.map((e) => '|${e.key.name}|${e.value.toMarkdownRow()}|').join('\n')}
''',
    );
  }

  Future<HealthCheckResult> licenseCheck(Github github) async {
    var files = await github.listFilesForPR();
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

  Future<HealthCheckResult> doNotSubmitCheck(Github github) async {
    final files = await github.listFilesForPR();
    print('Checking for DO_NOT${'_'}SUBMIT strings: $files');
    var filesWithDNS = files
        .where((file) =>
            ![FileStatus.removed, FileStatus.unchanged].contains(file.status))
        .where((file) => File(file.relativePath)
            .readAsStringSync()
            .contains('DO_NOT${'_'}SUBMIT'))
        .toList();
    print('Found files with DO_NOT_${'SUBMIT'}: $filesWithDNS');
    final markdownResult = '''
| Files with `DO_NOT_${'SUBMIT'}` |
| :--- |
${filesWithDNS.map((e) => e.filename).map((e) => '|$e|').join('\n')}
''';

    return HealthCheckResult(
      'do-not-submit',
      _doNotSubmitBotTag,
      filesWithDNS.isNotEmpty ? Severity.error : Severity.success,
      filesWithDNS.isNotEmpty ? markdownResult : null,
    );
  }

  Future<HealthCheckResult> coverageCheck(
    Github github,
    bool coverageWeb,
  ) async {
    var coverage = await Coverage(coverageWeb).compareCoverages(github);

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
    var commentText =
        results.where((result) => result.markdown != null).map((result) {
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
      return '${result.title} ${result.severity.emoji}\n\n$s';
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

Version getNewVersion(BreakingLevel level, Version oldVersion) {
  return switch (level) {
    BreakingLevel.none => oldVersion,
    BreakingLevel.nonBreaking => oldVersion.nextMinor,
    BreakingLevel.breaking => oldVersion.nextBreaking,
  };
}

enum BreakingLevel {
  none('None'),
  nonBreaking('Non-Breaking'),
  breaking('Breaking');

  final String name;

  const BreakingLevel(this.name);
}

class HealthCheckResult {
  final String name;
  final String title;
  final Severity severity;
  final String? markdown;

  HealthCheckResult(this.name, this.title, this.severity, this.markdown);
}

class BreakingChange {
  final BreakingLevel level;
  final Version oldVersion;
  final Version newVersion;

  BreakingChange({
    required this.level,
    required this.oldVersion,
    required this.newVersion,
  });

  Version get suggestedNewVersion => getNewVersion(level, oldVersion);

  bool get versionIsFine => newVersion == suggestedNewVersion;

  String toMarkdownRow() => [
        level.name,
        oldVersion,
        newVersion,
        versionIsFine ? suggestedNewVersion : '**$suggestedNewVersion**',
        versionIsFine ? ':heavy_check_mark:' : ':warning:'
      ].map((e) => e.toString()).join('|');
}
