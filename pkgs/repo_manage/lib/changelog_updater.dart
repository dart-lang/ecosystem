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

final _bulletLinePattern = RegExp(r'^[-*] (.*)$');

bool _isBulletContinuation(String line) =>
    line.trim().isNotEmpty && (line.startsWith('  ') || line.startsWith('\t'));

List<String>? _replaceMatchingBullets(
  List<String> bodyLines,
  String message,
  RegExp replacePattern,
) {
  final updated = <String>[];
  var replaced = false;

  for (var i = 0; i < bodyLines.length;) {
    final firstMatch = _bulletLinePattern.firstMatch(bodyLines[i]);
    if (firstMatch == null) {
      updated.add(bodyLines[i]);
      i++;
      continue;
    }

    var end = i + 1;
    while (end < bodyLines.length && _isBulletContinuation(bodyLines[end])) {
      end++;
    }

    final parts = [
      firstMatch.group(1)!.trim(),
      ...bodyLines.sublist(i + 1, end).map((line) => line.trim()),
    ];
    if (!replacePattern.hasMatch(parts.join(' '))) {
      updated.addAll(bodyLines.sublist(i, end));
    } else if (!replaced) {
      updated.add('- $message');
      replaced = true;
    }
    i = end;
  }

  return replaced ? updated : null;
}

({Version version, int lineIndex})? _findCurrentVersion(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('## ')) continue;
    final token = line.substring(3).trim().split(' ').first;
    try {
      return (version: Version.parse(token), lineIndex: i);
    } on FormatException {
      // Ignore non-SemVer level-2 headings.
    }
  }
  return null;
}

void updateChangelog({
  required File changelogFile,
  required String message,
  RegExp? replacePattern,
}) {
  final changelogContent = changelogFile.readAsStringSync();
  final lines = LineSplitter.split(changelogContent).toList();
  final current = _findCurrentVersion(lines);

  final output = <String>[];
  if (current != null && current.version.isWip) {
    final nextHeading = lines.indexWhere(
      (line) => line.startsWith('## '),
      current.lineIndex + 1,
    );
    final sectionEnd = switch (nextHeading) {
      -1 => lines.length,
      final idx when lines[idx - 1].trim().isEmpty => idx - 1,
      final idx => idx,
    };
    final bodyStart = current.lineIndex + 1;
    final replacedBody = replacePattern == null
        ? null
        : _replaceMatchingBullets(
            lines.sublist(bodyStart, sectionEnd),
            message,
            replacePattern,
          );
    if (replacedBody != null) {
      output
        ..addAll(lines.take(bodyStart))
        ..addAll(replacedBody)
        ..addAll(lines.skip(sectionEnd));
    } else {
      output
        ..addAll(lines.take(sectionEnd))
        ..add('- $message')
        ..addAll(lines.skip(sectionEnd));
    }
  } else {
    final newVersion = _nextWipVersion(current?.version).toString();
    output.addAll([
      '## $newVersion',
      '',
      '- $message',
      '',
      ...lines,
    ]);

    final changelogDir = path.dirname(changelogFile.path);
    final pubspecFile = File(path.join(changelogDir, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      updatePubspecVersion(pubspecFile, newVersion);
    }
  }

  changelogFile.writeAsStringSync('${output.join('\n')}\n');
}

class ChangelogUpdaterCommand extends ReportCommand {
  ChangelogUpdaterCommand()
      : super('changelog', 'Update a changelog with a new entry.') {
    argParser
      ..addOption(
        'changelog',
        abbr: 'c',
        help: 'Path to the changelog file to update. Defaults to CHANGELOG.md.',
      )
      ..addOption(
        'replace-pattern',
        help: 'Regular expression matched against existing bullet text in an '
            'active -wip section; matching entries are replaced in place '
            'instead of appending a new bullet.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults?.rest ?? const <String>[];
    if (args.isEmpty) {
      stderr
        ..writeln(
          'Usage: dart run report.dart changelog [--changelog <path>] '
          '[--replace-pattern <regex>] "Your changelog message"',
        )
        ..writeln('If no --changelog path is provided, CHANGELOG.md is used.');
      return 1;
    }

    RegExp? replacePattern;
    final replacePatternArg = argResults?['replace-pattern'] as String?;
    if (replacePatternArg != null) {
      try {
        replacePattern = RegExp(replacePatternArg);
      } on FormatException catch (e) {
        stderr.writeln('Error: Invalid --replace-pattern: ${e.message}');
        return 1;
      }
    }

    final message = args.join(' ');

    final changelogFile =
        File(argResults?['changelog'] as String? ?? 'CHANGELOG.md');

    if (!changelogFile.existsSync()) {
      stderr.writeln('Error: ${changelogFile.path} not found.');
      return 1;
    }

    updateChangelog(
      changelogFile: changelogFile,
      message: message,
      replacePattern: replacePattern,
    );
    stdout.writeln('Changelog updated successfully.');
    return 0;
  }
}
