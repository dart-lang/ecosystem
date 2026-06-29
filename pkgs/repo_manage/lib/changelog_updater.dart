// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'src/common.dart';

String updateChangelogContent(String changelog, String message) {
  final lines = LineSplitter.split(changelog).toList();
  var currentVersion = '0.0.1';
  var currentVersionLine = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('## ')) {
      final content = line.substring(3).trim();
      final version = content.split(' ').first;
      if (version.startsWith(RegExp(r'\d'))) {
        currentVersion = version;
        currentVersionLine = i;
        break;
      }
    }
  }

  final isWip = currentVersion.endsWith('-wip');

  final output = <String>[];
  if (isWip) {
    var sectionEnd = lines.indexWhere(
            (line) => line.startsWith('## '), currentVersionLine + 1) -
        1;
    if (sectionEnd < 0) {
      sectionEnd = lines.length;
    }

    output.addAll(lines.take(sectionEnd));
    output.add('- $message');
    output.addAll(lines.skip(sectionEnd));
  } else {
    output.addAll([
      '## $currentVersion-wip',
      '',
      '- $message',
      '',
      ...lines,
    ]);
  }

  return '${output.join('\n')}\n';
}

class ChangelogUpdaterCommand extends ReportCommand {
  ChangelogUpdaterCommand()
      : super('changelog', 'Update a changelog with a new entry.') {
    argParser.addOption(
      'changelog',
      abbr: 'c',
      help: 'Path to the changelog file to update. Defaults to CHANGELOG.md.',
    );
  }

  @override
  Future<int> run() async {
    final args = argResults?.rest ?? const <String>[];
    if (args.isEmpty) {
      stderr.writeln('''
Usage: dart run report.dart changelog [--changelog <path>] "Your changelog message"''');
      stderr
          .writeln('If no --changelog path is provided, CHANGELOG.md is used.');
      return 1;
    }

    final message = args.join(' ');
    final changelogFile =
        File(argResults?['changelog'] as String? ?? 'CHANGELOG.md');

    if (!changelogFile.existsSync()) {
      stderr.writeln('Error: ${changelogFile.path} not found.');
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
