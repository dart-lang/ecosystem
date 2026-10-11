// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

class Changelog {
  static const _headerLinePrefix = '## ';

  final File file;
  final bool exists;
  final List<_Section> _sections;

  /// Reads [file] and parses it into sections.
  factory Changelog(File file) {
    if (!file.existsSync()) {
      return Changelog._(file, false, const <_Section>[]);
    }
    final lines = file.readAsLinesSync();
    final sections = _parseSections(lines);
    return Changelog._(file, true, sections);
  }

  Changelog._(this.file, this.exists, this._sections);

  /// Pattern recognizing some SemVer formats.
  ///
  /// Accepts:
  ///
  /// > digits '.' digits '.' digits
  ///
  /// optionally followed by `-` or `+` character and one of more non-whitespace
  /// characters, without validating them as valid semver.
  ///
  /// This is not all complete SemVer version strings but it should be enough
  /// for the user-cases we need it for in this package.
  static final _versionRegex = RegExp(r'\d+\.\d+\.\d+(?:[+\-]\S*)?');

  String? get latestVersion {
    final input = latestHeading;

    if (input != null) {
      final match = _versionRegex.firstMatch(input);
      if (match != null) {
        final version = match[0];
        return version;
      }
    }

    return null;
  }

  String? get latestHeading {
    final section = _sections.firstOrNull;
    if (section == null) return null;
    // Remove the leading `_headerLinePrefix`, then trim left-over whitespace.
    final title = section.title;
    assert(title.startsWith(_headerLinePrefix));
    return title.substring(_headerLinePrefix.length).trim();
  }

  List<String> get latestChangeEntries =>
      _sections.firstOrNull?.entries ?? const <String>[];

  static List<_Section> _parseSections(List<String> lines) {
    final sections = <_Section>[];

    _Section? section;

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith(_headerLinePrefix)) {
        if (section != null) sections.add(section);
        section = _Section(line);
      } else {
        section?.entries.add(line);
      }
    }
    if (section != null) sections.add(section);

    return sections;
  }

  String get describeLatestChanges => latestChangeEntries.join('\n');

  static final _hunkHeaderRegex =
      RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@');

  /// Returns whether [patch] (a unified diff for this changelog file) adds or
  /// removes at least one line within the top `## ...` section.
  ///
  /// Returns `true` if [patch] is `null`, empty, contains no hunk headers, or
  /// if the changelog has no sections yet.
  bool patchTouchesLatestSection(String? patch) {
    if (patch == null || patch.isEmpty || !exists) return true;
    final lines = file.readAsLinesSync();
    int? firstHeaderLine;
    var secondHeaderLine = lines.length + 1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith(_headerLinePrefix)) {
        if (firstHeaderLine == null) {
          firstHeaderLine = i + 1;
        } else {
          secondHeaderLine = i + 1;
          break;
        }
      }
    }
    if (firstHeaderLine == null) return true;

    var sawHunk = false;
    var currentNewLine = 0;
    for (final line in patch.split('\n')) {
      final match = _hunkHeaderRegex.firstMatch(line);
      if (match != null) {
        sawHunk = true;
        currentNewLine = int.parse(match.group(1)!);
        continue;
      }
      if (!sawHunk) continue;
      if (line.startsWith('+') && !line.startsWith('+++')) {
        if (currentNewLine >= firstHeaderLine &&
            currentNewLine < secondHeaderLine) {
          return true;
        }
        currentNewLine++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        final isDeletedSectionHeader =
            line.substring(1).startsWith(_headerLinePrefix);
        if (currentNewLine >= firstHeaderLine &&
            (currentNewLine < secondHeaderLine ||
                (currentNewLine == secondHeaderLine &&
                    !isDeletedSectionHeader))) {
          return true;
        }
      } else if (line.startsWith(' ')) {
        currentNewLine++;
      }
    }
    return !sawHunk;
  }
}

class _Section {
  final String title;
  final List<String> entries = [];

  _Section(this.title);
}
