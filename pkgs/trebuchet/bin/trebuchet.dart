// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final argParser = ArgParser()
    ..addOption(
      'input-name',
      help: 'Name of the package which should be transferred to a mono-repo',
    )
    ..addOption(
      'input-path',
      help: 'Path to the package which should be transferred to a mono-repo',
    )
    ..addOption(
      'target-path',
      help: 'Path to the mono-repo',
    )
    ..addOption(
      'branch-name',
      help: 'The name of the main branch on the input repo',
      defaultsTo: 'main',
    )
    ..addOption(
      'git-filter-repo',
      help: 'Path to the git-filter-repo tool',
    )
    ..addFlag(
      'push',
      help: 'Whether to push the branch to remote',
      defaultsTo: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Prints usage info',
      negatable: false,
    )
    ..addFlag(
      'dry-run',
      help: 'Do not actually execute any of the steps',
      defaultsTo: false,
    );

  String input;
  String inputPath;
  String targetPath;
  String branchName;
  String gitFilterRepo;
  bool push;
  bool dryRun;
  try {
    final parsed = argParser.parse(arguments);
    if (parsed.flag('help')) {
      print(argParser.usage);
      exit(0);
    }

    input = parsed['input-name'] as String;
    inputPath = parsed['input-path'] as String;
    targetPath = parsed['target-path'] as String;
    branchName = parsed['branch-name'] as String;
    gitFilterRepo = parsed['git-filter-repo'] as String;
    push = parsed.flag('push');
    dryRun = parsed.flag('dry-run');
  } catch (e) {
    print(e);
    print('');
    print(argParser.usage);
    exit(1);
  }

  final trebuchet = Trebuchet(
    input: input,
    inputPath: inputPath,
    targetPath: targetPath,
    branchName: branchName,
    gitFilterRepo: gitFilterRepo,
    push: push,
    dryRun: dryRun,
  );

  await trebuchet.hurl();
}

class Trebuchet {
  final String input;
  final String inputPath;
  final String targetPath;
  final String branchName;
  final String gitFilterRepo;
  final bool push;
  final bool dryRun;

  Trebuchet({
    required this.input,
    required this.inputPath,
    required this.targetPath,
    required this.branchName,
    required this.gitFilterRepo,
    required this.push,
    required this.dryRun,
  });

  Future<void> hurl() async {
    print('Rename to `pkgs/`');
    await filterRepo(['--path-rename', ':pkgs/$input/']);

    print('Prefix tags');
    await filterRepo(['--tag-rename', ':$input-']);

    print('Replace issue references in commit messages');
    await inTempDir((tempDirectory) async {
      final regexFile = File(p.join(tempDirectory.path, 'expressions.txt'));
      await regexFile.create();
      await regexFile.writeAsString('regex:#(\\d)==>dart-lang/$input#\\1');
      await filterRepo(['--replace-message', regexFile.path]);
    });

    print('Create branch at target');
    await runProcess('git', ['checkout', '-b', 'merge-$input-package']);

    print('Add a remote for the local clone of the moving package');
    await runProcess(
      'git',
      ['remote', 'add', '${input}_package', inputPath],
    );
    await runProcess('git', ['fetch', '${input}_package']);

    print('Merge branch into monorepo');
    await runProcess(
      'git',
      [
        'merge',
        '--allow-unrelated-histories',
        '${input}_package/$branchName',
        '-m',
        'Merge package:$input into shared tool repository'
      ],
    );

    if (push) {
      print('Push to remote');
      await runProcess(
        'git',
        ['push', '--set-upstream', 'origin', 'merge-$input-package'],
      );
    }

    print('DONE!');
    print('''
Steps left to do:

- Move and fix workflow files
${push ? '' : '- Run `git push --set-upstream origin merge-$input-package` in the monorepo directory'}
- Disable squash-only in GitHub settings, and merge with a fast forward merge to the main branch, enable squash-only in GitHub settings.
- Push tags to github using `git tag --list '$input*' | xargs git push origin`
- Follow up with a PR adding links to the top-level readme table.
- Add a commit to https://github.com/dart-lang/$input/ with it's readme pointing to the monorepo.
- Update the auto-publishing settings on pub.dev/packages/$input.
- Archive https://github.com/dart-lang/$input/.
''');
  }

  Future<void> runProcess(
    String executable,
    List<String> arguments, {
    bool inTarget = true,
  }) async {
    final workingDirectory = inTarget ? targetPath : inputPath;
    print('----------');
    print('Running `$executable $arguments` in $workingDirectory');
    if (!dryRun) {
      final processResult = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      print('stdout:');
      print(processResult.stdout);
      if ((processResult.stderr as String).isNotEmpty) {
        print('stderr:');
        print(processResult.stderr);
      }
      if (processResult.exitCode != 0) {
        throw ProcessException(executable, arguments);
      }
    } else {
      print('Not running, as --dry-run is set.');
    }
    print('==========');
  }

  Future<void> filterRepo(List<String> args) async {
    await runProcess(
      'python3',
      [p.relative(gitFilterRepo, from: inputPath), ...args],
      inTarget: false,
    );
  }
}

Future<void> inTempDir(Future<void> Function(Directory temp) f) async {
  final tempDirectory = await Directory.systemTemp.createTemp();
  await f(tempDirectory);
  await tempDirectory.delete(recursive: true);
}
