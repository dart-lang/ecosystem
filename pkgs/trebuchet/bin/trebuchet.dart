// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

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
      'input-branch-name',
      help: 'The name of the main branch on the input repo',
      defaultsTo: 'main',
    )
    ..addOption(
      'target-branch-name',
      help: 'The name of the main branch on the target repo',
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
  String inputBranchName;
  String targetBranchName;
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
    inputBranchName = parsed.option('input-branch-name')!;
    targetBranchName = parsed.option('target-branch-name')!;
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
    inputBranchName: inputBranchName,
    targetBranchName: targetBranchName,
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
  final String inputBranchName;
  final String targetBranchName;
  final String gitFilterRepo;
  final bool dryRun;

  Trebuchet({
    required this.input,
    required this.inputPath,
    required this.target,
    required this.targetPath,
    required this.inputBranchName,
    required this.targetBranchName,
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

    print('Checkout correct branch at target repo');
    await runProcess('git', ['checkout', targetBranchName]);

    final prefix = 'pkgs';
    print('Rename to `$prefix/`');
    await filterRepo(['--path-rename', ':$prefix/$input/']);

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
        '${input}_package/$inputBranchName',
        '-m',
        'Merge package:$input into the $target monorepo',
      ],
    );

    print('Replace URI in pubspec');
    Pubspec? pubspec;
    if (!dryRun) {
      final pubspecFile =
          File(p.join(targetPath, prefix, input, 'pubspec.yaml'));
      final pubspecContents = await pubspecFile.readAsString();
      pubspec = Pubspec.parse(pubspecContents);
      final newPubspecContents = pubspecContents.replaceFirst(
        'repository: https://github.com/dart-lang/$input',
        'repository: https://github.com/dart-lang/$target/tree/$targetBranchName/$prefix/$input',
      );
      await pubspecFile.writeAsString(newPubspecContents);
    }

    print('Add issue template');
    final issueTemplateFile =
        File(p.join(targetPath, '.github', 'ISSUE_TEMPLATE', '$input.md'));
    final issueTemplateContents = '''
---
name: "package:$input"
about: "Create a bug or file a feature request against package:$input."
labels: "package:$input"
---''';
    if (!dryRun) {
      await issueTemplateFile.create(recursive: true);
      await issueTemplateFile.writeAsString(issueTemplateContents);
    }

    print('Remove CONTRIBUTING.md');
    if (!dryRun) {
      final contributingFile =
          File(p.join(targetPath, prefix, input, 'CONTRIBUTING.md'));
      if (await contributingFile.exists()) await contributingFile.delete();
    }

    print('Committing changes');
    await runProcess('git', ['add', '.']);
    await runProcess(
        'git', ['commit', '-m', 'Add issue template and other fixes']);

    final shouldPush = getInput('Push to remote? (y/N)');

    if (shouldPush) {
      print('Push to remote');
      await runProcess(
        'git',
        ['push', '--set-upstream', 'origin', 'merge-$input-package'],
      );
    }

    final remainingSteps = [
      if (!shouldPush)
        'run `git push --set-upstream origin merge-$input-package` in the monorepo directory',
      'Move and fix workflow files, labeler.yaml, and badges in the README.md',
      'Rev the version of the package, so that pub.dev points to the correct site',
      '''
Add a line to the changelog:
```
* Move to `dart-lang/$target` monorepo.
```
''',
      '''
Add the package to the top-level readme of the monorepo:
```
| [$input]($prefix/$input/) | ${pubspec?.description ?? ''} | [![package issues](https://img.shields.io/badge/issues-4774bc)](https://github.com/dart-lang/tools/issues?q=is%3Aissue+is%3Aopen+label%3Apackage%3A$input) | [![pub package](https://img.shields.io/pub/v/$input.svg)](https://pub.dev/packages/$input) |
```
''',
      "**Important!** Merge the PR with 'Create a merge commit' (enabling then disabling the `Allow merge commits` admin setting)",
      'Update the auto-publishing settings on https://pub.dev/packages/$input/admin',
      '''
Add the following text to https://github.com/dart-lang/$input/:'

```
> [!IMPORTANT]  
> This repo has moved to https://github.com/dart-lang/$target/tree/$targetBranchName/$prefix/$input
```
''',
      'Publish using the autopublish workflow',
      """Push tags to GitHub using
```
git tag --list '$input*' | xargs git push origin
```
""",
      '''
Close open PRs in dart-lang/$input with the following message:

```
Closing as the [dart-lang/$input](https://github.com/dart-lang/$input) repository is merged into the [dart-lang/$target](https://github.com/dart-lang/$target) monorepo. Please re-open this PR there!
```
      ''',
      '''Transfer issues by running
```
dart run pkgs/repo_manage/bin/report.dart transfer-issues --source-repo dart-lang/$input --target-repo dart-lang/$target --add-label package:$input --apply-changes
```
''',
      'Archive https://github.com/dart-lang/$input/',
    ];

    print('DONE!');
    print('''
Steps left to do:

${remainingSteps.map((step) => '- [ ] $step').join('\n')}
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
      print('  (not running; --dry-run is set)');
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
