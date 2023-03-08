// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'src/common.dart';

class TransferIssuesCommand extends ReportCommand {
  TransferIssuesCommand()
      : super('transfer-issues',
            'Bulk transfer issues from one repo to another.') {
    argParser.addFlag(
      'apply-changes',
      negatable: false,
      help: 'WARNING: This will transfer the issues. Please preview the changes'
          "first by running without '--apply-changes'.",
      defaultsTo: false,
    );
    argParser.addMultiOption(
      'issue-numbers',
      valueHelp: '1,2,3',
      help: 'Specifiy the numbers of specific issues to transfer, otherwise'
          ' transfers all.',
    );
    argParser.addOption(
      'source-repo',
      valueHelp: 'repo-org/repo-name',
      help: 'The source repository for the issues to be moved from.',
    );
    argParser.addOption(
      'target-repo',
      valueHelp: 'repo-org/repo-name',
      help: 'The target repository name where the issues will be moved to.',
    );
    argParser.addOption(
      'add-label',
      help: 'Add a label to all transferred issues.',
      valueHelp: 'pkg:foo',
    );
  }

  @override
  String get invocation =>
      '${super.invocation} --target-repo <repo-org/repo-name> --add-label <pkg:old-repo-name>';

  @override
  Future<int> run() async {
    var applyChanges = argResults!['apply-changes'] as bool;

    var sourceRepo = argResults!['source-repo'] as String?;
    var targetRepo = argResults!['target-repo'] as String?;
    if (targetRepo == null || sourceRepo == null) {
      print('target-repo and source-repo must be specified.');
      exit(0);
    }

    var issueNumberString = argResults!['issue-numbers'] as List<String>?;
    var issueNumbers = issueNumberString?.map(int.parse).toList();
    var labelName = argResults!['add-label'] as String?;

    return await transferIssues(
      RepositorySlug.full(sourceRepo),
      RepositorySlug.full(targetRepo),
      issueNumbers,
      labelName,
      applyChanges,
    );
  }

  Future<int> transferIssues(
    RepositorySlug sourceRepo,
    RepositorySlug targetRepo, [
    List<int>? issueNumbers,
    String? labelName,
    bool applyChanges = false,
  ]) async {
    if (labelName != null) {
      print('Create label $labelName');
      if (applyChanges) {
        await reportRunner.github.issues.createLabel(targetRepo, labelName);
      }
    }

    var parsedData =
        await transferIssue(sourceRepo, targetRepo, labelName, applyChanges);

    if (labelName != null) {
      for (var issueNumber in parsedData) {
        print('Add label $labelName to issue $issueNumber');
        if (applyChanges) {
          await reportRunner.github.issues.addLabelsToIssue(
            targetRepo,
            issueNumber,
            [labelName],
          );
        }
      }
    }

    return 0;
  }

  Future<List<String>> getIssueIds(
    RepositorySlug slug, [
    List<int>? issueNumbers,
  ]) async {
    final queryString = '''query {
  repository(owner:"${slug.owner}", name:"${slug.name}") {
    issues(last:100) {
      nodes {
        id
        number
      }
    }
  }
}
''';
    final result = await query(QueryOptions(
      document: gql(queryString),
      // If the cache is enabled this will always return the same issues, even
      // after transferring them to another repo.
      fetchPolicy: FetchPolicy.noCache,
      parserFn: (data) {
        var repository = data['repository'] as Map;
        var issues = repository['issues'] as Map;
        var nodes = issues['nodes'] as List;
        return nodes
            .map((node) => node as Map)
            .where((node) => issueNumbers != null
                ? issueNumbers.contains(node['number'] as int)
                : true)
            .map((node) => node['id'] as String)
            .toList();
      },
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }

  Future<String> getRepositoryId(RepositorySlug slug) async {
    final queryString = '''query {
  repository(owner:"${slug.owner}", name:"${slug.name}") {
    id
  }
}
''';
    final result = await query(QueryOptions(
      document: gql(queryString),
      parserFn: (data) {
        var repository = data['repository'] as Map;
        return repository['id'] as String;
      },
    ));

    return result.hasException ? throw result.exception! : result.parsedData!;
  }

  Future<List<int>> transferIssue(
    RepositorySlug sourceRepo,
    RepositorySlug targetRepo,
    String? issueLabel,
    bool applyChanges,
  ) async {
    var repositoryId = await getRepositoryId(targetRepo);
    var allIssueIds = <int>[];
    while (true) {
      var issueIds = await getIssueIds(sourceRepo);
      if (issueIds.isEmpty) {
        print('Done transferring a total of ${allIssueIds.length} issues from '
            '$sourceRepo to $targetRepo');
        return allIssueIds;
      }
      print('Transfer ${issueIds.length} issues from $sourceRepo to $targetRepo'
          'with id $repositoryId');
      var transferredIssues =
          await _transferMutation(issueIds, repositoryId, applyChanges);
      allIssueIds.addAll(transferredIssues);
      if (!applyChanges) {
        return List.generate(issueIds.length, (index) => index);
      }

      print('Waiting a bit to allow Github to catch up...');
      await Future.delayed(Duration(seconds: 5));
    }
  }

  Future<List<int>> _transferMutation(
    List<String> issueIds,
    String repositoryId,
    bool applyChanges,
  ) async {
    var queryStringBuilder = StringBuffer('mutation {\n');
    for (var i = 0; i < issueIds.length; i++) {
      var issue = issueIds[i];
      queryStringBuilder.writeln(
          '''t${i.toString()}: transferIssue(input: {issueId: "$issue", repositoryId: "$repositoryId", createLabelsIfMissing: true}) { issue { number }}''');
    }
    queryStringBuilder.writeln('}');
    final queryString = queryStringBuilder.toString();

    if (applyChanges) {
      final result = await mutate(MutationOptions(
        document: gql(queryString),
        parserFn: (data) {
          //{__typename: Mutation, t0: {__typename: TransferIssuePayload, issue:
          // {__typename: Issue, number: 18}}, t1: {__typename:
          //TransferIssuePayload, issue: {__type
          return data.entries
              .where((entry) => entry.key != '__typename')
              .map((entry) => entry.value)
              .map((mutation) => mutation as Map)
              .map((mutation) => mutation['issue'] as Map)
              .map((issue) => issue['number'] as int)
              .toList();
        },
      ));
      if (result.hasException) throw result.exception!;
      return result.parsedData ?? [];
    } else {
      return [];
    }
  }
}
