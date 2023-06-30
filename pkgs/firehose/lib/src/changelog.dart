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
    var lines = file.readAsLinesSync();
    var sections = _parseSections(lines);
    return Changelog._(file, true, sections);
  }

  Changelog._(this.file, this.exists, this._sections);

  /// Pattern recognizing some SemVer formats.
  ///
  /// Accepts:
  /// >  digits '.' digits '.' digits
  ///
  /// optionally followed by `-` or `+` character
  /// and one or more "word characters", which are
  /// ASCII letters (`a`-`z`, `A`-`Z`), digits (`0`-`9`),
  /// underscore (`_`) and dollar-sign (`$`).
  ///
  /// This is not all complete SemVer version strings,
  /// since it doesn't allow `.` in the continuation,
  /// or a `+...` sequence after a `-` sequence.
  /// It should be enough for the user-cases we need it for
  /// in this package.
  static final _versionRegex = RegExp(r'\d+\.\d+\.\d+(?:[\-+]\w+)?');

  String? get latestVersion {
    var input = latestHeading;

    if (input != null) {
      var match = _versionRegex.firstMatch(input);
      if (match != null) {
        var version = match[0];
        return version;
      }
    }

    return null;
  }

  String? get latestHeading {
    var section = _sections.firstOrNull;
    if (section == null) return null;
    // Remove the leading `_headerLinePrefix`, then trim left-over whitespace.
    var title = section.title;
    assert(title.startsWith(_headerLinePrefix));
    return title.substring(_headerLinePrefix.length).trim();
  }

  List<String> get latestChangeEntries =>
      _sections.firstOrNull?.entries ?? const <String>[];

  static List<_Section> _parseSections(List<String> lines) {
    var sections = <_Section>[];

    _Section? section;

    for (var line in lines) {
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

  String get describeLatestChanges => latestChangeEntries.join();
}

class _Section {
  final String title;
  final List<String> entries = [];

  _Section(this.title);
}
