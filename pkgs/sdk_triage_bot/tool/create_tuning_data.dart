// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:sdk_triage_bot/src/common.dart';
import 'package:sdk_triage_bot/src/github.dart';
import 'package:sdk_triage_bot/src/prompts.dart';

// Here, we download 500-1000 already triaged github issues and create a file
// suitable for tuning a Gemini model (via https://aistudio.google.com/).
//
//   - make sure we have more of the more common areas
//   - make sure we have at least 10 items from each area

const Map<String, int> areaSampleCount = {
  'area-vm': 100,
  'area-analyzer': 100,
  'area-web': 100,
  'area-core-library': 100,
  'area-front-end': 100,
  //
  'area-language': 50,
  'area-infrastructure': 50,
  'area-test': 50,
  'area-dart-cli': 50,
  //
  'area-meta': 25,
  'area-dart2wasm': 25,
  //
  'area-sdk': 10,
  'area-intellij': 10,
  'area-tools': 10,
  'area-build': 10,
  'area-google3': 10,
};

void main(List<String> args) async {
  print('Building tuning data...');
  print('');

  // download issues
  final issueMap = <int, Issue>{};

  for (var entry in areaSampleCount.entries) {
    final areaLabel = entry.key;
    final count = entry.value;

    final results = await downloadIssues(areaLabel, count);
    print('Downloaded ${results.length} issues from $areaLabel');

    // use the map to remove dups
    for (final issue in results) {
      issueMap[issue.number] = issue;
    }
  }

  // sort by issue number
  final issues = issueMap.values.toList();
  issues.sort((a, b) => b.number - a.number);

  // emit training file
  final trainingFileCsv = File('tool/training.csv');
  final trainingFileJsonl = File('tool/training.jsonl');
  final trainingFileDesc = File('tool/training.txt');

  final trainingDataCsv =
      issues.map((issue) => issue.trainingRowCSV).join('\n');
  trainingFileCsv.writeAsStringSync('$trainingDataCsv\n');

  final trainingDataJsonl =
      issues.map((issue) => issue.trainingRowJsonl).join('\n');
  trainingFileJsonl.writeAsStringSync('$trainingDataJsonl\n');

  final trainingDesc = issues.map((issue) => issue.trainingDesc).join('\n');
  trainingFileDesc.writeAsStringSync('$trainingDesc\n');

  print('');
  print('Wrote training data to ${trainingFileCsv.path} and '
      '${trainingFileJsonl.path}.');
  exit(0);
}

Future<List<Issue>> downloadIssues(String areaLabel, int count) async {
  var result = await fetchIssues(areaLabel);

  final issues = <Issue>[];

  while (result.issues.isNotEmpty) {
    for (final issue in result.issues) {
      issues.add(issue);

      if (issues.length >= count) {
        return issues;
      }
    }

    if (!result.hasNext) {
      break;
    } else {
      result = await fetchIssues(areaLabel, cursor: result.cursor);
    }
  }

  return issues;
}

extension on Issue {
  String get trainingRowCSV {
    final bodyValue = trimmedBody(bodyText!);
    final filteredLabels = labels.map((l) => l.name).where((label) {
      if (label.startsWith('area-')) return true;
      if (label.startsWith('type-')) return true;
      return false;
    }).toList();

    // csv encode
    final input = assignAreaPrompt(title: title, body: bodyValue);
    final output = filteredLabels.join(', ');

    return '${csvEncode(input)},${csvEncode(output)}';
  }

  String get trainingRowJsonl {
    final bodyValue = trimmedBody(bodyText!);
    final filteredLabels = labels.map((l) => l.name).where((label) {
      if (label.startsWith('area-')) return true;
      if (label.startsWith('type-')) return true;
      return false;
    }).toList();

    final input = assignAreaPrompt(title: title, body: bodyValue);
    final output = filteredLabels.join(', ');

    return jsonEncode({
      'messages': [
        {'role': 'user', 'content': input},
        {'role': 'model', 'content': output},
      ],
    });
  }

  String get trainingDesc {
    var shortTitle = title;
    if (shortTitle.length > 80) {
      shortTitle = '${shortTitle.substring(0, 80)}...';
    }
    final filteredLabels = labels.map((l) => l.name).where((label) {
      if (label.startsWith('area-')) return true;
      if (label.startsWith('type-')) return true;
      return false;
    }).toList();

    return '[$number] "$shortTitle": ${filteredLabels.join(', ')}';
  }
}

String csvEncode(String str) {
  str = str.replaceAll('\n', r' \n ');

  if (str.contains('"')) {
    str = str.replaceAll('"', '""');
  }

  if (str.contains("'") || str.contains(' ') || str.contains('"')) {
    return '"$str"';
  }

  return str;
}
