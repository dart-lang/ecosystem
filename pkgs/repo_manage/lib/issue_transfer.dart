// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:github/github.dart';
import 'package:graphql/client.dart';

import 'src/common.dart';

class TransferIssuesCommand extends ReportCommand {
  TransferIssuesCommand()
      : super('transfer-issues',
            'Bulk transfer issues from one repo to another.') {
    argParser
      ..addFlag(
        'apply-changes',
        negatable: false,
        help:
            'WARNING: This will transfer the issues. Please preview the changes'
            "first by running without '--apply-changes'.",
        defaultsTo: false,
      )
      ..addOption(
        'source-repo',
        valueHelp: 'repo-org/repo-name',
        help: 'The source repository for the issues to be moved from.',
        mandatory: true,
      )
      ..addOption(
        'target-repo',
        valueHelp: 'repo-org/repo-name',
        help: 'The target repository name where the issues will be moved to.',
        mandatory: true,
      )
      ..addOption(
        'add-label',
        help: 'Add a label to all transferred issues.',
        valueHelp: 'package:foo',
        mandatory: true,
      );
  }

  @override
  String get invocation =>
      '${super.invocation} --source-repo repo-org/old-repo-name --target-repo repo-org/new-repo-name --add-label package:old-repo-name';

  @override
  Future<int> run() async {
    var parsedArgs = argResults!;
    var applyChanges = parsedArgs.flag('apply-changes');

    var sourceRepo = parsedArgs.option('source-repo')!;
    var targetRepo = parsedArgs.option('target-repo')!;

    var labelName = argResults!['add-label'] as String;

    if (!applyChanges) {
      print('This is a dry run, no issues will be transferred!');
    }

    return await transferAndLabelIssues(
      RepositorySlug.full(sourceRepo),
      RepositorySlug.full(targetRepo),
      labelName,
      applyChanges,
    );
  }

  Future<int> transferAndLabelIssues(
    RepositorySlug sourceRepo,
    RepositorySlug targetRepo,
    String labelName, [
    bool applyChanges = false,
  ]) async {
    print('Create label $labelName in source and target repo');
    if (applyChanges) {
      await reportRunner.github.issues.createLabel(targetRepo, labelName);
      await reportRunner.github.issues.createLabel(sourceRepo, labelName);
    }

    var issues = await transferIssues(
      sourceRepo,
      targetRepo,
      labelName,
      applyChanges,
    );

    print('Transferred ${issues.length} issues');

    return 0;
  }

  Future<List<({String id, int number})>> getIssueIds(
      RepositorySlug slug) async {
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
            .map((node) =>
                (id: node['id'] as String, number: node['number'] as int))
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

  Future<List<int>> transferIssues(
    RepositorySlug sourceRepo,
    RepositorySlug targetRepo,
    String issueLabel,
    bool applyChanges,
  ) async {
    var repositoryId = await getRepositoryId(targetRepo);

    var allIssueIds = <int>[];
    // As we can only do 100 issues at a time per GraphQL API limitations, we
    // need to run this in a loop.
    while (true) {
      var issueIds = await getIssueIds(sourceRepo);
      if (issueIds.isEmpty) {
        print('Done transferring a total of ${allIssueIds.length} issues from '
            '$sourceRepo to $targetRepo');
        return allIssueIds;
      }
      print('Transfer ${issueIds.length} issues from $sourceRepo to $targetRepo'
          ' with id $repositoryId');

      for (var issueIdChunk in issueIds.slices(10)) {
        print('Transferring a chunk of ${issueIdChunk.length} issues');
        print('Adding label $issueLabel to all issues in chunk');
        for (var issueNumber in issueIdChunk) {
          print('Add to issue $issueNumber');
          if (applyChanges) {
            await reportRunner.github.issues.addLabelsToIssue(
              sourceRepo,
              issueNumber.number,
              [issueLabel],
            );
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        var transferredIssues = await _transferMutation(
          issueIdChunk.map((issue) => issue.id).toList(),
          repositoryId,
          applyChanges,
        );
        if (transferredIssues.$2 != null) {
          stderr.writeln('Failed to transfer issues.');
          stderr.writeln(transferredIssues.$2);
          return allIssueIds;
        }
        allIssueIds.addAll(transferredIssues.$1);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (!applyChanges) {
        // Return mock list of indices to allow user to see how downstream
        // methods would continue.
        return List.generate(issueIds.length, (index) => index);
      }

      print('Waiting a bit to allow Github to catch up...');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<(List<int>, Exception?)> _transferMutation(
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
      return (result.parsedData ?? [], result.exception);
    } else {
      return (<int>[], null);
    }
  }

  bool getInput(String question) {
    print(question);
    final line = stdin.readLineSync()?.toLowerCase();
    return line == 'y' || line == 'yes';
  }
}
