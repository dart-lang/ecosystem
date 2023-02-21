// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:math';

import 'src/common.dart';

class LabelsCommand extends ReportCommand {
  LabelsCommand()
      : super('labels',
            'Report on the various labels in use by dart-lang repos.');

  @override
  Future<int> run() async {
    var repos = getReposForOrg('dart-lang');

    var results = <Repo, List<Label>>{};

    for (var repo in await repos.toList()) {
      var page = 1;
      var lastItemCount = 0;
      do {
        var json = await callRestApi(Uri.parse(
            'https://api.github.com/repos/${repo.org}/${repo.name}/labels?per_page=100&page=$page'));
        var items = (jsonDecode(json!) as List).cast<Map>();
        var labels = items.map((item) => Label(item.cast<String, dynamic>()));
        results.putIfAbsent(repo, () => []).addAll(labels);

        page++;
        lastItemCount = items.length;
      } while (lastItemCount > 0);

      print('${repo.slug} has ${results[repo]!.length} labels '
          '(${repo.openIssuesCount} issues, ${repo.stargazersCount} stars).');
    }

    print('');

    // calculate label usage
    var labels = <String, LabelInfo>{};

    for (var entry in results.entries) {
      var repo = entry.key;
      if (repo.openIssuesCount < 30) continue;

      for (var label in entry.value) {
        var labelInfo =
            labels.putIfAbsent(label.name, () => LabelInfo(label.name));

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

class Label {
  Map<String, dynamic> json;

  Label(this.json);

  String get name => json['name'] as String;
  String? get description => json['description'] as String?;
  String get color => json['color'] as String;
}

class LabelInfo {
  final String name;
  final Set<String> repos = {};

  double weight = 0.0;

  LabelInfo(this.name);

  int get repoCount => repos.length;

  String get repoNames => (repos.toList()..sort()).join(',');
}
