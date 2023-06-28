// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: always_declare_return_types

import 'dart:io';

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
${filePaths.entries.map((e) => '| package:${e.key.name} | ${e.value.map((e) => path.relative(e, from: Directory.current.path)).join('<br />')} |').join('\n')}

Changes to files need to be [accounted for](https://github.com/dart-lang/ecosystem/wiki/Changelog) in their respective changelogs.
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
<details${e.severity == Severity.error ? ' open' : ''}>
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
}

class HealthCheckResult {
  final String tag;
  final Severity severity;
  final String markdown;

  HealthCheckResult(this.tag, this.severity, this.markdown);
}
