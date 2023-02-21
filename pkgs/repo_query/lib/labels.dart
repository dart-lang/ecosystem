// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:github/github.dart';

import 'src/common.dart';

class LabelsCommand extends ReportCommand {
  LabelsCommand()
      : super('labels',
            'Report on the various labels in use by dart-lang repos.');

  @override
  Future<int> run() async {
    var repos = await getReposForOrg('dart-lang');

    var results = <Repository, List<IssueLabel>>{};

    for (var repo in repos) {
      var labels =
          await reportRunner.github.issues.listLabels(repo.slug()).toList();

      results[repo] = labels;

      print('${repo.slug} has ${results[repo]!.length} labels '
          '(${repo.openIssuesCount} issues, ${repo.stargazersCount} stars).');
    }

    print('');

    // calculate label usage
    var labels = <String, _LabelInfo>{};

    for (var entry in results.entries) {
      var repo = entry.key;
      if (repo.openIssuesCount < 30) continue;

      for (var label in entry.value) {
        var labelInfo =
            labels.putIfAbsent(label.name, () => _LabelInfo(label.name));

        labelInfo.repos.add(repo.name);
        labelInfo.weight += log(repo.openIssuesCount);
      }
    }

    print('Label,Count,Weighted Repo,Repos');

    var labelUsage = labels.values.toList()
      ..sort((a, b) => b.repoCount - a.repoCount);

    for (var info in labelUsage) {
      print('${info.name},${info.repoCount},${info.weight.toStringAsFixed(1)},'
          '"${info.repoNames}"');
    }

    return 0;
  }
}

class _LabelInfo {
  final String name;
  final Set<String> repos = {};

  double weight = 0.0;

  _LabelInfo(this.name);

  int get repoCount => repos.length;

  String get repoNames => (repos.toList()..sort()).join(',');
}
