// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
@TestOn('vm')
library;

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

    test('latestHeading', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var heading = changelog.latestHeading;
        expect(heading, '0.3.7+1');
      });
    });

    test('Custom heading extraction', () {
      withChangelog('''
## 1.2.3+4 is the new version ## :) 
''', (file) {
        var changelog = Changelog(file);
        var heading = changelog.latestHeading;
        expect(heading, '1.2.3+4 is the new version ## :)');
      });
    });

    test('latestVersion', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '0.3.7+1');
      });
    });

    test('on digit version + x', () {
      withChangelog('''
## 1.2.3+4
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '1.2.3+4');
      });
    });

    test('multi digit version + x', () {
      withChangelog('''
## 123.456.789+123456789
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '123.456.789+123456789');
      });
    });

    test('no "+ x" at the end', () {
      withChangelog('''
## 123.456.789
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '123.456.789');
      });
    });

    test('with prerelease tag', () {
      withChangelog('''
## 123.456.789-wip
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '123.456.789-wip');
      });
    });

    test('custom heading version', () {
      withChangelog('''
## [4.7.0](https://github.com/...) (2023-05-06)
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '4.7.0');
      });
    });

    test('multiple versions mentioned', () {
      withChangelog('''
## [4.7.0](https://github.com/.../.../compare/v4.6.0...v4.7.0) (25.05.23)
''', (file) {
        var changelog = Changelog(file);
        var version = changelog.latestVersion;
        expect(version, '4.7.0');
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

    test('no changelog file', () {
      var changelog = Changelog(File('missing_changelog.md'));
      expect(changelog.exists, false);
      expect(changelog.latestVersion, isNull);
      expect(changelog.latestChangeEntries, isEmpty);
    });

    test('latestChangeEntries', () {
      withChangelog(_defaultContents, (file) {
        var changelog = Changelog(file);
        var entries = changelog.latestChangeEntries;
        expect(entries, isNotEmpty);
      });
    });

    test('describeLatestChanges', () {
      withChangelog(_multiLineContents, (file) {
        var changelog = Changelog(file);
        var description = changelog.describeLatestChanges;
        expect(description, '''
- Fix issue 1.
- Fix issue 2.''');
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

const _multiLineContents = '''
## 0.3.6

- Fix issue 1.
- Fix issue 2.

## 0.3.5

- Provide feedback about publishing status as PR comments.
''';
