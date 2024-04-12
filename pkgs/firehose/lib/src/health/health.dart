// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../../firehose.dart';
import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'changelog.dart';
import 'coverage.dart';
import 'license.dart';

enum Check {
  version('### Package publish validation', 'version'),
  license('### License Headers', 'license'),
  changelog('### Changelog Entry', 'changelog'),
  coverage('### Coverage', 'coverage'),
  breaking('### Breaking changes', 'breaking'),
  leaking('### API leaks', 'leaking'),
  donotsubmit('### Do Not Submit', 'do-not-submit');

  final String tag;

  final String name;

  const Check(this.tag, this.name);
}

class Health {
  final Directory directory;

  final String commentPath;

  Health(
    this.directory,
    this.check,
    this.warnOn,
    this.failOn,
    this.coverageweb,
    List<String> ignoredPackages,
    List<String> ignoredLicense,
    List<String> ignoredCoverage,
    this.experiments,
    this.github, {
    Directory? base,
    String? comment,
  })  : ignoredPackages = ignoredPackages
            .map((pattern) => Glob(pattern, recursive: true))
            .toList(),
        ignoredFilesForCoverage = ignoredCoverage
            .map((pattern) => Glob(pattern, recursive: true))
            .toList(),
        ignoredFilesForLicense = ignoredLicense
            .map((pattern) => Glob(pattern, recursive: true))
            .toList(),
        baseDirectory = base ?? Directory('../base_repo'),
        commentPath = comment ??
            path.join(
              directory.path,
              'output',
              'comment.md',
            );
  final GithubApi github;

  final Check check;
  final List<String> warnOn;
  final List<String> failOn;
  final bool coverageweb;
  final List<Glob> ignoredPackages;
  final List<Glob> ignoredFilesForLicense;
  final List<Glob> ignoredFilesForCoverage;
  final Directory baseDirectory;
  final List<String> experiments;

  Future<void> healthCheck() async {
    // Do basic validation of our expected env var.
    if (!expectEnv(github.repoSlug?.fullName, 'GITHUB_REPOSITORY')) return;
    if (!expectEnv(github.issueNumber?.toString(), 'ISSUE_NUMBER')) return;
    if (!expectEnv(github.sha, 'GITHUB_SHA')) return;

    var checkName = check.name;
    print('Start health check for the check $checkName with');
    print(' warnOn: $warnOn');
    print(' failOn: $failOn');
    print(' coverageweb: $coverageweb');
    print(' ignoredPackages: $ignoredPackages');
    print(' ignoredForLicense: $ignoredFilesForLicense');
    print(' ignoredForCoverage: $ignoredFilesForCoverage');
    print(' baseDirectory: $baseDirectory');
    print(' experiments: $experiments');
    print('Checking for $checkName');
    if (!github.prLabels.contains('skip-$checkName-check')) {
      final firstResult = await checkFor(check)();
      final HealthCheckResult finalResult;
      if (warnOn.contains(check.name) &&
          firstResult.severity == Severity.error) {
        finalResult = firstResult.withSeverity(Severity.warning);
      } else if (failOn.contains(check.name) &&
          firstResult.severity == Severity.warning) {
        finalResult = firstResult.withSeverity(Severity.error);
      } else {
        finalResult = firstResult;
      }
      await writeInComment(github, finalResult);
      var severity = finalResult.severity.name.toUpperCase();
      print('\n\n$severity: $checkName done.\n\n');
    } else {
      print('Skipping $checkName, as the skip tag is present.');
    }
  }

  Future<HealthCheckResult> Function() checkFor(Check check) => switch (check) {
        Check.version => validateCheck,
        Check.license => licenseCheck,
        Check.changelog => changelogCheck,
        Check.coverage => coverageCheck,
        Check.breaking => breakingCheck,
        Check.donotsubmit => doNotSubmitCheck,
        Check.leaking => leakingCheck,
      };

  Future<HealthCheckResult> validateCheck() async {
    //TODO: Add Flutter support for PR health checks
    var results =
        await Firehose(directory, false, ignoredPackages).verify(github);

    var markdownTable = '''
| Package | Version | Status |
| :--- | ---: | :--- |
${results.describeAsMarkdown(withTag: false)}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
    ''';

    return HealthCheckResult(
      Check.version,
      results.severity,
      markdownTable,
    );
  }

  Future<HealthCheckResult> breakingCheck() async {
    final filesInPR = await github.listFilesForPR(directory, ignoredPackages);
    final changeForPackage = <Package, BreakingChange>{};
    for (var package in packagesContaining(filesInPR, ignoredPackages)) {
      print('Look for changes in $package with base $baseDirectory');
      var relativePath =
          path.relative(package.directory.path, from: directory.path);
      var baseRelativePath = path.relative(
          path.join(baseDirectory.path, relativePath),
          from: directory.path);
      var tempDirectory = Directory.systemTemp.createTempSync();
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
      Check.breaking,
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

  Future<HealthCheckResult> leakingCheck() async {
    final filesInPR = await github.listFilesForPR(directory, ignoredPackages);
    final leaksForPackage = <Package, List<String>>{};
    for (var package in packagesContaining(filesInPR, ignoredPackages)) {
      print('Look for leaks in $package');
      var relativePath =
          path.relative(package.directory.path, from: directory.path);
      var tempDirectory = Directory.systemTemp.createTempSync();
      var reportPath = path.join(tempDirectory.path, 'leaks.json');
      var runApiTool = Process.runSync(
        'dart',
        [
          ...['pub', 'global', 'run'],
          'dart_apitool:main',
          'extract',
          ...['--input', relativePath],
          ...['--output', reportPath],
          '--set-exit-on-missing-export',
        ],
        workingDirectory: directory.path,
      );
      print(runApiTool.stderr);
      print(runApiTool.stdout);

      var fullReportString = File(reportPath).readAsStringSync();
      var decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
      var leaks = decoded['missingEntryPoints'] as List<dynamic>;

      print('Leaking API:\n$leaks');
      if (leaks.isNotEmpty) {
        leaksForPackage[package] = leaks.cast();
      }
    }
    return HealthCheckResult(
      Check.leaking,
      leaksForPackage.values.any((leaks) => leaks.isNotEmpty)
          ? Severity.warning
          : Severity.success,
      '''
The following packages contain symbols visible in the public API, but not exported by the library. Export these symbols or remove them from your publicly visible API.

| Package | Leaking API members |
| :--- | :--- |
${leaksForPackage.entries.map((e) => '|${e.key.name}|${e.value.join('<br>')}|').join('\n')}
''',
    );
  }

  Future<HealthCheckResult> licenseCheck() async {
    var files = await github.listFilesForPR(directory, ignoredPackages);
    var allFilePaths = await getFilesWithoutLicenses(
      directory,
      [...ignoredFilesForLicense, ...ignoredPackages],
    );

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
      Check.license,
      changedFilesPaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> changelogCheck() async {
    var filePaths = await packagesWithoutChangelog(
      github,
      ignoredPackages,
      directory,
    );

    final markdownResult = '''
| Package | Changed Files |
| :--- | :--- |
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => e.filename).join('<br />')} |').join('\n')}

Changes to files need to be [accounted for](https://github.com/dart-lang/ecosystem/wiki/Changelog) in their respective changelogs.
''';

    return HealthCheckResult(
      Check.changelog,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> doNotSubmitCheck() async {
    final dns = 'DO_NOT${'_'}SUBMIT';
    // To avoid trying to read non-text files.
    const supportedExtensions = ['.dart', '.json', '.md', '.txt'];

    final body = await github.pullrequestBody();
    final files = await github.listFilesForPR(directory, ignoredPackages);
    print('Checking for DO_NOT${'_'}SUBMIT strings: $files');
    final filesWithDNS = files
        .where((file) =>
            ![FileStatus.removed, FileStatus.unchanged].contains(file.status))
        .where((file) =>
            supportedExtensions.contains(path.extension(file.filename)))
        .where((file) => File(file.pathInRepository)
            .readAsStringSync()
            .contains('DO_NOT${'_'}SUBMIT'))
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
      Check.donotsubmit,
      hasDNS ? Severity.error : Severity.success,
      hasDNS ? markdownResult : null,
    );
  }

  Future<HealthCheckResult> coverageCheck() async {
    var coverage = await Coverage(
      coverageweb,
      ignoredFilesForCoverage,
      ignoredPackages,
      directory,
      experiments,
    ).compareCoverages(github, directory);

    var markdownResult = '''
| File | Coverage |
| :--- | :--- |
${coverage.coveragePerFile.entries.map((e) => '|${e.key}| ${e.value.toMarkdown()} |').join('\n')}

This check for [test coverage](https://github.com/dart-lang/ecosystem/wiki/Test-Coverage) is informational (issues shown here will not fail the PR).
''';

    return HealthCheckResult(
      Check.coverage,
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

${isWorseThanInfo ? 'This check can be disabled by tagging the PR with `skip-${result.check.name}-check`' : ''}
</details>

''';
      markdownSummary = '${check.tag} ${result.severity.emoji}\n\n$s';
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

  List<Package> packagesContaining(
    List<GitFile> filesInPR,
    List<Glob> ignoredPackages,
  ) {
    var files = filesInPR.where((element) => element.status.isRelevant);
    return Repository(directory)
        .locatePackages(ignoredPackages)
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
  final Check check;
  final Severity severity;
  final String? markdown;

  HealthCheckResult(this.check, this.severity, this.markdown);

  HealthCheckResult withSeverity(Severity severity) => HealthCheckResult(
        check,
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
