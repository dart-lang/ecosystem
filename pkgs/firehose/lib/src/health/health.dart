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

/// To allow easier searching for the package name
// ignore: constant_identifier_names
const dart_apitoolHash = '6d710709e5d51bab52ecd911c84a3264e5277a69';

/// To allow easier searching for the package name
// ignore: constant_identifier_names
const dependency_validatorHash = 'f0a7e4ba6489d42f81a1352159c2f049c9741d4e';

enum Check {
  license('License Headers', 'license'),
  changelog('Changelog Entry', 'changelog'),
  coverage('Coverage', 'coverage'),
  breaking('Breaking changes', 'breaking'),
  leaking('API leaks', 'leaking'),
  donotsubmit('Do Not Submit', 'do-not-submit'),
  unuseddependencies('Unused Dependencies', 'unused-dependencies');

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
    String? licenseTestString,
    String? license,
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
            ),
        licenseOptions = LicenseOptions(
          license: license,
          licenseTestString: licenseTestString,
        ) {
    flutterExecutable =
        (Process.runSync('which', ['-a', 'flutter']).stdout as String)
            .split('\n')
            .where((element) => element.isNotEmpty)
            .firstOrNull;

    final dartExecutables =
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
  final LicenseOptions licenseOptions;

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

    final checkName = check.displayName;
    log('Start health check for the check $checkName with');
    log(' warnOn: $warnOn');
    log(' failOn: $failOn');
    log(' coverageweb: $coverageweb');
    log(' flutterPackages: $flutterPackageGlobs');
    log(' ignoredPackages: $ignoredPackages');
    log(' ignoredFor: ${ignoredFor[check]}');
    log(' baseDirectory: $baseDirectory');
    log(' experiments: $experiments');
    log(' healthYamlNames: $healthYamlNames');
    log('Checking for $checkName');
    final prLabels = github.prLabels;
    print('PR Labels are $prLabels');
    if (!prLabels.contains('skip-$checkName-check')) {
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
      final severity = finalResult.severity.name.toUpperCase();
      log('\n\n$severity: $checkName done.\n\n');
    } else {
      log('Skipping $checkName, as the skip tag is present in $prLabels.');
    }
  }

  Future<HealthCheckResult> Function() checkFor(Check check) => switch (check) {
        Check.license => licenseCheck,
        Check.changelog => changelogCheck,
        Check.coverage => coverageCheck,
        Check.breaking => breakingCheck,
        Check.donotsubmit => doNotSubmitCheck,
        Check.leaking => leakingCheck,
        Check.unuseddependencies => unusedDependenciesCheck,
      };
  Future<HealthCheckResult> unusedDependenciesCheck() async {
    final filesInPR = await listFilesInPRorAll();
    final flutterPackages =
        packagesContaining(filesInPR, only: flutterPackageGlobs);
    final packages = packagesContaining(filesInPR, ignore: ignored);

    final results = <String>[];
    var hasError = false;

    for (final package in packages) {
      log('Checking dependencies for ${package.name}');

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'get',
        ],
        workingDirectoryOverride: package.directory,
        logStdout: false,
      );

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'activate',
          ...['-sgit', 'https://github.com/Workiva/dependency_validator.git'],
          ...['--git-ref', dependency_validatorHash],
        ],
        logStdout: false,
      );

      final (result, out, err) = runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'run',
          'dependency_validator',
        ],
        workingDirectoryOverride: package.directory,
        logStdout: false,
      );

      if (result.exitCode != 0) {
        hasError = true;
        final output = (err.trim().isNotEmpty ? err.trim() : out.trim())
            .replaceAll('\n', '<br>');
        results.add('''
| ${package.name} | <details><summary>:exclamation: Show Issues</summary><pre>$output</pre></details> |''');
      } else {
        results.add('''
| ${package.name} | :heavy_check_mark: All dependencies utilized correctly. |''');
      }
    }

    final markdownResult = '''
| Package | Status |
| :--- | :--- |
${results.isEmpty ? '| _None_ | No packages found to check. |' : results.join('\n')}

For details on how to fix these, see [dependency_validator](https://pub.dev/packages/dependency_validator).
''';

    return HealthCheckResult(
      Check.unuseddependencies,
      hasError ? Severity.error : Severity.success,
      markdownResult,
    );
  }

  Future<HealthCheckResult> breakingCheck() async {
    final filesInPR = await listFilesInPRorAll();
    final changeForPackage = <Package, BreakingChange>{};

    final flutterPackages =
        packagesContaining(filesInPR, only: flutterPackageGlobs);
    log('This list of Flutter packages is $flutterPackages');
    for (final package in packagesContaining(filesInPR, ignore: ignored)) {
      log('Look for changes in $package');
      final absolutePath = package.directory.absolute.path;
      final tempDirectory = Directory.systemTemp.createTempSync();
      final reportPath = path.join(tempDirectory.path, 'report.json');

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'activate',
          ...['-sgit', 'https://github.com/bmw-tech/dart_apitool.git'],
          ...['--git-ref', dart_apitoolHash],
        ],
        logStdout: false,
      );

      final (_, _, err) = runDashProcess(
        flutterPackages,
        package,
        [
          ...['pub', 'global', 'run'],
          'dart_apitool:main',
          'diff',
          '--no-check-sdk-version',
          '--no-ignore-prerelease',
          ...['--old', getCurrentVersionOfPackage(package)],
          ...['--new', absolutePath],
          ...['--report-format', 'json'],
          ...['--report-file-path', reportPath],
        ],
      );
      final file = File(reportPath);
      if (file.existsSync()) {
        final fullReportString = file.readAsStringSync();
        final decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
        final report = decoded['report'] as Map<String, dynamic>;
        final formattedChanges =
            const JsonEncoder.withIndent('  ').convert(decoded);
        log('Breaking change report:\n$formattedChanges');

        final versionMap = decoded['version'] as Map<String, dynamic>;
        final neededVersion = versionMap['needed'] as String?;
        changeForPackage[package] = BreakingChange(
          level: _breakingLevel(report),
          oldVersion: Version.parse(versionMap['old'] as String),
          newVersion: Version.parse(versionMap['new'] as String),
          neededVersion:
              neededVersion == null ? null : Version.parse(neededVersion),
          versionIsFine: versionMap['success'] as bool,
          explanation: versionMap['explanation'].toString(),
        );
      } else {
        log('Report was not created for $package at $reportPath');
        changeForPackage[package] = BreakingChange(
          level: BreakingLevel.breaking,
          oldVersion: Version(0, 0, 0),
          newVersion: Version(0, 0, 0),
          neededVersion: Version(0, 0, 0),
          versionIsFine: false,
          explanation: 'Report was not created for $package. Error: $err',
        );
      }
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

  (ProcessResult, String, String) runDashProcess(
    List<Package> flutterPackages,
    Package package,
    List<String> arguments, {
    bool logStdout = true,
    Directory? workingDirectoryOverride,
  }) {
    final workingDirectory = workingDirectoryOverride ?? directory;
    final exec = executable(flutterPackages.any((p) => p.name == package.name));
    log('Running `$exec ${arguments.join(' ')}` in ${workingDirectory.path}');
    final runApiTool = Process.runSync(
      exec,
      arguments,
      workingDirectory: workingDirectory.path,
    );
    final out = (runApiTool.stdout as String).trimRight();
    if (logStdout && out.isNotEmpty) {
      print(out);
    }
    final err = (runApiTool.stderr as String).trimRight();
    if (err.isNotEmpty) {
      print(err);
    }
    return (runApiTool, out, err);
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
    final filesInPR = await listFilesInPRorAll();
    final leaksInPackages = <(Package, Leak)>[];

    final flutterPackages =
        packagesContaining(filesInPR, only: flutterPackageGlobs);
    log('This list of Flutter packages is $flutterPackages');

    for (final package in packagesContaining(filesInPR)) {
      log('');
      log('--- ${package.name} ---');
      log('Look for leaks in ${package.name}');
      final absolutePath = package.directory.absolute.path;
      final tempDirectory = Directory.systemTemp.createTempSync();
      final reportPath = path.join(tempDirectory.path, 'leaks.json');

      runDashProcess(
        flutterPackages,
        package,
        [
          'pub',
          'global',
          'activate',
          ...['-sgit', 'https://github.com/bmw-tech/dart_apitool.git'],
          ...['--git-ref', dart_apitoolHash],
        ],
        logStdout: false,
      );

      final arguments = [
        ...['pub', 'global', 'run'],
        'dart_apitool:main',
        'extract',
        ...['--input', absolutePath],
        ...['--output', reportPath],
      ];
      final (runApiTool, _, err) = runDashProcess(
        flutterPackages,
        package,
        arguments,
      );

      log('');

      if (runApiTool.exitCode == 0) {
        final fullReportString = await File(reportPath).readAsString();
        final decoded = jsonDecode(fullReportString) as Map<String, dynamic>;
        final leaks = decoded['missingEntryPoints'] as List<dynamic>;

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
          'Api tool finished with exit code ${runApiTool.exitCode}: $err',
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
    final files = await listFilesInPRorAll();
    final allFilePaths = await getFilesWithoutLicenses(
        directory, ignored, licenseOptions.licenseTestString);

    final groupedPaths = allFilePaths
        .groupListsBy((filePath) => files.any((f) => f.filename == filePath));

    final unchangedFilesPaths = groupedPaths[false] ?? [];
    final unchangedMarkdown = '''
<details>
<summary>
Unrelated files missing license headers
</summary>

| Files |
| :--- |
${unchangedFilesPaths.map((e) => '|$e|').join('\n')}
</details>
''';

    final changedFilesPaths = groupedPaths[true] ?? [];
    final markdownResult = '''
```
${licenseOptions.license}
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
    final filePaths = await packagesWithoutChangelog(
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
    final files = await listFilesInPRorAll();
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
    final coverage = Coverage(
      coverageweb,
      ignored,
      directory,
      experiments,
      dartExecutable,
    );

    final files = await listFilesInPRorAll();
    final coverageResult = coverage.compareCoveragesFor(files, baseDirectory);

    final markdownResult = '''
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
      final markdown = result.markdown;
      final expand = switch (result.severity) {
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

    final commentFile = File(commentPath);
    log('Saving comment markdown to file ${commentFile.path}');
    await commentFile.create(recursive: true);
    await commentFile.writeAsString(markdownSummary, mode: FileMode.append);

    if (result.severity == Severity.error && exitCode == 0) {
      exitCode = 1;
    }
  }

  List<Package> packagesContaining(
    List<GitFile> filesInPR, {
    List<Glob>? ignore,
    List<Glob>? only,
  }) {
    final files = filesInPR.where((element) => element.status.isRelevant);
    return Repository(directory)
        .locatePackages(ignore: ignore, only: only)
        .where((package) => files.any((file) =>
            path.isWithin(package.directory.path, file.pathInRepository)))
        .toList();
  }
}

class LicenseOptions {
  static const _defaultLicenseTestString = '// Copyright (c)';

  static const _defaultLicense = '''
// Copyright (c) %YEAR%, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.''';

  final String _license;

  String get license =>
      _license.replaceAll('%YEAR%', DateTime.now().year.toString());

  final String licenseTestString;

  LicenseOptions({
    String? license,
    String? licenseTestString,
  })  : _license = license ?? _defaultLicense,
        licenseTestString = licenseTestString ?? _defaultLicenseTestString;
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

  factory Leak.fromJson(Map<String, dynamic> json) => Leak._(
        type: json['type'] as String,
        usages: (json['usages'] as List<dynamic>).cast<String>(),
        name: json['name'] as String,
      );
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
  final Version? neededVersion;
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

  String toMarkdownRow() {
    String needed;
    if (versionIsFine) {
      needed = neededVersion.toString();
    } else {
      if (neededVersion != null) {
        needed = '**$neededVersion** <br> $explanation';
      } else {
        needed = explanation;
      }
    }
    return [
      level.name,
      oldVersion.toString(),
      newVersion.toString(),
      needed,
      versionIsFine ? ':heavy_check_mark:' : ':warning:'
    ].map((e) => e.toString()).join('|');
  }
}
