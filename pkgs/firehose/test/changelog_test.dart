// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/changelog.dart';
import 'package:test/test.dart';

void main() {
  group('changelog', () {
    test('exists', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var exists = changelog.exists;
        expect(exists, isTrue);
      });
    });

    test('latestVersion', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, isNotNull);
      });
    });

    test('missing versions', () {
      withChangelog('''
- no
- versions
- mentioned here
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, isNull);
      });
    });

    test('latestChangeEntries', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var entries = changelog.latestChangeEntries;
        expect(entries, isNotEmpty);
      });
    });

    test('no recent entries', () {
      withChangelog('''
## 0.2.0-dev

## 0.1.0

- change 1
- change 2
''', (file) {
        var changelog = Changelog(file);
        var entries = changelog.latestChangeEntries;
        expect(entries, isEmpty);
      });
    });
  });
}

void withChangelog(String contents, void Function(File file) closure) {
  var dir = Directory.systemTemp.createTempSync();
  var file = File('${dir.path}/CHANGELOG.md');
  try {
    file.writeAsStringSync(contents);
    closure(file);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

const _defaultContents = '''
## 0.3.7+1

- Fix an issue in the `.github/workflows/publish.yaml` workflow file.

## 0.3.7

- Provide feedback about publishing status as PR comments.
''';
