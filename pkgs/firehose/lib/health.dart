// ignore_for_file: public_member_api_docs, sort_constructors_first
// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:io';
import 'dart:math';

import 'package:firehose/firehose.dart';
import 'package:firehose/src/repo.dart';
import 'package:path/path.dart' as path;

import 'src/github.dart';
import 'src/utils.dart';

const String _botSuffix = '[bot]';

const String _githubActionsUser = 'github-actions[bot]';

const String _publishBotTag2 = '### Package publish validation';

const String _licenseBotTag = '### License Headers';

const String _changelogBotTag = '### Changelog Entry';

const String _coverageBotTag = '### Coverage';

const String _prHealthTag = '## PR Health';

class Health {
  final Directory directory;

  Health(this.directory);

  Future<void> healthCheck(List args) async {
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
        coverageCheck,
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
${results.describeAsMarkdown(false)}

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
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
```
$license
```

| Files |
| :--- |
${filePaths.isNotEmpty ? filePaths.map((e) => '|$e|').join('\n') : '| _no missing headers_  |'}

All source files should start with a [license header](https://github.com/dart-lang/ecosystem/wiki/License-Header).
''';

    return HealthCheckResult(
      _licenseBotTag,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> changelogCheck(Github github) async {
    var filePaths = await _packagesWithoutChangelog(github);

    final markdownResult = '''
| Package | Changed Files |
| :--- | :--- |
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => e.relativePath).join('<br />')} |').join('\n')}

Changes to files need to be [accounted for](https://github.com/dart-lang/ecosystem/wiki/Changelog) in their respective changelogs.
''';

    return HealthCheckResult(
      _changelogBotTag,
      filePaths.isNotEmpty ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<Map<Package, List<GitFile>>> _packagesWithoutChangelog(
      Github github) async {
    final repo = Repository();
    final packages = repo.locatePackages();

    final files = await github.listFilesForPR();
    print('Collecting packages without changed changelogs:');
    final packagesWithoutChangedChangelog = packages.where((package) {
      var changelogPath = package.changelog.file.path;
      var changelog =
          path.relative(changelogPath, from: Directory.current.path);
      return !files.map((e) => e.relativePath).contains(changelog);
    }).toList();
    print('Done, found ${packagesWithoutChangedChangelog.length} packages.');

    print('Collecting files without license headers in those packages:');
    var packagesWithChanges = <Package, List<GitFile>>{};
    for (final file in files) {
      for (final package in packagesWithoutChangedChangelog) {
        if (fileNeedsEntryInChangelog(package, file.relativePath)) {
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

  Future<HealthCheckResult> coverageCheck(Github github) async {
    final files = await github.listFilesForPR();
    var coverage = await compareCoverages(files);

    var markdownResult = '''
| File | Coverage change |
| :--- | :--- |
${coverage.coveragePerFile.entries.map((e) => '|${e.key}| ${e.value.toMarkdown()} |').join('\n')}

Try to increase coverage.
''';

    return HealthCheckResult(
      _coverageBotTag,
      Severity.values[coverage.coveragePerFile.values
          .map((change) => change.severity.index)
          .reduce(max)],
      markdownResult,
    );
  }

  bool fileNeedsEntryInChangelog(Package package, String file) {
    final directoryPath = package.directory.path;
    final directory =
        path.relative(directoryPath, from: Directory.current.path);
    final isInPackage = path.isWithin(directory, file);
    final isInLib = path.isWithin(path.join(directory, 'lib'), file);
    final isInBin = path.isWithin(path.join(directory, 'bin'), file);
    final isPubspec = file.endsWith('pubspec.yaml');
    final isReadme = file.endsWith('README.md');
    return isInPackage && (isInLib || isInBin || isPubspec || isReadme);
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

  Future<void> writeInComment(
    Github github,
    List<HealthCheckResult> results,
  ) async {
    var commentText = results.map((e) {
      var markdown = e.markdown;
      var s = '''
<details${e.severity.index >= Severity.warning.index ? ' open' : ''}>
<summary>
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

  Future<CoverageResult> compareCoverages(List<GitFile> files) async {
    var coverageResult = CoverageResult({});
    for (var package in Repository().locatePackages()) {
      var currentPath = Directory.current.path;
      var relative = path.join(Directory.current.path, '.coverage_base');
      var oldPackageDirectory = path.join(
        relative,
        path.relative(package.directory.path, from: currentPath),
      );
      var oldCoverages = parseLCOV(
        path.join(oldPackageDirectory, 'coverage/lcov.info'),
        relativeTo: relative,
      );
      var newCoverages = parseLCOV(
        path.join(package.directory.path, 'coverage/lcov.info'),
        relativeTo: Directory.current.path,
      );
      print('Old coverage: ${oldCoverages.coveragePerFile}');
      print('New coverage: ${newCoverages.coveragePerFile}');
      for (var file in files
          .map((file) => file.relativePath)
          .where((file) => path.extension(file) == '.dart')
          .where((file) => path.isWithin(package.directory.path, file))) {
        var oldCoverage = oldCoverages[file];
        var newCoverage = newCoverages[file];
        Change change;
        if (oldCoverage == null && newCoverage == null) {
          change = Change(existedBefore: false, existsNow: false);
        } else if (oldCoverage == null) {
          change = Change(
            value: newCoverage!.value!,
            existedBefore: false,
            existsNow: true,
          );
        } else {
          change = Change(
            value: ((newCoverage?.value ?? 0) - oldCoverage.value!) /
                oldCoverage.value!.abs(),
          );
        }
        coverageResult[file] = change;
      }
    }
    return coverageResult;
  }

  CoverageResult parseLCOV(
    String lcovPath, {
    required String relativeTo,
  }) {
    var file = File(lcovPath);
    List<String> lines;
    if (file.existsSync()) {
      lines = file.readAsLinesSync();
    } else {
      print('LCOV file not found at $lcovPath.');
      return CoverageResult({});
    }
    var coveragePerFile = <String, Change>{};
    String? fileName;
    int? numberLines;
    int? coveredLines;
    for (var line in lines) {
      if (line.startsWith('SF:')) {
        fileName = line.substring('SF:'.length);
      } else if (line.startsWith('LF:')) {
        numberLines = int.parse(line.substring('LF:'.length));
      } else if (line.startsWith('LH:')) {
        coveredLines = int.parse(line.substring('LH:'.length));
      } else if (line.startsWith('end_of_record')) {
        var change = Change(
          value: numberLines != null ? (coveredLines ?? 0) / numberLines : 0,
          existsNow: numberLines != null,
        );
        coveragePerFile[path.relative(fileName!, from: relativeTo)] = change;
      }
    }
    print('Found coverage for ${coveragePerFile.length} files.');
    return CoverageResult(coveragePerFile);
  }
}

class HealthCheckResult {
  final String tag;
  final Severity severity;
  final String markdown;

  HealthCheckResult(this.tag, this.severity, this.markdown);
}

class CoverageResult {
  final Map<String, Change> coveragePerFile;

  CoverageResult(this.coveragePerFile);

  CoverageResult operator +(CoverageResult other) {
    return CoverageResult({...coveragePerFile, ...other.coveragePerFile});
  }

  Change? operator [](String s) => coveragePerFile[s];
  void operator []=(String s, Change d) => coveragePerFile[s] = d;
}

class Change {
  final double? value;
  final bool existedBefore;
  final bool existsNow;

  Change({this.value, this.existedBefore = true, this.existsNow = true});

  Severity get severity {
    if (existedBefore) {
      return value! < 0 ? Severity.warning : Severity.success;
    } else if (existsNow && !existedBefore) {
      return Severity.success;
    } else if (!existsNow && !existedBefore) {
      return Severity.info;
    } else {
      return Severity.error;
    }
  }

  String toMarkdown() {
    if (existedBefore || existsNow) {
      var valueAsPercentage = '${(value! * 100).abs().toStringAsFixed(1)} %';
      if (existedBefore) {
        if (value! > 0) {
          return ':green_heart: Increased by $valueAsPercentage';
        } else {
          return ':broken_heart: Decreased by $valueAsPercentage';
        }
      } else {
        if (value! > 0) {
          return ':green_heart: Total coverage $valueAsPercentage';
        } else {
          // As the file did not exist before, there cannot be coverage...
          return ':broken_heart: No coverage for this file';
        }
      }
    } else {
      return ':broken_heart: No coverage for this file';
    }
  }

  @override
  bool operator ==(covariant Change other) {
    if (identical(this, other)) return true;

    return other.value == value &&
        other.existedBefore == existedBefore &&
        other.existsNow == existsNow;
  }

  @override
  int get hashCode =>
      value.hashCode ^ existedBefore.hashCode ^ existsNow.hashCode;
}
