// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;
import 'package:yaml_edit/yaml_edit.dart';

import '../action_version.dart';
import '../github.dart';
import '../github_action_resolver.dart';
import '../repo_tweak.dart';

final _instance = GitHubActionTweak._();

class GitHubActionTweak extends RepoTweak {
  factory GitHubActionTweak() => _instance;

  GitHubActionTweak._()
      : super(
          id: 'github-actions',
          description:
              'ensure GitHub actions use the latest versions and are keyed '
              'by SHA',
        );

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) async {
    final files = _workflowFiles(checkout);

    if (files.isEmpty) {
      return FixResult.noFixesMade;
    }

    final neededFixes = <Object>[];

    await _withResolver((githubResolver) async {
      for (var file in files) {
        final relativePath = p.relative(file.path, from: checkout.path);
        print('  Fixing $relativePath');

        final fileChecks = await _fixFile(file, githubResolver);

        if (fileChecks.isNotEmpty) {
          neededFixes.add({relativePath: fileChecks});
        }
      }
    });

    return FixResult(fixes: neededFixes);
  }
}

List<File> _workflowFiles(Directory checkout) {
  final workflowDir = Directory(p.join(checkout.path, _workflowsDir));
  if (!workflowDir.existsSync()) {
    return const [];
  }

  return workflowDir
      .listSync()
      .whereType<File>()
      .where(
        (element) =>
            element.path.endsWith('.yml') || element.path.endsWith('.yaml'),
      )
      .toList();
}

Future<List<String>> _fixFile(
  File workflowFile,
  GitHubActionResolver resolver,
) async {
  final versions = await _versionsForFile(workflowFile, resolver);

  final repos = versions.map((e) => e.fullRepo).toSet();

  final latestVersions = {
    for (var repo in repos) repo: await resolver.latestStable(repo),
  };

  final items = <String>[];

  final content = workflowFile.readAsStringSync();

  final editor = YamlEditor(content);

  final fileYaml = yaml.loadYaml(content, sourceUrl: workflowFile.uri);

  final jobs = (fileYaml as Map)['jobs'] as yaml.YamlMap;

  for (var jobEntry in jobs.entries) {
    final steps = jobEntry.steps;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepMap = step as yaml.YamlMap;
      final uses = stepMap['uses'] as String?;
      if (uses != null) {
        final currentVersion = ActionVersion.parse(uses);
        if (currentVersion.path != null) {
          // skipping things with path!
          continue;
        }
        final targetVersion = latestVersions[currentVersion.fullRepo]!;

        final targetActionVersion = ActionVersion(
          org: currentVersion.org,
          repo: currentVersion.repo,
          path: null,
          version: targetVersion.sha,
        );

        if (targetActionVersion != currentVersion) {
          final path = ['jobs', jobEntry.key, 'steps', i, 'uses'];

          editor.update(
            path,
            targetActionVersion.toString(),
          );

          items.add(
            'Updated ${path.join('/')} from $currentVersion to '
            '$targetActionVersion',
          );
        }
      }
    }
  }

  workflowFile.writeAsStringSync(editor.toString());

  return items;
}

Future<Set<ActionVersion>> _versionsForFile(
  File workflowFile,
  GitHubActionResolver resolver,
) async {
  final content = workflowFile.readAsStringSync();

  final fileYaml = yaml.loadYaml(content, sourceUrl: workflowFile.uri);

  final jobs = (fileYaml as Map)['jobs'] as yaml.YamlMap;

  final result = <ActionVersion>{};

  for (var jobEntry in jobs.entries) {
    final steps = jobEntry.steps;
    for (var step in steps) {
      final stepMap = step as yaml.YamlMap;
      final uses = stepMap['uses'] as String?;
      if (uses != null) {
        final parsed = ActionVersion.parse(uses);
        if (parsed.path == null) {
          result.add(parsed);
        } else {
          print("skipping $parsed – we don't support paths yet");
        }
      }
    }
  }

  return result;
}

extension on MapEntry<dynamic, dynamic> {
  List<dynamic> get steps =>
      (value as Map)['steps'] as yaml.YamlList? ?? const [];
}

Future<void> _withResolver(
  Future<void> Function(GitHubActionResolver) action,
) async {
  final resolver = GitHubActionResolver(github: createGitHubClient());

  try {
    await action(resolver);
  } finally {
    resolver.close();
  }
}

const _workflowsDir = '.github/workflows';
