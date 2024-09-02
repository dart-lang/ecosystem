// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_dynamic_calls

import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'common.dart';

class GithubService {
  final GitHub _gitHub;

  GithubService({required GitHub github}) : _gitHub = github;

  Future<List<String>> getAllLabels(RepositorySlug repoSlug) async {
    final result = await _gitHub.issues.listLabels(repoSlug).toList();
    return result.map((item) => item.name).toList();
  }

  Future<Issue> fetchIssue(RepositorySlug slug, int issueNumber) async {
    return await _gitHub.issues.get(slug, issueNumber);
  }

  Future<List<IssueComment>> fetchIssueComments(
      RepositorySlug slug, Issue issue) async {
    return await _gitHub.issues
        .listCommentsByIssue(slug, issue.number)
        .toList();
  }

  Future createComment(
      RepositorySlug sdkSlug, int issueNumber, String comment) async {
    await _gitHub.issues.createComment(sdkSlug, issueNumber, comment);
  }

  Future addLabelsToIssue(
      RepositorySlug sdkSlug, int issueNumber, List<String> newLabels) async {
    await _gitHub.issues.addLabelsToIssue(sdkSlug, issueNumber, newLabels);
  }
}

Future<FetchIssuesResult> fetchIssues(
  String areaLabel, {
  required bool includeClosed,
  String? cursor,
}) async {
  final result = await _query(QueryOptions(
    document: gql(_buildQueryString(
      areaLabel,
      cursor: cursor,
      includeClosed: includeClosed,
    )),
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

String _buildQueryString(
  String areaLabel, {
  required bool includeClosed,
  String? cursor,
}) {
  final cursorTerm = cursor == null ? '' : 'after: "$cursor"';
  final isOpen = includeClosed ? '' : 'is:open';

  return '''{
    search(
      query: "repo:dart-lang/sdk is:issue $isOpen label:$areaLabel"
      type: ISSUE
      first: 100
      $cursorTerm
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

extension IssueExtension on Issue {
  /// Returns whether this issue has any comments.
  ///
  /// Note that the original text for the issue is returned in the `body` field.
  bool get hasComments => commentsCount > 0;

  /// Returns whether this issue has already been triaged.
  ///
  /// Generally, this means the the issue has had an `area-` label applied to
  /// it, has had `needs-info` applied to it, or was closed.
  bool get alreadyTriaged {
    if (isClosed) return true;

    return labels.any((label) {
      final name = label.name;
      return name == 'needs-info' || name.startsWith('area-');
    });
  }
}
