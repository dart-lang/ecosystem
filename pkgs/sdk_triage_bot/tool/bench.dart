// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This script benchmarks the issues listed in tool/bench.md using the current
// issue triage prompt and writes the results back into bench.md.

import 'dart:io';

import 'package:github/github.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:sdk_triage_bot/src/common.dart';
import 'package:sdk_triage_bot/src/gemini.dart';
import 'package:sdk_triage_bot/src/github.dart';
import 'package:sdk_triage_bot/src/prompts.dart';

final sdkSlug = RepositorySlug('dart-lang', 'sdk');

void main(List<String> args) async {
  print('Running benchmark against current prompt...');
  print('');

  final client = http.Client();

  final github = GitHub(
    auth: Authentication.withToken(githubToken),
    client: client,
  );
  final githubService = GithubService(github: github);
  final geminiService = GeminiService(
    apiKey: geminiKey,
    httpClient: client,
  );

  // read issues
  final benchmarkFile = File('tool/bench.md');
  final lines = benchmarkFile
      .readAsLinesSync()
      .where((l) => l.startsWith('| #'))
      .toList();

  final expectations = lines.map(ClassificationResults.parseFrom).toList();
  var predicted = 0;

  print('${expectations.length} issues read.');
  print('');

  for (var expectation in expectations) {
    final issue =
        await githubService.fetchIssue(sdkSlug, expectation.issueNumber);
    final bodyTrimmed = trimmedBody(issue.body);

    print('#${issue.number}: ${expectation.expectedLabels.join(', ')}');

    try {
      final labels = await geminiService.classify(
        assignAreaPrompt(title: issue.title, body: bodyTrimmed),
      );
      if (expectation.satisfiedBy(labels)) {
        predicted++;
      } else {
        stderr.writeln('   bot: ${labels.join(', ')}');
      }
    } on GenerativeAIException catch (e) {
      // Failures here can include things like gemini safety issues, ...
      stderr.writeln('gemini: $e');
    }
  }

  final result = predicted * 100.0 / expectations.length;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final percent = result.toStringAsFixed(1);
  final model = GeminiService.classificationModel.split('/')[1];

  benchmarkFile.writeAsStringSync(
    '$today: $percent% using $model\n',
    mode: FileMode.append,
  );

  print('');
  print('$today: $percent% using $model');

  client.close();
}

class ClassificationResults {
  final int issueNumber;
  final List<String> expectedLabels;

  ClassificationResults({
    required this.issueNumber,
    required this.expectedLabels,
  });

  static ClassificationResults parseFrom(String line) {
    // | #56366 | `area-dart2wasm`, `type-enhancement` |
    final sections = line.split('|').skip(1).take(2).toList();
    final number = sections[0].trim();
    final labels = sections[1].trim();

    return ClassificationResults(
      issueNumber: int.parse(number.substring(1)),
      expectedLabels: labels.split(',').map((label) {
        label = label.trim();
        return label.substring(1, label.length - 1);
      }).toList(),
    );
  }

  bool satisfiedBy(List<String> labels) {
    // Handle a `needs-info` label.
    if (expectedLabels.contains('needs-info')) {
      return labels.contains('needs-info');
    }

    // Handle a `breaking-change-request` label.
    if (expectedLabels.contains('breaking-change-request')) {
      return labels.contains('breaking-change-request');
    }

    for (final label in expectedLabels.where((l) => l.startsWith('area-'))) {
      if (!labels.contains(label)) {
        return false;
      }
    }

    return true;
  }
}
