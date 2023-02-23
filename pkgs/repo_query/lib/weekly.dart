// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'src/common.dart';

class WeeklyCommand extends ReportCommand {
  WeeklyCommand()
      : super(
            'weekly', 'Run a week-based report on repo status and activity.') {
    argParser
      ..addOption(
        'date',
        valueHelp: '2022-01-26',
        help: 'Specify the date to pull data from '
            '(defaults to the last full week).',
      )
      ..addFlag(
        'dart-lang',
        negatable: false,
        help: 'Return stats for add dart-lang repos.',
      )
      ..addFlag(
        'monthly',
        negatable: false,
        help: 'Return stats based on calendar months (instead of weeks).',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final byMonth = args['monthly'] as bool;
    final allDartLang = args['dart-lang'] as bool;

    late final DateTime firstReportingDay;
    late final DateTime lastReportingDay;

    if (byMonth) {
      if (args.wasParsed('date')) {
        final day = DateTime.parse(args['date'] as String);
        firstReportingDay = DateTime(day.year, day.month, 1);
      } else {
        final now = DateTime.now();
        firstReportingDay = DateTime(now.year, now.month - 1, 1);
      }

      lastReportingDay =
          DateTime(firstReportingDay.year, firstReportingDay.month + 1, 1);
    } else {
      // by week
      if (args.wasParsed('date')) {
        final day = DateTime.parse(args['date'] as String);
        firstReportingDay = day.subtract(Duration(days: day.weekday - 1));
      } else {
        final now = DateTime.now();
        final currentDay = now.weekday;
        final thisWeek = now.subtract(Duration(days: currentDay - 1));
        firstReportingDay = thisWeek.subtract(Duration(days: 7));
      }

      lastReportingDay = firstReportingDay.add(Duration(days: 6));
    }

    var repos = noteableRepos.map(RepositorySlug.full).toList();

    if (allDartLang) {
      repos = (await getReposForOrg('dart-lang')).map((r) => r.slug()).toList();
    }

    print(
      'Reporting from ${iso8601String(firstReportingDay)} '
      'to ${iso8601String(lastReportingDay)}...',
    );

    var infos = await Future.wait(repos.map((repo) async {
      return RepoInfo(
        repo.fullName,
        issuesOpened: await queryIssuesOpened(
          repo: repo,
          from: firstReportingDay,
          to: lastReportingDay,
        ),
        issuesClosed: await queryIssuesClosed(
          repo: repo,
          from: firstReportingDay,
          to: lastReportingDay,
        ),
        commits: await queryCommitsSince(
          repo: repo,
          since: firstReportingDay,
          until: lastReportingDay,
        ),
        p0Count: await queryIssueCountForLabel(repo: repo, label: 'P0'),
        p1Count: await queryIssueCountForLabel(repo: repo, label: 'P1'),
        stargazers: await queryStargazers(repo: repo),
      );
    }));

    print('');
    print('Repo,Issues Opened,Issues Closed,Commits,P0s,P1s,Stars');

    for (var info in infos) {
      print(
        '${info.repo},'
        '${info.issuesOpened},'
        '${info.issuesClosed},'
        '${info.commits},'
        '${info.p0Count},'
        '${info.p1Count},'
        '${info.stargazers}',
      );
    }

    print('');

    print(
      'All: '
      '${infos.fold(0, (count, info) => count + info.issuesOpened)} opened, '
      '${infos.fold(0, (count, info) => count + info.issuesClosed)} closed, '
      '${infos.fold(0, (count, info) => count + info.commits)} commits, '
      '${infos.fold(0, (count, info) => count + info.p0Count)} P0s, '
      '${infos.fold(0, (count, info) => count + info.p1Count)} P1s, '
      '${infos.fold(0, (count, info) => count + info.stargazers)} stars',
    );

    return 0;
  }

  Future<int> queryIssuesOpened({
    required RepositorySlug repo,
    required DateTime from,
    required DateTime to,
  }) async {
    final queryString = '''{
  search(query: "repo:${repo.fullName} is:issue created:${iso8601String(from)}..${iso8601String(to)}", type: ISSUE, last: 100) {
  issueCount
    edges {
      node { 
        ... on Issue { title url createdAt number state }
      }
    }
  }
}''';

    final result = await query(QueryOptions(
      document: gql(queryString),
      parserFn: (data) => (data['search'] as Map)['issueCount']! as int,
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }

  Future<int> queryIssuesClosed({
    required RepositorySlug repo,
    required DateTime from,
    required DateTime to,
  }) async {
    final queryString = '''{
  search(query: "repo:${repo.fullName} is:issue is:closed closed:${iso8601String(from)}..${iso8601String(to)}", type: ISSUE, last: 100) {
  issueCount
    edges {
      node {
        ... on Issue { title url createdAt number state }
      }
    }
  }
}''';

    final result = await query(QueryOptions(
      document: gql(queryString),
      parserFn: (data) => (data['search'] as Map)['issueCount']! as int,
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }

  Future<int> queryCommitsSince({
    required RepositorySlug repo,
    required DateTime since,
    required DateTime until,
  }) async {
    final queryString = '''{
  repository(owner: "${repo.owner}", name: "${repo.name}") {
    defaultBranchRef {
      target {
        ... on Commit {
          history(since: "${since.toIso8601String()}", until: "${until.toIso8601String()}") {
            totalCount
          }
        }
      }
    }
  }
}''';

    final result = await query(QueryOptions(document: gql(queryString)));
    if (result.hasException) {
      throw result.exception!;
    }
    var target = ((result.data!['repository'] as Map)['defaultBranchRef']
        as Map)['target'] as Map?;
    if (target == null) {
      print('no repo history available for $repo');
      return 0;
    }
    return (target['history'] as Map)['totalCount'] as int;
  }

  Future<int> queryIssueCountForLabel({
    required RepositorySlug repo,
    required String label,
  }) async {
    final queryString = '''query {
  repository(owner:"${repo.owner}", name:"${repo.name}") {
    issues(states:OPEN labels:"$label") {
      totalCount
    }
  }
}
''';

    final result = await query(QueryOptions(
      document: gql(queryString),
      parserFn: (data) =>
          ((data['repository'] as Map)['issues'] as Map)['totalCount'] as int,
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }

  Future<int> queryStargazers({
    required RepositorySlug repo,
  }) async {
    final queryString = '''query {
  repository(owner:"${repo.owner}", name:"${repo.name}") {
    stargazerCount
  }
}
''';

    final result = await query(QueryOptions(
      document: gql(queryString),
      parserFn: (data) => (data['repository'] as Map)['stargazerCount'] as int,
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }
}
