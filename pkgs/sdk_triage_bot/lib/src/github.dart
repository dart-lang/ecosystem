// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_dynamic_calls

import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'common.dart';

abstract class GithubService {
  Future<List<String>> getAllLabels(RepositorySlug repoSlug);

  Future<Issue> getIssue(RepositorySlug sdkSlug, int issueNumber);

  Future createComment(RepositorySlug sdkSlug, int issueNumber, String comment);

  Future addLabelsToIssue(
      RepositorySlug sdkSlug, int issueNumber, List<String> newLabels);
}

class GithubServiceImpl implements GithubService {
  final GitHub github;

  GithubServiceImpl({required this.github});

  @override
  Future<List<String>> getAllLabels(RepositorySlug repoSlug) async {
    final result = await github.issues.listLabels(repoSlug).toList();
    return result.map((item) => item.name).toList();
  }

  @override
  Future<Issue> getIssue(RepositorySlug sdkSlug, int issueNumber) async {
    return await github.issues.get(sdkSlug, issueNumber);
  }

  @override
  Future createComment(
      RepositorySlug sdkSlug, int issueNumber, String comment) async {
    await github.issues.createComment(sdkSlug, issueNumber, comment);
  }

  @override
  Future addLabelsToIssue(
      RepositorySlug sdkSlug, int issueNumber, List<String> newLabels) async {
    await github.issues.addLabelsToIssue(sdkSlug, issueNumber, newLabels);
  }
}

Future<FetchIssuesResult> fetchIssues(
  String areaLabel, {
  String? cursor,
}) async {
  final result = await _query(QueryOptions(
    document: gql(_buildQueryString(areaLabel, cursor: cursor)),
    fetchPolicy: FetchPolicy.noCache,
    parserFn: (data) {
      final search = data['search'] as Map<String, dynamic>;

      // parse issues
      final edges = search['edges'] as List;

      final issues = edges.map((data) {
        final node = data['node'] as Map<String, dynamic>;
        final labels = (node['labels']['edges'] as List).map((data) {
          final node = data['node'] as Map<String, dynamic>;
          return IssueLabel(name: node['name'] as String);
        }).toList();

        return Issue(
          title: node['title'] as String,
          number: node['number'] as int,
          state: node['state'] as String,
          bodyText: node['bodyText'] as String?,
          labels: labels,
        );
      }).toList();

      // parse cursor
      final pageInfo = search['pageInfo'] as Map<String, dynamic>;

      return FetchIssuesResult(
        cursor: pageInfo['endCursor'] as String?,
        hasNext: pageInfo['hasNextPage'] as bool,
        issues: issues,
      );
    },
  ));

  return result.hasException ? throw result.exception! : result.parsedData!;
}

class FetchIssuesResult {
  final bool hasNext;
  final String? cursor;
  final List<Issue> issues;

  FetchIssuesResult({
    required this.hasNext,
    required this.cursor,
    required this.issues,
  });

  @override
  String toString() =>
      '[hasNext=$hasNext, cursor=$cursor, issues=${issues.length}]';
}

Future<QueryResult<T>> _query<T>(QueryOptions<T> options) {
  return _client.query<T>(options);
}

String _buildQueryString(String areaLabel, {String? cursor}) {
  final cursorRef = cursor == null ? null : '"$cursor"';

  return '''{
  search(
    query: "repo:dart-lang/sdk is:issue is:open label:$areaLabel"
    type: ISSUE
    first: 100,
    after: $cursorRef
  ) {
    edges {
      node {
        ... on Issue {
          title
          number
          state
          bodyText
          labels(first: 10) {
            edges {
              node {
                name
              }
            }
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
}''';
}

final GraphQLClient _client = _initGraphQLClient();

GraphQLClient _initGraphQLClient() {
  final token = githubToken;

  final auth = AuthLink(getToken: () async => 'Bearer $token');
  return GraphQLClient(
    cache: GraphQLCache(),
    link: auth.concat(HttpLink('https://api.github.com/graphql')),
  );
}
