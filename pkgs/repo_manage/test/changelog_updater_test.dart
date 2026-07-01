// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:repo_manage/changelog_updater.dart';
import 'package:test/test.dart';

void main() {
  group('updateChangelog', () {
    test('adds an entry to a wip changelog', () {
      expectGolden(
        inputPath: 'test/data/changelog_wip.md',
        goldenPath: 'test/data/golden/changelog_wip.golden',
        message: 'Add new feature',
      );
    });

    test('creates a new wip section from a released changelog', () {
      expectGolden(
        inputPath: 'test/data/changelog_release.md',
        goldenPath: 'test/data/golden/changelog_release.golden',
        message: 'Fix regression',
      );
    });

    test('creates a starter changelog when none is present', () {
      expectGolden(
        inputPath: 'test/data/changelog_empty.md',
        goldenPath: 'test/data/golden/changelog_empty.golden',
        message: 'Initial entry',
      );
    });

    test('handles complex timezone formatting', () {
      expectGolden(
        inputPath: 'test/data/changelog_complex_timezone.md',
        goldenPath: 'test/data/golden/changelog_complex_timezone.golden',
        message: 'Add new feature',
      );
    });

    test('handles complex timezone formatting with WIP suffix', () {
      expectGolden(
        inputPath: 'test/data/changelog_complex_timezone_wip.md',
        goldenPath: 'test/data/golden/changelog_complex_timezone_wip.golden',
        message: 'Add new feature',
      );
    });
  });

  group('updatePubspecVersion', () {
    test('updates version line', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final pubspecFile = File('${tempDir.path}/pubspec.yaml');
      pubspecFile.writeAsStringSync('''
name: my_package
version: 1.0.0
dependencies:
  path: ^1.8.0
''');

      updatePubspecVersion(pubspecFile, '1.0.1-wip');

      expect(pubspecFile.readAsStringSync(), '''
name: my_package
version: 1.0.1-wip
dependencies:
  path: ^1.8.0
''');
      tempDir.deleteSync(recursive: true);
    });
  });

  group('updateChangelog (with pubspec)', () {
    test('updates pubspec if transitioned to WIP', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final changelogFile = File('${tempDir.path}/CHANGELOG.md');
      final pubspecFile = File('${tempDir.path}/pubspec.yaml');

      changelogFile.writeAsStringSync('''
## 1.0.0

- Released version
''');
      pubspecFile.writeAsStringSync('''
name: my_package
version: 1.0.0
''');

      updateChangelog(changelogFile: changelogFile, message: 'New WIP change');

      expect(changelogFile.readAsStringSync(), '''
## 1.0.0-wip

- New WIP change

## 1.0.0

- Released version
''');

      expect(pubspecFile.readAsStringSync(), '''
name: my_package
version: 1.0.0-wip
''');
      tempDir.deleteSync(recursive: true);
    });

    test('does not update pubspec if already WIP', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final changelogFile = File('${tempDir.path}/CHANGELOG.md');
      final pubspecFile = File('${tempDir.path}/pubspec.yaml');

      changelogFile.writeAsStringSync('''
## 1.0.0-wip

- WIP change

## 1.0.0

- Released version
''');
      pubspecFile.writeAsStringSync('''
name: my_package
version: 1.0.0-wip
''');

      updateChangelog(
          changelogFile: changelogFile, message: 'Another WIP change');

      expect(changelogFile.readAsStringSync(), '''
## 1.0.0-wip

- WIP change
- Another WIP change

## 1.0.0

- Released version
''');

      expect(pubspecFile.readAsStringSync(), '''
name: my_package
version: 1.0.0-wip
''');
      tempDir.deleteSync(recursive: true);
    });
  });
}

void expectGolden({
  required String inputPath,
  required String goldenPath,
  required String message,
}) {
  final tempDir = Directory.systemTemp.createTempSync();
  final tempChangelog = File(path.join(tempDir.path, 'CHANGELOG.md'));
  tempChangelog.writeAsStringSync(File(inputPath).readAsStringSync());

  updateChangelog(changelogFile: tempChangelog, message: message);

  final output = tempChangelog.readAsStringSync();
  final goldenFile = File(goldenPath);

  if (!goldenFile.existsSync()) {
    goldenFile.parent.createSync(recursive: true);
    goldenFile.writeAsStringSync(output);
    tempDir.deleteSync(recursive: true);
    return;
  }

  expect(output, goldenFile.readAsStringSync());
  tempDir.deleteSync(recursive: true);
}
