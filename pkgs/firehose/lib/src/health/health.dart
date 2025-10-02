// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../../firehose.dart';
import '../utils.dart';
import 'changelog.dart';
import 'coverage.dart';
import 'license.dart';

const apiToolHash = '8654b768219d5707cdade72fdd80cf915e9d46b8';

enum Check {
  license('License Headers', 'license'),
  changelog('Changelog Entry', 'changelog'),
  coverage('Coverage', 'coverage'),
  breaking('Breaking changes', 'breaking'),
  leaking('API leaks', 'leaking'),
  donotsubmit('Do Not Submit', 'do-not-submit');

  final String tag;

  final String displayName;

  const Check(this.tag, this.displayName);
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
    Map<Check, List<String>> ignoredFor,
    this.experiments,
    this.github,
    List<String> flutterPackages, {
    Directory? base,
    String? comment,
    this.log = printLogger,
    required this.healthYamlNames,
  })  : ignoredPackages = toGlobs(ignoredPackages),
        flutterPackageGlobs = toGlobs(flutterPackages),
        ignoredFor =
            ignoredFor.map((c, globString) => MapEntry(c, toGlobs(globString))),
        baseDirectory = base ?? Directory('../base_repo'),
        commentPath = comment ??
            path.join(
              directory.path,
              'output',
              'comment-${check.displayName}.md',
            ) {
    flutterExecutable =
        (Process.runSync('which', ['-a', 'flutter']).stdout as String)
            .split('\n')
            .where((element) => element.isNotEmpty)
            .firstOrNull;

    var dartExecutables =
        (Process.runSync('which', ['-a', 'dart']).stdout as String)
            .split('\n')
            .where((element) => element.isNotEmpty);
    dartExecutable = dartExecutables
        .sortedBy((path) => path.contains('flutter').toString())
        .first;
  }

  static List<Glob> toGlobs(List<String> ignoredPackages) =>
      ignoredPackages.map((pattern) => Glob(pattern, recursive: true)).toList();

  final GithubApi github;

  final Check check;
  final List<String> warnOn;
  final List<String> failOn;
  final bool coverageweb;
  final List<Glob> ignoredPackages;
  final Map<Check, List<Glob>> ignoredFor;
  final List<Glob> flutterPackageGlobs;
  final Directory baseDirectory;
  final List<String> experiments;
  final Logger log;
  final Set<String> healthYamlNames;

  late final String dartExecutable;
  late final String? flutterExecutable;

  List<Glob> get ignored => [...ignoredPackages, ...ignoredFor[check] ?? []];

  String executable(bool isFlutter) =>
      isFlutter ? flutterExecutable ?? dartExecutable : dartExecutable;

  Future<void> healthCheck() async {
    // Do basic validation of our expected env var.
    if (!expectEnv(github.repoSlug?.fullName, 'GITHUB_REPOSITORY')) return;
    if (!expectEnv(github.issueNumber?.toString(), 'ISSUE_NUMBER')) return;
    if (!expectEnv(github.sha, 'GITHUB_SHA')) return;

    var checkName = check.displayName;
    log('Start health check for the check $checkName with');
    log(' warnOn: $warnOn');
    log(' failOn: $failOn');
    log(' coverageweb: $coverageweb');
    log(' flutterPackages: $flutterPackageGlobs');
    log(' ignoredPackages: $ignoredPackages');
    log(' ignoredFor: $ignoredFor');
    log(' baseDirectory: $baseDirectory');
    log(' experiments: $experiments');
    log(' healthYamlNames: $healthYamlNames');
    log('Checking for $checkName');
    if (!github.prLabels.contains('skip-$checkName-check')) {
      final firstResult = await checkFor(check)();
      final HealthCheckResult finalResult;
      if (warnOn.contains(check.displayName) &&
          firstResult.severity == Severity.error) {
        finalResult = firstResult.withSeverity(Severity.warning);
      } else if (failOn.contains(check.displayName) &&
          firstResult.severity == Severity.warning) {
        finalResult = firstResult.withSeverity(Severity.error);
      } else {
        finalResult = firstResult;
      }
      await writeInComment(github, finalResult);
      var severity = finalResult.severity.name.toUpperCase();
      log('\n\n$severity: $checkName done.\n\n');
    } else {
      log('Skipping $checkName, as the skip tag is present.');
    }
  }

  Future<HealthCheckResult> Function() checkFor(Check check) => switch (check) {
        Check.license => licenseCheck,
        Check.changelog => changelogCheck,
        Check.coverage => coverageCheck,
        Check.breaking => breakingCheck,
        Check.donotsubmit => doNotSubmitCheck,
        Check.leaking => leakingCheck,
      };

  Future<HealthCheckResult> breakingCheck() async {
    final filesInPR = await listFilesInPRorAll();
    final changeForPackage = <Package, BreakingChange>{};

    final flutterPackages =
        packagesContaining(filesInPR, only: flutterPackageGlobs);
    log('This list of Flutter packages is $flutterPackages');
    for (var package in packagesContaining(filesInPR, ignore: ignored)) {
      log('Look for changes in $package');
      final absolutePath = package.directory.absolute.path;
      var tempDirectory = Directory.systemTemp.createTempSync();
      var reportPath = path.join(tempDirectory.path, 'report.json');

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'activate',
          ...['-sgit', 'https://github.com/bmw-tech/dart_apitool.git'],
          ...['--git-ref', apiToolHash],
        ],
        logStdout: false,
      );

      runDashProcess(
        flutterPackages,
        package,
        [
          ...['pub', 'global', 'run'],
          'dart_apitool:main',
          'diff',
          '--no-check-sdk-version',
          ...['--old', getCurrentVersionOfPackage(package)],
          ...['--new', absolutePath],
          ...['--report-format', 'json'],
          ...['--report-file-path', reportPath],
        ],
      );

      var fullReportString = File(reportPath).readAsStringSync();
      var decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
      var report = decoded['report'] as Map<String, dynamic>;

      var formattedChanges = const JsonEncoder.withIndent('  ').convert(report);
      log('Breaking change report:\n$formattedChanges');

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

  String getCurrentVersionOfPackage(Package package) => 'pub://${package.name}';

  ProcessResult runDashProcess(
    List<Package> flutterPackages,
    Package package,
    List<String> arguments, {
    bool logStdout = true,
  }) {
    var exec = executable(flutterPackages.any((p) => p.name == package.name));
    log('Running `$exec ${arguments.join(' ')}` in ${directory.path}');
    var runApiTool = Process.runSync(
      exec,
      arguments,
      workingDirectory: directory.path,
    );
    final out = (runApiTool.stdout as String).trimRight();
    if (logStdout && out.isNotEmpty) {
      print(out);
    }
    final err = (runApiTool.stderr as String).trimRight();
    if (err.isNotEmpty) {
      print(err);
    }
    return runApiTool;
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
    var filesInPR = await listFilesInPRorAll();
    final leaksInPackages = <(Package, Leak)>[];

    final flutterPackages =
        packagesContaining(filesInPR, only: flutterPackageGlobs);
    log('This list of Flutter packages is $flutterPackages');

    for (var package in packagesContaining(filesInPR)) {
      log('');
      log('--- ${package.name} ---');
      log('Look for leaks in ${package.name}');
      final absolutePath = package.directory.absolute.path;
      var tempDirectory = Directory.systemTemp.createTempSync();
      var reportPath = path.join(tempDirectory.path, 'leaks.json');

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'activate',
          ...['-sgit', 'https://github.com/bmw-tech/dart_apitool.git'],
          ...['--git-ref', apiToolHash],
        ],
        logStdout: false,
      );

      var arguments = [
        ...['pub', 'global', 'run'],
        'dart_apitool:main',
        'extract',
        ...['--input', absolutePath],
        ...['--output', reportPath],
      ];
      var runApiTool = runDashProcess(
        flutterPackages,
        package,
        arguments,
      );

      log('');

      if (runApiTool.exitCode == 0) {
        var fullReportString = await File(reportPath).readAsString();
        var decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
        var leaks = decoded['missingEntryPoints'] as List<dynamic>;

        if (leaks.isNotEmpty) {
          leaksInPackages.addAll(leaks.map(
            (leakJson) =>
                (package, Leak.fromJson(leakJson as Map<String, dynamic>)),
          ));

          final desc = leaks.map((item) => '$item').join(', ');
          log('Leaked symbols found: $desc.');

          log('');

          final report = const JsonEncoder.withIndent('  ').convert(decoded);
          log(report);
        } else {
          log('No leaks found.');
        }

        log('');
      } else {
        throw ProcessException(
          executable(flutterPackages.contains(package)),
          arguments,
          'Api tool finished with exit code ${runApiTool.exitCode}',
        );
      }
    }
    return HealthCheckResult(
      Check.leaking,
      leaksInPackages.isNotEmpty ? Severity.warning : Severity.success,
      '''
The following packages contain symbols visible in the public API, but not exported by the library. Export these symbols or remove them from your publicly visible API.

| Package | Leaked API symbol | Leaking sources |
| :--- | :--- | :--- |
${leaksInPackages.map((e) => '|${e.$1.name}|${e.$2.name}|${e.$2.usages.join('<br>')}|').join('\n')}
''',
    );
  }

  Future<HealthCheckResult> licenseCheck() async {
    var files = await listFilesInPRorAll();
    var allFilePaths = await getFilesWithoutLicenses(directory, ignored);

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

  bool healthYamlChanged(List<GitFile> files) => files
      .where((file) =>
          [FileStatus.added, FileStatus.modified].contains(file.status))
      .any((file) => healthYamlNames.contains(path.basename(file.filename)));

  Future<HealthCheckResult> changelogCheck() async {
    var filePaths = await packagesWithoutChangelog(
      github,
      ignored,
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
    var files = await listFilesInPRorAll();
    log('Checking for DO_NOT${'_'}SUBMIT strings: $files');
    final filesWithDNS = files
        .where((file) =>
            ![FileStatus.removed, FileStatus.unchanged].contains(file.status))
        .where((file) =>
            supportedExtensions.contains(path.extension(file.filename)))
        .where((file) => File(file.pathInRepository)
            .readAsStringSync()
            .contains('DO_NOT${'_'}SUBMIT'))
        .toList();
    log('Found files with $dns: $filesWithDNS');

    final bodyContainsDNS = body.contains(dns);
    log('The body contains a $dns string: $bodyContainsDNS');
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

  Future<List<GitFile>> listFilesInPRorAll() async {
    final files = await github.listFilesForPR(directory, ignored);
    return healthYamlChanged(files) ? await _getAllFiles() : files;
  }

  Future<List<GitFile>> _getAllFiles() async => await directory
      .list(recursive: true)
      .where((entity) => entity is File)
      .map((file) => path.relative(file.path, from: directory.path))
      .where((file) => ignored.none((glob) => glob.matches(file)))
      .map((file) => GitFile(file, FileStatus.added, directory))
      .toList();

  Future<HealthCheckResult> coverageCheck() async {
    var coverage = Coverage(
      coverageweb,
      ignored,
      directory,
      experiments,
      dartExecutable,
    );

    var files = await listFilesInPRorAll();
    var coverageResult = coverage.compareCoveragesFor(files, baseDirectory);

    var markdownResult = '''
| File | Coverage |
| :--- | :--- |
${coverageResult.coveragePerFile.entries.map((e) => '|${e.key}| ${e.value.toMarkdown()} |').join('\n')}

This check for [test coverage](https://github.com/dart-lang/ecosystem/wiki/Test-Coverage) is informational (issues shown here will not fail the PR).
''';

    return HealthCheckResult(
      Check.coverage,
      Severity.values[coverageResult.coveragePerFile.values
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
      var expand = switch (result.severity) {
        Severity.success || Severity.info || Severity.warning => false,
        Severity.error => true,
      };

      markdownSummary = '''
<details${expand ? ' open' : ''}>
<summary>
<strong>${check.tag}</strong> ${result.severity.emoji}
</summary>

$markdown

This check can be disabled by tagging the PR with `skip-${result.check.displayName}-check`.
</details>

''';
    } else {
      markdownSummary = '';
    }

    github.appendStepSummary(markdownSummary);

    var commentFile = File(commentPath);
    log('Saving comment markdown to file ${commentFile.path}');
    await commentFile.create(recursive: true);
    await commentFile.writeAsString(markdownSummary);

    if (result.severity == Severity.error && exitCode == 0) {
      exitCode = 1;
    }
  }

  List<Package> packagesContaining(
    List<GitFile> filesInPR, {
    List<Glob>? ignore,
    List<Glob>? only,
  }) {
    var files = filesInPR.where((element) => element.status.isRelevant);
    return Repository(directory)
        .locatePackages(ignore: ignore, only: only)
        .where((package) => files.any((file) =>
            path.isWithin(package.directory.path, file.pathInRepository)))
        .toList();
  }
}

class Leak {
  /// The type of the leak, e.g., 'interface'.
  final String type;

  /// A list of strings representing where the leak is used.
  final List<String> usages;

  final String name;

  Leak._({
    required this.type,
    required this.usages,
    required this.name,
  });

  factory Leak.fromJson(Map<String, dynamic> json) {
    return Leak._(
      type: json['type'] as String,
      usages: (json['usages'] as List<dynamic>).cast<String>(),
      name: json['name'] as String,
    );
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
