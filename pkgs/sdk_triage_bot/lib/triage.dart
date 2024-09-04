// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'src/common.dart';
import 'src/gemini.dart';
import 'src/github.dart';
import 'src/prompts.dart';

final sdkSlug = RepositorySlug('dart-lang', 'sdk');

Future<void> triage(
  int issueNumber, {
  bool dryRun = false,
  bool forceTriage = false,
  required GithubService githubService,
  required GeminiService geminiService,
  required Logger logger,
}) async {
  logger.log('Triaging $sdkSlug...');
  logger.log('');

  // retrieve the issue
  final issue = await githubService.fetchIssue(sdkSlug, issueNumber);
  logger.log('## issue ${issue.htmlUrl}');
  logger.log('');
  final labels = issue.labels.map((l) => l.name).toList();
  if (labels.isNotEmpty) {
    logger.log('labels: ${labels.join(', ')}');
    logger.log('');
  }
  logger.log('"${issue.title}"');
  logger.log('');
  final bodyLines =
      issue.body.split('\n').where((l) => l.trim().isNotEmpty).toList();
  for (final line in bodyLines.take(4)) {
    logger.log(line);
  }
  if (bodyLines.length > 4) {
    logger.log('...');
  }
  logger.log('');

  // If the issue has any comments, retrieve and include the last comment in the
  // prompt.
  String? lastComment;
  if (issue.hasComments) {
    final comments = await githubService.fetchIssueComments(sdkSlug, issue);
    final comment = comments.last;

    lastComment = '''
---

Here is the last comment on the issue (by user @${comment.user?.login}):

${trimmedBody(comment.body ?? '')}
''';
  }

  // decide if we should triage
  if (!forceTriage) {
    if (issue.alreadyTriaged) {
      logger.log('Exiting (issue is already triaged).');
      return;
    }
  }

  var bodyTrimmed = trimmedBody(issue.body);

  // ask for the 'area-' classification
  List<String> newLabels;
  try {
    newLabels = await geminiService.classify(
      assignAreaPrompt(
        title: issue.title,
        body: bodyTrimmed,
        lastComment: lastComment,
      ),
    );
  } on GenerativeAIException catch (e) {
    // Failures here can include things like gemini safety issues, ...
    stderr.writeln('gemini: $e');
    exit(1);
  }

  // ask for the summary
  String summary;
  try {
    summary = await geminiService.summarize(
      summarizeIssuePrompt(
        title: issue.title,
        body: bodyTrimmed,
        needsInfo: newLabels.contains('needs-info'),
      ),
    );
  } on GenerativeAIException catch (e) {
    // Failures here can include things like gemini safety issues, ...
    stderr.writeln('gemini: $e');
    exit(1);
  }

  logger.log('## gemini summary');
  logger.log('');
  logger.log(summary);
  logger.log('');

  logger.log('## gemini classification');
  logger.log('');
  logger.log(newLabels.toString());
  logger.log('');

  if (dryRun) {
    logger.log('Exiting (dry run mode - not applying changes).');
    return;
  }

  // perform changes
  logger.log('## github comment');
  logger.log('');
  logger.log('labels: $newLabels');
  logger.log('');
  logger.log(summary);

  final comment = '**Summary:** $summary\n';

  // create github comment
  await githubService.createComment(sdkSlug, issueNumber, comment);

  final allRepoLabels = await githubService.getAllLabels(sdkSlug);
  final labelAdditions =
      filterLegalLabels(newLabels, allRepoLabels: allRepoLabels);
  if (labelAdditions.isNotEmpty) {
    labelAdditions.add('triage-automation');
  }

  // apply github labels
  if (newLabels.isNotEmpty) {
    await githubService.addLabelsToIssue(sdkSlug, issueNumber, labelAdditions);
  }

  logger.log('');
  logger.log('---');
  logger.log('');
  logger.log('Triaged ${issue.htmlUrl}');
}

List<String> filterLegalLabels(
  List<String> labels, {
  required List<String> allRepoLabels,
}) {
  final validLabels = allRepoLabels.toSet();
  return [
    for (var label in labels)
      if (validLabels.contains(label)) label,
  ]..sort();
}
