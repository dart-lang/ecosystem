import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';

import 'repo_tweak.dart';
import 'tweaks/dependabot_tweak.dart';
import 'tweaks/github_action_tweak.dart';
import 'tweaks/no_reponse_tweak.dart';
import 'utils.dart';

final allTweaks = Set<RepoTweak>.unmodifiable([
  DependabotTweak(),
  GitHubActionTweak(),
  NoResponseTweak(),
]);

Future<void> runFix({
  required String slug,
  required bool deleteTemp,
  required bool onlyStable,
  required String? prReviewer,
}) async {
  await withSystemTemp(
    deleteTemp: deleteTemp,
    (tempDir, runKey) async {
      await cloneGitHubRepoToPath(slug, tempDir.path);

      final result = await fixAll(tempDir, onlyStable: onlyStable);

      final fixes = result.entries
          .where((element) => element.value.fixes.isNotEmpty)
          .map((e) => e.key.name)
          .toList()
        ..sort();

      if (fixes.isEmpty) {
        printHeader('No changes! All done!');
        return;
      }

      printHeader('Fixes:');
      for (var entry in result.entries) {
        print(entry.key.name);
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

${fixes.join('\n')}
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
  Directory checkout, {
  Iterable<RepoTweak>? tweaks,
  required bool onlyStable,
}) async =>
    {
      for (var tweak in tweaks.orAll(onlyStable: onlyStable))
        tweak: await _safeRun(checkout, tweak.name, tweak.fix),
    };

Future<T> _safeRun<T>(
  Directory checkout,
  String description,
  FutureOr<T> Function(Directory) action,
) async {
  printHeader('Running "$description"');
  try {
    return await action(checkout);
  } catch (_) {
    printError('  Error running $description');
    rethrow;
  }
}

extension on Iterable<RepoTweak>? {
  Iterable<RepoTweak> orAll({required bool onlyStable}) =>
      (this ?? allTweaks).where((element) => !onlyStable || element.stable);
}
