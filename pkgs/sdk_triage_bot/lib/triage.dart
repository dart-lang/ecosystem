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
  bool force = false,
  required GithubService githubService,
  required GeminiService geminiService,
  required Logger logger,
}) async {
  logger.log('Triaging $sdkSlug...');
  logger.log('');

  // retrieve the issue
  final issue = await githubService.fetchIssue(sdkSlug, issueNumber);
  logger.log('## issue "${issue.htmlUrl}"');
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

  // decide if we should triage
  final alreadyTriaged = labels.any((l) => l.startsWith('area-'));
  if (alreadyTriaged && !force) {
    logger.log('Exiting (issue is already triaged).');
    return;
  }

  // ask for the summary
  var bodyTrimmed = trimmedBody(issue.body);
  String summary;
  try {
    // Failures here can include things like gemini safety issues, ...
    summary = await geminiService.summarize(
      summarizeIssuePrompt(title: issue.title, body: bodyTrimmed),
    );
  } on GenerativeAIException catch (e) {
    stderr.writeln('gemini: $e');
    exit(1);
  }

  logger.log('## gemini summary');
  logger.log('');
  logger.log(summary);
  logger.log('');

  // ask for the 'area-' classification
  List<String> classification;
  try {
    // Failures here can include things like gemini safety issues, ...
    classification = await geminiService.classify(
      assignAreaPrompt(title: issue.title, body: bodyTrimmed),
    );
  } on GenerativeAIException catch (e) {
    stderr.writeln('gemini: $e');
    exit(1);
  }

  logger.log('## gemini classification');
  logger.log('');
  logger.log(classification.toString());
  logger.log('');

  if (dryRun) {
    logger.log('Exiting (dry run mode - not applying changes).');
    return;
  }

  // perform changes
  logger.log('## github comment');
  logger.log('');
  logger.log(summary);
  logger.log('');
  logger.log('labels: $classification');

  var comment = '';
  if (classification.isNotEmpty) {
    comment += classification.map((l) => '`$l`').join(', ');
    comment += '\n';
  }
  comment += '> $summary\n';

  // create github comment
  await githubService.createComment(sdkSlug, issueNumber, comment);

  final allLabels = await githubService.getAllLabels(sdkSlug);
  var newLabels = filterExistingLabels(allLabels, classification);
  if (newLabels.any((l) => l.startsWith('area-'))) {
    newLabels.add('triage-automation');
  }
  // remove any duplicates
  newLabels = newLabels.toSet().toList();

  // apply github labels
  if (newLabels.isNotEmpty) {
    await githubService.addLabelsToIssue(sdkSlug, issueNumber, newLabels);
  }

  logger.log('');
  logger.log('---');
  logger.log('');
  logger.log('Triaged ${issue.htmlUrl}.');
}

List<String> filterExistingLabels(
    List<String> allLabels, List<String> newLabels) {
  return newLabels.toSet().intersection(allLabels.toSet()).toList();
}
