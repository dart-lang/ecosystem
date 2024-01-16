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

const String _publishBotTag2 = '### Package publish validation';

const String _licenseBotTag = '### License Headers';

const String _changelogBotTag = '### Changelog Entry';

const String _doNotSubmitBotTag = '### Do Not Submit';

const String _coverageBotTag = '### Coverage';

const String _breakingBotTag = '### Breaking changes';

const checkTypes = <String>[
  'version',
  'license',
  'changelog',
  'coverage',
  'breaking',
  'do-not-submit',
];

class Health {
  final Directory directory;

  final String commentPath;

  Health(
    this.directory,
    this.check,
    this.warnOn,
    this.failOn,
    this.coverageweb,
    this.experiments,
    this.github, {
    Directory? base,
    String? comment,
  })  : baseDirectory = base ?? Directory('../base_repo'),
        commentPath = comment ??
            path.join(
              directory.path,
              'output',
              'comment.md',
            );
  final GithubApi github;

  final String check;
  final List<String> warnOn;
  final List<String> failOn;
  final bool coverageweb;
  final Directory baseDirectory;
  final List<String> experiments;

  Future<void> healthCheck() async {
    // Do basic validation of our expected env var.
    if (!expectEnv(github.repoSlug?.fullName, 'GITHUB_REPOSITORY')) return;
    if (!expectEnv(github.issueNumber?.toString(), 'ISSUE_NUMBER')) return;
    if (!expectEnv(github.sha, 'GITHUB_SHA')) return;

    print('Start health check for the check $check');
    print('Checking for $check');
    if (!github.prLabels.contains('skip-$check-check')) {
      final firstResult = await checkFor(check)();
      final HealthCheckResult finalResult;
      if (warnOn.contains(check) && firstResult.severity == Severity.error) {
        finalResult = firstResult.withSeverity(Severity.warning);
      } else if (failOn.contains(check) &&
          firstResult.severity == Severity.warning) {
        finalResult = firstResult.withSeverity(Severity.error);
      } else {
        finalResult = firstResult;
      }
      await writeInComment(github, finalResult);
      print('\n\n${finalResult.severity.name.toUpperCase()}: $check done.\n\n');
    } else {
      print('Skipping $check, as the skip tag is present.');
    }
  }

  String tagFor(String checkType) => switch (checkType) {
        'version' => _publishBotTag2,
        'license' => _licenseBotTag,
        'changelog' => _changelogBotTag,
        'coverage' => _coverageBotTag,
        'breaking' => _breakingBotTag,
        'do-not-submit' => _doNotSubmitBotTag,
        String() => throw ArgumentError('Invalid check type $checkType'),
      };

  Future<HealthCheckResult> Function() checkFor(String checkType) =>
      switch (checkType) {
        'version' => validateCheck,
        'license' => licenseCheck,
        'changelog' => changelogCheck,
        'coverage' => coverageCheck,
        'breaking' => breakingCheck,
        'do-not-submit' => doNotSubmitCheck,
        String() => throw ArgumentError('Invalid check type $checkType'),
      };

  Future<HealthCheckResult> validateCheck() async {
    //TODO: Add Flutter support for PR health checks
    var results = await Firehose(directory, false).verify(github);

    var markdownTable = '''
| Package | Version | Status |
| :--- | ---: | :--- |
${results.describeAsMarkdown(withTag: false)}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
    ''';

    return HealthCheckResult(
      'version',
      results.severity,
      markdownTable,
    );
  }

  Future<HealthCheckResult> breakingCheck() async {
    final filesInPR = await github.listFilesForPR(directory);
    final changeForPackage = <Package, BreakingChange>{};
    for (var package in packagesContaining(filesInPR)) {
      print('Look for changes in $package with base $baseDirectory');
      var relativePath =
          path.relative(package.directory.path, from: directory.path);
      var baseRelativePath = path.relative(
          path.join(baseDirectory.path, relativePath),
          from: directory.path);
      var tempDirectory = Directory.systemTemp..createSync();
      var reportPath = path.join(tempDirectory.path, 'report.json');
      var runApiTool = Process.runSync(
        'dart',
        [
          ...['pub', 'global', 'run'],
          'dart_apitool:main',
          'diff',
          ...['--old', baseRelativePath],
          ...['--new', relativePath],
          ...['--report-format', 'json'],
          ...['--report-file-path', reportPath],
        ],
        workingDirectory: directory.path,
      );
      print(runApiTool.stderr);
      print(runApiTool.stdout);

      var fullReportString = File(reportPath).readAsStringSync();
      var decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
      var report = decoded['report'] as Map<String, dynamic>;

      var formattedChanges = const JsonEncoder.withIndent('  ').convert(report);
      print('Breaking change report:\n$formattedChanges');

      final versionMap = decoded['version'] as Map<String, dynamic>;
      changeForPackage[package] = BreakingChange(
        level: _breakingLevel(report),
        oldVersion: Version.parse(versionMap['old'].toString()),
        newVersion: Version.parse(versionMap['new'].toString()),
        neededVersion: Version.parse(versionMap['needed'].toString()),
        versionIsFine: versionMap['success'] as bool,
        explanation: versionMap['explanation'].toString(),
      );
    }
    return HealthCheckResult(
      'breaking',
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

  BreakingLevel _breakingLevel(Map<String, dynamic> report) {
    BreakingLevel breakingLevel;
    if ((report['noChangesDetected'] as bool?) ?? false) {
      breakingLevel = BreakingLevel.none;
    } else if ((report['breakingChanges'] as Map? ?? {}).isNotEmpty) {
      breakingLevel = BreakingLevel.breaking;
    } else if ((report['nonBreakingChanges'] as Map? ?? {}).isNotEmpty) {
      breakingLevel = BreakingLevel.nonBreaking;
    } else {
      breakingLevel = BreakingLevel.none;
    }
    return breakingLevel;
  }

  Future<HealthCheckResult> licenseCheck() async {
    var files = await github.listFilesForPR(directory);
    var allFilePaths = await getFilesWithoutLicenses(directory);

    var groupedPaths = allFilePaths.groupListsBy((filePath) {
      return files.any((f) => f.filename == filePath);
    });

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
      changedFilesPaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> changelogCheck() async {
    var filePaths = await packagesWithoutChangelog(github, directory);

    final markdownResult = '''
| Package | Changed Files |
| :--- | :--- |
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => e.filename).join('<br />')} |').join('\n')}

Changes to files need to be [accounted for](https://github.com/dart-lang/ecosystem/wiki/Changelog) in their respective changelogs.
''';

    return HealthCheckResult(
      'changelog',
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> doNotSubmitCheck() async {
    final dns = 'DO_NOT${'_'}SUBMIT';

    final body = await github.pullrequestBody();
    final files = await github.listFilesForPR(directory);
    print('Checking for $dns strings: $files');
    final filesWithDNS = files
        .where((file) =>
            ![FileStatus.removed, FileStatus.unchanged].contains(file.status))
        .where((file) => File(file.pathInRepository).existsSync())
        .where((file) =>
            File(file.pathInRepository).readAsStringSync().contains(dns))
        .toList();
    print('Found files with $dns: $filesWithDNS');

    final bodyContainsDNS = body.contains(dns);
    print('The body contains a $dns string: $bodyContainsDNS');
    final markdownResult = '''
Body contains `$dns`: $bodyContainsDNS

| Files with `$dns` |
| :--- |
${filesWithDNS.map((e) => e.filename).map((e) => '|$e|').join('\n')}
''';

    final hasDNS = filesWithDNS.isNotEmpty || bodyContainsDNS;
    return HealthCheckResult(
      'do-not-submit',
      hasDNS ? Severity.error : Severity.success,
      hasDNS ? markdownResult : null,
    );
  }

  Future<HealthCheckResult> coverageCheck() async {
    var coverage = await Coverage(coverageweb, directory, experiments)
        .compareCoverages(github, baseDirectory);

    var markdownResult = '''
| File | Coverage |
| :--- | :--- |
${coverage.coveragePerFile.entries.map((e) => '|${e.key}| ${e.value.toMarkdown()} |').join('\n')}

This check for [test coverage](https://github.com/dart-lang/ecosystem/wiki/Test-Coverage) is informational (issues shown here will not fail the PR).
''';

    return HealthCheckResult(
      'coverage',
      Severity.values[coverage.coveragePerFile.values
          .map((change) => change.severity.index)
          .fold(0, max)],
      markdownResult,
    );
  }

  Future<void> writeInComment(
      GithubApi github, HealthCheckResult result) async {
    final String markdownSummary;
    if (result.markdown != null) {
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
      markdownSummary = '${tagFor(result.name)} ${result.severity.emoji}\n\n$s';
    } else {
      markdownSummary = '';
    }

    github.appendStepSummary(markdownSummary);

    var commentFile = File(commentPath);
    print('Saving comment markdown to file ${commentFile.path}');
    await commentFile.create(recursive: true);
    await commentFile.writeAsString(markdownSummary);

    if (result.severity == Severity.error && exitCode == 0) {
      exitCode = 1;
    }
  }

  List<Package> packagesContaining(List<GitFile> filesInPR) {
    var files = filesInPR.where((element) => element.status.isRelevant);
    final repo = Repository(directory);
    return repo
        .locatePackages()
        .where((package) => files.any((file) =>
            path.isWithin(package.directory.path, file.pathInRepository)))
        .toList();
  }
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
  final Severity severity;
  final String? markdown;

  HealthCheckResult(this.name, this.severity, this.markdown);

  HealthCheckResult withSeverity(Severity severity) => HealthCheckResult(
        name,
        severity,
        markdown,
      );
}

class BreakingChange {
  final BreakingLevel level;
  final Version oldVersion;
  final Version newVersion;
  final Version neededVersion;
  final bool versionIsFine;
  final String explanation;

  BreakingChange({
    required this.level,
    required this.oldVersion,
    required this.newVersion,
    required this.neededVersion,
    required this.versionIsFine,
    required this.explanation,
  });

  String toMarkdownRow() => [
        level.name,
        oldVersion,
        newVersion,
        versionIsFine ? neededVersion : '**$neededVersion** <br> $explanation',
        versionIsFine ? ':heavy_check_mark:' : ':warning:'
      ].map((e) => e.toString()).join('|');
}
