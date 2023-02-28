// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:github/github.dart';
import 'package:graphql/client.dart';

import '../branches.dart';
import '../labels.dart';
import '../labels_update.dart';
import '../links.dart';
import '../weekly.dart';

final GraphQLClient _client = _initGraphQLClient();

GraphQLClient _initGraphQLClient() {
  final token = githubToken;

  final auth = AuthLink(getToken: () async => 'Bearer $token');
  return GraphQLClient(
    cache: GraphQLCache(),
    link: auth.concat(HttpLink('https://api.github.com/graphql')),
  );
}

String get githubToken {
  var token = Platform.environment['GITHUB_TOKEN'];
  if (token == null) {
    throw StateError('This tool expects a github access token in the '
        'GITHUB_TOKEN environment variable.');
  }
  return token;
}

Future<QueryResult<T>> query<T>(QueryOptions<T> options) {
  return _client.query<T>(options);
}

String iso8601String(DateTime date) {
  return date.toIso8601String().substring(0, 10);
}

String overflow(String str, [int overflows = 40]) {
  return str.length <= overflows
      ? str
      : '${str.substring(0, overflows - 3)}...';
}

abstract class ReportCommand extends Command<int> {
  @override
  final String name;

  @override
  final String description;

  ReportCommand(this.name, this.description);

  ReportCommandRunner get reportRunner => runner as ReportCommandRunner;

  Future<List<Repository>> getReposForOrg(String org) async {
    return await reportRunner.github.repositories
        .listUserRepositories(org)
        .toList();
  }
}

class ReportCommandRunner extends CommandRunner<int> {
  GitHub? _github;

  ReportCommandRunner()
      : super('report',
            'Run various reports on Dart and Flutter related repositories.') {
    addCommand(BranchesCommand());
    addCommand(LabelsCommand());
    addCommand(LabelsUpdateCommand());
    addCommand(LinksCommand());
    addCommand(WeeklyCommand());
  }

  GitHub get github =>
      _github ??= GitHub(auth: findAuthenticationFromEnvironment());

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    try {
      return await super.runCommand(topLevelResults);
    } finally {
      close();
    }
  }

  void close() => _github?.dispose();
}

class Repo {
  final String org;
  Map<String, dynamic> json;

  Repo(this.org, this.json);

  String get name => json['name'] as String;
  String get defaultBranch => json['default_branch'] as String;
  int get stargazersCount => json['stargazers_count'] as int;
  int get openIssuesCount => json['open_issues_count'] as int;

  String get slug => '$org/$name';

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    return other is Repo && other.name == name;
  }
}

class RepoInfo {
  final String repo;
  final int issuesOpened;
  final int issuesClosed;
  final int commits;
  final int p0Count;
  final int p1Count;
  final int stargazers;

  RepoInfo(
    this.repo, {
    required this.issuesOpened,
    required this.issuesClosed,
    required this.commits,
    required this.p0Count,
    required this.p1Count,
    required this.stargazers,
  });
}

// These are monorepos, high-traffic repos, or otherwise noteable repos.
final List<String> noteableRepos = [
  'dart-lang/build',
  'dart-lang/ecosystem',
  'dart-lang/ffi',
  'dart-lang/http',
  'dart-lang/language',
  'dart-lang/linter',
  'dart-lang/pub',
  'dart-lang/sdk',
  'dart-lang/shelf',
  'dart-lang/test',
  'dart-lang/tools',
  'dart-lang/webdev',
  'flutter/flutter',
  'flutter/packages',
];
