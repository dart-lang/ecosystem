// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:github/github.dart';

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
}) async {
  print('Triaging $sdkSlug...');
  print('');

  // retrieve the issue
  final issue = await githubService.getIssue(sdkSlug, issueNumber);
  print('## issue ${issue.url}');
  print('');
  print('title: ${issue.title}');
  final labels = issue.labels.map((l) => l.name).toList();
  if (labels.isNotEmpty) {
    print('labels: ${labels.join(', ')}');
  }
  final bodyLines = issue.body.split('\n');
  print('body: ${bodyLines.first}');
  for (final line in bodyLines.skip(1).take(2)) {
    print('  $line');
  }
  if (bodyLines.length > 3) {
    print('  ...');
  }
  print('');

  // decide if we should triage
  final alreadyTriaged = labels.any((l) => l.startsWith('area-'));
  if (alreadyTriaged && !force) {
    print('Exiting (issue is already triaged).');
    return;
  }

  // ask for the summary
  var bodyTrimmed = trimmedBody(issue.body);
  // TODO(devoncarew): handle safety failures
  final summary = await geminiService.summarize(
    summarizeIssuePrompt(title: issue.title, body: bodyTrimmed),
  );
  print('## gemini summary');
  print('');
  print(summary);
  print('');

  // ask for the 'area-' classification
  // TODO(devoncarew): handle safety failures
  final classification = await geminiService.classify(
    assignAreaPrompt(title: issue.title, body: bodyTrimmed),
  );
  print('## gemini classification');
  print('');
  print(classification);
  print('');

  if (dryRun) {
    print('Exiting (dry run mode - not applying changes).');
    return;
  }

  // perform changes
  const docsText = '(see our triage process '
      '[docs](https://github.com/dart-lang/sdk/blob/main/docs/Triaging-Dart-SDK-issues.md)'
      ')';

  print('## github comment');
  print('');
  print(summary);
  if (classification.isNotEmpty) {
    print('');
    print('labels: $classification');
  }
  print('');
  print(docsText);

  var newLabels = classification.split(',').map((l) => l.trim()).toList();

  var comment = '"$summary"\n\n';
  if (newLabels.isNotEmpty) {
    comment += 'labels: ${newLabels.map((l) => '`$l`').join(', ')}';
    comment += '\n';
  }
  comment += '$docsText\n';

  // create github comment
  await githubService.createComment(sdkSlug, issueNumber, comment);

  final allLabels = await githubService.getAllLabels(sdkSlug);
  newLabels = filterExistingLabels(allLabels, newLabels);
  if (newLabels.any((l) => l.startsWith('area-'))) {
    newLabels.add('triage-automation');
  }
  // remove any duplicates
  newLabels = newLabels.toSet().toList();

  // apply github labels
  if (newLabels.isNotEmpty) {
    await githubService.addLabelsToIssue(sdkSlug, issueNumber, newLabels);
  }

  print('');
  print('---');
  print('');
  print('Triaged ${issue.url}.');
}

List<String> filterExistingLabels(
    List<String> allLabels, List<String> newLabels) {
  return newLabels.toSet().intersection(allLabels.toSet()).toList();
}
