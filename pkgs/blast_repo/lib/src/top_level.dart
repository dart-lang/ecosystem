// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blast_repo/src/tweaks/mono_repo_tweak.dart';
import 'package:git/git.dart';

import 'repo_tweak.dart';
import 'tweaks/auto_publish_tweak.dart';
import 'tweaks/dependabot_tweak.dart';
import 'tweaks/github_action_tweak.dart';
import 'tweaks/no_reponse_tweak.dart';
import 'utils.dart';

final allTweaks = Set<RepoTweak>.unmodifiable([
  AutoPublishTweak(),
  DependabotTweak(),
  GitHubActionTweak(),
  MonoRepoTweak(),
  NoResponseTweak(),
]);

Future<void> runFix({
  required String slug,
  required bool deleteTemp,
  required String? prReviewer,
  Iterable<RepoTweak>? tweaks,
}) async {
  await withSystemTemp(
    deleteTemp: deleteTemp,
    (tempDir, runKey) async {
      await cloneGitHubRepoToPath(slug, tempDir.path);

      final result = await fixAll(
        slug,
        tempDir,
        tweaks: tweaks,
      );

      final fixes = result.entries
          .where((element) => element.value.fixes.isNotEmpty)
          .map((e) => e.key.id)
          .toList()
        ..sort();

      if (fixes.isEmpty) {
        printHeader('No changes! All done!');
        return;
      }

      printHeader('Fixes:');
      for (var entry in result.entries) {
        print(entry.key.id);
        print(const JsonEncoder.withIndent(' ').convert(entry.value.fixes));
      }

      final gitDir = await GitDir.fromExisting(tempDir.path);

      await gitDir.exec(
        'Creating a working branch',
        ['checkout', '-b', runKey],
      );

      await gitDir.exec(
        'Add all files to index',
        ['add', '-v', '.'],
      );

      await gitDir.exec(
        'Commit changes',
        [
          'commit',
          '-am',
          '''
$packageName fixes

${fixes.join(', ')}
'''
        ],
      );

      await runProc(
        'Creating pull request',
        'gh',
        [
          'pr',
          'create',
          '--fill',
          '--title',
          'blast repo changes: ${fixes.join(', ')}',
          '--body',
          'This PR contains changes created by the blast repo tool.\n\n'
              '${fixes.map((fix) => '- `$fix`').join('\n')}',
          '--repo',
          slug,
          if (prReviewer != null) ...['--reviewer', prReviewer]
        ],
        workingDirectory: tempDir.path,
      );
    },
  );
}

Future<Map<RepoTweak, FixResult>> fixAll(
  String repoSlug,
  Directory checkout, {
  Iterable<RepoTweak>? tweaks,
}) async {
  tweaks ??=
      allTweaks.where((tweak) => tweak.shouldRunByDefault(checkout, repoSlug));

  return {
    for (var tweak in tweaks)
      tweak: await _safeRun(repoSlug, checkout, tweak.id, tweak.fix),
  };
}

Future<T> _safeRun<T>(
  String repoSlug,
  Directory checkout,
  String id,
  FutureOr<T> Function(Directory, String repoSlug) action,
) async {
  printHeader('Running "$id"');
  try {
    return await action(checkout, repoSlug);
  } catch (_) {
    printError('  Error running $id');
    rethrow;
  }
}
