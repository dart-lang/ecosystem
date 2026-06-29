// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'src/common.dart';

String updateChangelogContent(String changelog, String message) {
  final lines = LineSplitter.split(changelog).toList();
  var currentVersion = '0.0.1';

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('## ')) {
      final content = line.substring(3).trim();
      final version = content.split(' ').first;
      if (version.startsWith(RegExp(r'\d'))) {
        currentVersion = version;
        break;
      }
    }
  }

  final output = <String>[];

  final isWip = currentVersion.endsWith('-wip');

  if (isWip) {
    output.add('- $message');
    output.addAll(lines);
  } else {
    final newVersion = '$currentVersion-wip';
    output.add('## $newVersion');
    output.add('- $message');
    output.add('');
    output.addAll(lines);
  }

  return '${output.join('\n')}\n';
}

class ChangelogUpdaterCommand extends ReportCommand {
  ChangelogUpdaterCommand()
      : super('changelog', 'Update a changelog with a new entry.');

  @override
  Future<int> run() async {
    final args = argResults?.rest ?? const <String>[];
    if (args.isEmpty) {
      stderr.writeln(
          'Usage: dart run pkgs/repo_manage/bin/report.dart changelog "Your changelog message"');
      return 1;
    }

    final message = args.join(' ');
    final changelogFile = File('CHANGELOG.md');

    if (!changelogFile.existsSync()) {
      stderr.writeln('Error: CHANGELOG.md not found.');
      return 1;
    }

    final newChangelog = updateChangelogContent(
      changelogFile.readAsStringSync(),
      message,
    );
    changelogFile.writeAsStringSync(newChangelog);
    stdout.writeln('Changelog updated successfully.');
    return 0;
  }
}
