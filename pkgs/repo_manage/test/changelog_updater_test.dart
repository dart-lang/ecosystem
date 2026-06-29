import 'dart:io';

import 'package:repo_manage/changelog_updater.dart';
import 'package:test/test.dart';

void main() {
  group('updateChangelogContent', () {
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
  });
}

void expectGolden({
  required String inputPath,
  required String goldenPath,
  required String message,
}) {
  final input = File(inputPath).readAsStringSync();
  final output = updateChangelogContent(input, message);
  final goldenFile = File(goldenPath);

  if (!goldenFile.existsSync()) {
    goldenFile.parent.createSync(recursive: true);
    goldenFile.writeAsStringSync(output);
    return;
  }

  expect(output, goldenFile.readAsStringSync());
}
