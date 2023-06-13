// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';

class Changelog {
  final File file;

  Changelog(this.file);

  bool get exists => file.existsSync();

  String? get latestVersion {
    var input = latestHeading;

    if (input == null) {
      return null;
    }

    final versionRegex = RegExp(r'[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?');

    var match = versionRegex.firstMatch(input);

    if (match != null) {
      var version = match.group(0);
      return version;
    }
    return null;
  }

  String? get latestHeading {
    var sections = _parseSections();
    // Remove all leading "#"
    return sections.firstOrNull?.title.replaceAll(RegExp(r'^#*'), '').trim();
  }

  List<String> get latestChangeEntries {
    var sections = _parseSections();
    return sections.isEmpty ? [] : sections.first.entries;
  }

  Iterable<_Section> _parseSections() sync* {
    if (!exists) return;

    _Section? section;

    for (var line in file.readAsLinesSync().where((line) => line.isNotEmpty)) {
      if (line.startsWith('## ')) {
        if (section != null) yield section;

        section = _Section(line);
      } else if (section != null) {
        section.entries.add(line);
      }
    }

    if (section != null) yield section;
  }

  String get describeLatestChanges {
    var buf = StringBuffer();
    for (var entry in latestChangeEntries) {
      buf.writeln(entry);
    }
    return buf.toString();
  }
}

class _Section {
  final String title;
  final List<String> entries = [];

  _Section(this.title);
}
