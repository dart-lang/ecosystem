// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:github/src/common/model/repos.dart';
import 'package:glob/glob.dart';

void main(List<String> arguments) async {
  var checkTypes = Check.values.map((c) => c.name);
  var argParser = ArgParser()
    ..addOption(
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
      'ignore_license',
      defaultsTo: [],
      help: 'Which files to ignore for the license check.',
    )
    ..addMultiOption(
      'ignore_coverage',
      defaultsTo: [],
      help: 'Which files to ignore for the coverage check.',
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
    ..addFlag(
      'cli_mode',
      help: 'Whether to use the Github API or manually provide the input.',
    )
    ..addOption('pr_body')
    ..addOption('file_list', defaultsTo: '');
  final parsedArgs = argParser.parse(arguments);
  final checkStr = parsedArgs.option('check');
  final check = Check.values.firstWhere((c) => c.name == checkStr);
  final warnOn = parsedArgs.multiOption('warn_on');
  final failOn = parsedArgs.multiOption('fail_on');
  final flutterPackages = _listNonEmpty(parsedArgs, 'flutter_packages');
  final ignorePackages = _listNonEmpty(parsedArgs, 'ignore_packages');
  final ignoreLicense = _listNonEmpty(parsedArgs, 'ignore_license');
  final ignoreCoverage = _listNonEmpty(parsedArgs, 'ignore_coverage');
  final experiments = _listNonEmpty(parsedArgs, 'experiments');
  final coverageWeb = parsedArgs.flag('coverage_web');
  if (warnOn.toSet().intersection(failOn.toSet()).isNotEmpty) {
    throw ArgumentError('The checks for which warnings are displayed and the '
        'checks which lead to failure must be disjoint.');
  }
  var current = Directory.current;
  GithubApi githubApi;
  if (parsedArgs.flag('cli_mode')) {
    final prBody = parsedArgs.option('pr_body');
    final gitFiles = _listNonEmpty(parsedArgs, 'file_list')
        .map((e) => GitFile(e, FileStatus.modified, current))
        .toList();
    githubApi = ManualFileApi(
      prBody: prBody ?? '',
      files: gitFiles,
      prLabels: [],
    );
  } else {
    githubApi = GithubApi();
  }
  await Health(
    current,
    check,
    warnOn,
    failOn,
    coverageWeb,
    ignorePackages,
    ignoreLicense,
    ignoreCoverage,
    experiments,
    githubApi,
    flutterPackages,
  ).healthCheck();
}

List<String> _listNonEmpty(ArgResults parsedArgs, String key) =>
    parsedArgs.multiOption(key).where((option) => option.isNotEmpty).toList();

class ManualFileApi implements GithubApi {
  final String prBody;
  final List<GitFile> files;

  @override
  final List<String> prLabels;

  ManualFileApi({
    required this.prBody,
    required this.files,
    required this.prLabels,
  });

  @override
  String? get actor => throw UnimplementedError();

  @override
  void appendStepSummary(String markdownSummary) {}

  @override
  String? get baseRef => throw UnimplementedError();

  @override
  void close() {}

  @override
  Future<int?> findCommentId({required String user, String? searchTerm}) {
    throw UnimplementedError();
  }

  @override
  String? get githubAuthToken => null;

  @override
  bool get inGithubContext => false;

  @override
  Future<List<GitFile>> listFilesForPR(Directory directory,
          [List<Glob> ignoredFiles = const []]) async =>
      files;

  @override
  void notice({required String message}) {}

  @override
  Future<String> pullrequestBody() async => prBody;

  @override
  String? get refName => throw UnimplementedError();

  @override
  RepositorySlug? get repoSlug => RepositorySlug('owner', 'name');

  @override
  int? get issueNumber => -1;

  @override
  String? get sha => '';
}
