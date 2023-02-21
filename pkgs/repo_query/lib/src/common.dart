// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import '../branches.dart';
import '../labels.dart';
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

Future<QueryResult> query(QueryOptions options) {
  return _client.query(options);
}

String iso8601String(DateTime date) {
  return date.toIso8601String().substring(0, 10);
}

abstract class ReportCommand extends Command<int> {
  @override
  final String name;

  @override
  final String description;

  ReportCommand(this.name, this.description);

  ReportCommandRunner get reportRunner => runner as ReportCommandRunner;

  Future<String?> callRestApi(Uri uri) {
    return reportRunner.callRestApi(uri);
  }

  Stream<Repo> getReposForOrg(String org) async* {
    int? page = 1;

    while (page != null) {
      var json = await callRestApi(Uri.parse(
          'https://api.github.com/orgs/$org/repos?sort=full_name&page=$page'));

      var repos = (jsonDecode(json!) as List).cast<Map>();

      for (var repo in repos) {
        yield Repo(org, repo.cast<String, dynamic>());
      }

      if (repos.isEmpty) {
        page = null;
      } else {
        page++;
      }
    }
  }
}

class ReportCommandRunner extends CommandRunner<int> {
  http.Client? _httpClient;

  ReportCommandRunner()
      : super('report',
            'Run various reports on Dart and Flutter related repositories.') {
    addCommand(BranchesCommand());
    addCommand(LabelsCommand());
    addCommand(LinksCommand());
    addCommand(WeeklyCommand());
  }

  http.Client get httpClient => _httpClient ??= http.Client();

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    try {
      return super.runCommand(topLevelResults);
    } finally {
      close();
    }
  }

  Future<String?> callRestApi(Uri uri) async {
    return httpClient.get(uri, headers: {
      'Authorization': 'token $githubToken',
      'Accept': 'application/vnd.github+json',
    }).then((response) {
      return response.statusCode == 404 ? null : response.body;
    });
  }

  void close() => _httpClient?.close();
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

// This are monorepos, high-traffic repos, or otherwise noteable repos.
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
  'flutter/plugins',
];
