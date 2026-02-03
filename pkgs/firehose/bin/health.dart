// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:firehose/src/local_github_api.dart';

void main(List<String> arguments) async {
  final checkTypes = Check.values.map((c) => c.displayName);
  final argParser = ArgParser()
    ..addMultiOption(
      'check',
      allowed: checkTypes,
      help: 'Check PR health.',
    )
    ..addMultiOption(
      'ignore_packages',
      defaultsTo: [],
      help: 'Which packages to ignore.',
    )
    ..addMultiOption(
      'warn_on',
      allowed: checkTypes,
      help: 'Which checks to display warnings on',
    )
    ..addMultiOption(
      'fail_on',
      allowed: checkTypes,
      help: 'Which checks should lead to workflow failure',
    )
    ..addMultiOption(
      'experiments',
      help: 'Which experiments should be enabled for Dart',
    )
    ..addFlag(
      'coverage_web',
      help: 'Whether to run web tests for coverage',
    )
    ..addMultiOption(
      'flutter_packages',
      defaultsTo: [],
      help: 'The Flutter packages in this repo',
    )
    ..addOption(
      'health_yaml_name',
      help: 'The name of the workflow file containing the health checks, '
          'to know to rerun all checks if that file is changed.',
    )
    ..addOption(
      'comment',
      help: 'The name of the file to write the resulting comment to.',
    )
    ..addFlag('local', help: 'Run locally', defaultsTo: true)
    ..addOption(
      'license',
      help: 'The license string to insert if missing.'
          ' %YEAR% will be replaced with the current year',
    )
    ..addOption(
      'license_test_string',
      help:
          'A file containing this string will be considered having a license.',
    );

  for (var check in Check.values) {
    argParser.addMultiOption(
      'ignore_${check.name}',
      defaultsTo: [],
      help: 'Which files to ignore for the ${check.displayName} check.',
    );
  }
  final parsedArgs = argParser.parse(arguments);
  final checkStrings = parsedArgs.multiOption('check');
  final checks = checkStrings.map(
      (checkStr) => Check.values.firstWhere((c) => c.displayName == checkStr));
  final warnOn = parsedArgs.multiOption('warn_on');
  final failOn = parsedArgs.multiOption('fail_on');
  final flutterPackages = parsedArgs.listNonEmpty('flutter_packages');
  final ignorePackages = parsedArgs.listNonEmpty('ignore_packages');
  final ignoredFor = Map.fromEntries(Check.values
      .map((c) => MapEntry(c, parsedArgs.listNonEmpty('ignore_${c.name}'))));
  final experiments = parsedArgs.listNonEmpty('experiments');
  final coverageWeb = parsedArgs.flag('coverage_web');
  final healthYamlName = parsedArgs.option('health_yaml_name');
  final healthYamlNames = healthYamlName != null && healthYamlName.isNotEmpty
      ? {healthYamlName}
      : {'health.yaml', 'health.yml'};

  final gitStdOut =
      Process.runSync('git', ['rev-parse', '--abbrev-ref', 'origin/HEAD'])
          .stdout as String;
  final mainBranchName =
      const LineSplitter().convert(gitStdOut).first.substring('origin/'.length);

  final license = nullIfEmpty(parsedArgs.option('license'));
  final licenseTestString =
      nullIfEmpty(parsedArgs.option('license_test_string'));

  if (warnOn.toSet().intersection(failOn.toSet()).isNotEmpty) {
    throw ArgumentError('The checks for which warnings are displayed and the '
        'checks which lead to failure must be disjoint.');
  }
  final isLocal = parsedArgs.flag('local');
  final GithubApi githubApi;
  if (isLocal) {
    print('Using mock Github API, as this is run locally.');
    print('Finding changed files from this branch to "$mainBranchName"');
    final gitOutput = Process.runSync(
            'git', ['diff', '--name-status', '$mainBranchName...HEAD']).stdout
        as String;
    final files = parseGitDiff(gitOutput, Directory.current);
    print('Found files: ${files.isNotEmpty ? files.join('\n') : 'None'}');
    githubApi = LocalGithubApi(prLabels: [], files: files);
  } else {
    print('Using Github API, as this is executed on GitHub.');
    githubApi = GithubApi();
  }
  for (var check in checks.isEmpty ? Check.values : checks) {
    await Health(
      Directory.current,
      check,
      warnOn,
      failOn,
      coverageWeb,
      ignorePackages,
      ignoredFor,
      experiments,
      githubApi,
      flutterPackages,
      healthYamlNames: healthYamlNames,
      comment: isLocal ? parsedArgs.option('comment') : null,
      license: license,
      licenseTestString: licenseTestString,
    ).healthCheck();
  }
}

String? nullIfEmpty(String? value) =>
    value != null && value.isNotEmpty ? value : null;

extension on ArgResults {
  List<String> listNonEmpty(String key) =>
      (this[key] as List<String>).where((e) => e.isNotEmpty).toList();
}

FileStatus _mapGitCodeToStatus(String char) => switch (char) {
      'A' => FileStatus.added,
      'D' => FileStatus.removed,
      'M' => FileStatus.modified,
      'R' => FileStatus.renamed,
      'C' => FileStatus.copied,
      'T' => FileStatus.changed,
      'U' => FileStatus.unchanged,
      _ => FileStatus.changed,
    };

/// Parses raw stdout from `git diff --name-status`
Iterable<GitFile> parseGitDiff(String gitOutput, Directory repoRoot) =>
    const LineSplitter()
        .convert(gitOutput)
        .where(
          (line) => line.isNotEmpty,
        )
        .map(
      (line) {
        // Line should be of the form
        // M      pkgs/firehose/lib/src/health/health.dart
        final parts = line.split(RegExp(r'\s+'));

        if (parts.length < 2) {
          throw ArgumentError('Could not construct GitFile from $line'
              ' as output of `git diff --name-status`');
        }

        final status = _mapGitCodeToStatus(parts[0][0]);

        // Handle Renames: Git outputs "R100 old_path new_path".
        // We care only about the 'new_path'.
        return GitFile(parts.last, status, repoRoot);
      },
    );
