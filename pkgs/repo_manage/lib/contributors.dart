// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'src/common.dart';

class ContributorsCommand extends ReportCommand {
  ContributorsCommand()
      : super(
            'contributors',
            'Run a report on repo contributors.\n'
                'Defaults to the last 365 days.') {
    argParser
      ..addFlag(
        'dart-lang',
        negatable: false,
        help: 'Return stats for all dart-lang repos.',
      )
      ..addFlag(
        'monthly',
        negatable: false,
        help: 'Last 30 days.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final byMonth = args['monthly'] as bool;
    final allDartLang = args['dart-lang'] as bool;

    late final DateTime firstReportingDay;

    if (byMonth) {
      final now = DateTime.now();
      firstReportingDay = now.subtract(const Duration(days: 31));
    } else {
      // by year
      final now = DateTime.now();
      firstReportingDay = now.subtract(const Duration(days: 365));
    }

    var repos = noteableRepos
        .map(RepositorySlug.full)
        .where((repo) => repo.owner == 'dart-lang')
        .toList();

    if (allDartLang) {
      repos = (await getReposForOrg('dart-lang')).map((r) => r.slug()).toList();
    }

    print('Reporting from ${iso8601String(firstReportingDay)}...');

    final aggregates = <String, List<Commit>>{};

    for (final repo in repos) {
      final commits = await queryCommits(repo: repo, from: firstReportingDay);

      print('$repo: ${commits.length} commits');

      for (final commit in commits) {
        aggregates.putIfAbsent(commit.user, () => []).add(commit);
      }
    }

    print('');

    final contributors = <Contributor>[];

    for (final entry in aggregates.entries) {
      contributors.add(
        Contributor(github: entry.key, count: entry.value.length),
      );
    }

    contributors.sort((a, b) {
      return b.count - a.count;
    });

    for (var i = 0; i < contributors.length; i++) {
      final contributor = contributors[i];
      print('[$i] @${contributor.github}: ${contributor.count} commits');
    }

    return 0;
  }

  Future<List<Commit>> queryCommits({
    required RepositorySlug repo,
    required DateTime from,
  }) async {
    var result = await query(
      QueryOptions(document: gql(commitQueryString(repo: repo, from: from))),
    );
    if (result.hasException) throw result.exception!;

    final commits = <Commit>[];

    while (true) {
      if (result.hasException) throw result.exception!;

      commits.addAll(_getCommitsFromResult(result));

      final pageInfo = _pageInfoFromResult(result);
      final hasNextPage = (pageInfo['hasNextPage'] as bool?) ?? false;

      if (hasNextPage) {
        final endCursor = pageInfo['endCursor'] as String?;
        result = await query(
          QueryOptions(
            document: gql(
              commitQueryString(repo: repo, from: from, endCursor: endCursor),
            ),
          ),
        );
      } else {
        break;
      }
    }

    return commits;
  }
}

Iterable<Commit> _getCommitsFromResult(QueryResult result) {
  // ignore: avoid_dynamic_calls
  final history = result.data!['repository']['defaultBranchRef']['target']
      ['history'] as Map;
  var edges = (history['edges'] as List).cast<Map>();

  return edges.map<Commit>((Map edge) {
    var node = edge['node'] as Map<String, dynamic>;
    return Commit.fromQuery(node);
  });
}

Map<String, dynamic> _pageInfoFromResult(QueryResult result) {
  // pageInfo {
  //   endCursor
  //   startCursor
  //   hasNextPage
  //   hasPreviousPage
  // }

  // ignore: avoid_dynamic_calls
  final history = result.data!['repository']['defaultBranchRef']['target']
      ['history'] as Map;

  return (history['pageInfo'] as Map).cast();
}

String commitQueryString({
  required RepositorySlug repo,
  required DateTime from,
  String? endCursor,
}) {
  final since = from.toIso8601String();
  final cursor = endCursor == null ? '' : ', after: "$endCursor"';

  // https://docs.github.com/en/graphql/reference/objects#commit
  return '''{
      repository(owner: "${repo.owner}", name: "${repo.name}") {
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: 100, since: "$since" $cursor) {
                edges {
                  node {
                    oid
                    messageHeadline
                    committedDate
                    author {
                      user {
                        login
                      }
                    }
                    committer {
                      user {
                        login
                      }
                    }
                  }
                }
                pageInfo {
                  endCursor
                  startCursor
                  hasNextPage
                  hasPreviousPage
                }
              }
            }
          }
        }
      }
    }
''';
}

class Commit implements Comparable<Commit> {
  final String oid;
  final String message;
  final String user;
  final DateTime committedDate;

  Commit({
    required this.oid,
    required this.message,
    required this.user,
    required this.committedDate,
  });

  factory Commit.fromQuery(Map<String, dynamic> node) {
    var oid = node['oid'] as String;
    var messageHeadline = node['messageHeadline'] as String;
    // ignore: avoid_dynamic_calls
    var user = (node['author']['user'] ?? node['committer']['user']) as Map?;
    var login = user == null ? '' : user['login'] as String;
    // 2021-07-23T18:37:57Z
    var committedDate = node['committedDate'] as String;

    if (login.isEmpty) {
      final json = jsonEncode(node);
      print('[$json]');
    }

    return Commit(
      oid: oid,
      message: messageHeadline,
      user: login,
      committedDate: DateTime.parse(committedDate),
    );
  }

  @override
  int compareTo(Commit other) {
    return other.committedDate.compareTo(committedDate);
  }

  @override
  String toString() => '${oid.substring(0, 8)} $_shortDate $user $message';

  String get _shortDate => committedDate.toIso8601String().substring(0, 10);
}

class PageInfo {
  final String endCursor;
  final bool hasNextPage;

  PageInfo({required this.endCursor, required this.hasNextPage});

  static PageInfo parse(Map<String, dynamic> json) {
    return PageInfo(
      endCursor: json['endCursor'] as String,
      hasNextPage: json['hasNextPage'] as bool,
    );
  }
}

class Contributor {
  final String github;
  final int count;

  Contributor({required this.github, required this.count});
}
