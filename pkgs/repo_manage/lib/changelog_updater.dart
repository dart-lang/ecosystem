// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import 'src/common.dart';

extension on Version {
  bool get isWip =>
      isPreRelease &&
      switch (preRelease.last) {
        final String s => s == 'wip' || s.endsWith('-wip'),
        _ => false,
      };
}

Version _nextWipVersion(Version? current) {
  if (current == null) return Version(0, 0, 1, pre: 'wip');
  if (current.isPreRelease) {
    return Version(
      current.major,
      current.minor,
      current.patch,
      pre: '${current.preRelease.join('.')}-wip',
    );
  }
  final next = current.nextPatch;
  return Version(next.major, next.minor, next.patch, pre: 'wip');
}

void updatePubspecVersion(File pubspecFile, String newVersion) {
  final content = pubspecFile.readAsStringSync();
  final lines = LineSplitter.split(content).toList();
  var updated = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('version:')) {
      lines[i] = 'version: $newVersion';
      updated = true;
      break;
    }
  }
  if (updated) {
    pubspecFile.writeAsStringSync('${lines.join('\n')}\n');
  }
}

void updateChangelog({
  required File changelogFile,
  required String message,
}) {
  final changelogContent = changelogFile.readAsStringSync();
  final lines = LineSplitter.split(changelogContent).toList();
  Version? currentVersion;
  var currentVersionLine = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('## ')) {
      final token = line.substring(3).trim().split(' ').first;
      try {
        currentVersion = Version.parse(token);
        currentVersionLine = i;
        break;
      } on FormatException {
        // Ignore non-SemVer level-2 headings.
      }
    }
  }

  final output = <String>[];
  if (currentVersion != null && currentVersion.isWip) {
    var sectionEnd = lines.indexWhere(
            (line) => line.startsWith('## '), currentVersionLine + 1) -
        1;
    if (sectionEnd < 0) {
      sectionEnd = lines.length;
    }

    output.addAll(lines.take(sectionEnd));
    output.add('- $message');
    output.addAll(lines.skip(sectionEnd));
    changelogFile.writeAsStringSync('${output.join('\n')}\n');
  } else {
    final newVersion = _nextWipVersion(currentVersion).toString();
    output.addAll([
      '## $newVersion',
      '',
      '- $message',
      '',
      ...lines,
    ]);
    changelogFile.writeAsStringSync('${output.join('\n')}\n');

    final changelogDir = path.dirname(changelogFile.path);
    final pubspecFile = File(path.join(changelogDir, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      updatePubspecVersion(pubspecFile, newVersion);
    }
  }
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

    updateChangelog(changelogFile: changelogFile, message: message);
    stdout.writeln('Changelog updated successfully.');
    return 0;
  }
}
