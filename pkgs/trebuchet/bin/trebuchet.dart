// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: lines_longer_than_80_chars

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
      'target',
      help: 'Name of the mono-repo',
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
      'dry-run',
      help: 'Do not actually execute any of the steps',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Prints usage info',
      negatable: false,
    );

  String input;
  String inputPath;
  String target;
  String targetPath;
  String branchName;
  String gitFilterRepo;
  bool dryRun;
  try {
    final parsed = argParser.parse(arguments);
    if (parsed.flag('help')) {
      print(argParser.usage);
      exit(0);
    }

    input = parsed.option('input-name')!;
    inputPath = parsed.option('input-path')!;
    target = parsed.option('target')!;
    targetPath = parsed.option('target-path')!;
    branchName = parsed.option('branch-name')!;
    gitFilterRepo = parsed.option('git-filter-repo')!;
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
    target: target,
    targetPath: targetPath,
    branchName: branchName,
    gitFilterRepo: gitFilterRepo,
    dryRun: dryRun,
  );

  await trebuchet.hurl();
}

class Trebuchet {
  final String input;
  final String inputPath;
  final String target;
  final String targetPath;
  final String branchName;
  final String gitFilterRepo;
  final bool dryRun;

  Trebuchet({
    required this.input,
    required this.inputPath,
    required this.target,
    required this.targetPath,
    required this.branchName,
    required this.gitFilterRepo,
    required this.dryRun,
  });

  Future<void> hurl() async {
    print('Check existence of python3 on path');
    await runProcess(
      'python3',
      ['--version'],
      inTarget: false,
    );

    print('Start moving package');

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
        'Merge package:$input into shared $target repository'
      ],
    );

    final shouldPush = getInput('Push to remote? (y/N)');

    if (shouldPush) {
      print('Push to remote');
      await runProcess(
        'git',
        ['push', '--set-upstream', 'origin', 'merge-$input-package'],
      );
    }

    final remainingSteps = [
      'Move and fix workflow files',
      if (!shouldPush)
        'Run `git push --set-upstream origin merge-$input-package` in the monorepo directory',
      'Disable squash-only in GitHub settings, and merge with a fast forward merge to the main branch, enable squash-only in GitHub settings.',
      "Push tags to github using `git tag --list '$input*' | xargs git push origin`",
      'Follow up with a PR adding links to the top-level readme table.',
      'Transfer issues by running `dart run pkgs/repo_manage/bin/report.dart transfer-issues --source-repo dart-lang/$input --target-repo dart-lang/$target --add-label package:$input --apply-changes`',
      "Add a commit to https://github.com/dart-lang/$input/ with it's readme pointing to the monorepo.",
      'Update the auto-publishing settings on pub.dev/packages/$input.',
      'Archive https://github.com/dart-lang/$input/.',
    ];

    print('DONE!');
    print('''
Steps left to do:

${remainingSteps.map((step) => '  - $step').join('\n')}
''');
  }

  bool getInput(String question) {
    print(question);
    final line = stdin.readLineSync()?.toLowerCase();
    return line == 'y' || line == 'yes';
  }

  Future<void> runProcess(
    String executable,
    List<String> arguments, {
    bool inTarget = true,
    bool overrideDryRun = false,
  }) async {
    final workingDirectory = inTarget ? targetPath : inputPath;
    print('');
    print('${bold('$executable ${arguments.join(' ')}')} '
        '${subtle('[$workingDirectory]')}');
    if (!dryRun || overrideDryRun) {
      final processResult = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      final out = processResult.stdout as String;
      if (out.isNotEmpty) {
        print(indent(out).trimRight());
      }
      final err = processResult.stderr as String;
      if (err.isNotEmpty) {
        print(indent(err).trimRight());
      }
      if (processResult.exitCode != 0) {
        throw ProcessException(executable, arguments);
      }
    } else {
      print('  not running; --dry-run is set.');
    }
    print('');
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

String bold(String str) => '\u001b[1m$str\u001b[22m';

String subtle(String str) => '\u001b[2m$str\u001b[22m';

String indent(String str) =>
    str.split('\n').map((line) => '  $line').join('\n');
