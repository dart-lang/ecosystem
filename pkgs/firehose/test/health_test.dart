// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/health.dart';

Future<void> main() async {
  late final Directory directory;
  late final ManualFileApi Function(List<GitFile> additional) fakeGithubApi;

  setUpAll(() async {
    directory = Directory(p.join('test_data', 'test_repo'));
    fakeGithubApi = (List<GitFile> additional) => ManualFileApi(
          prBody: '',
          prLabels: [],
          files: [
            GitFile(
              'pkgs/package1/bin/package1.dart',
              FileStatus.modified,
              directory,
            ),
            GitFile(
              'pkgs/package2/lib/anotherLib.dart',
              FileStatus.added,
              directory,
            ),
            GitFile(
              'pkgs/package2/someImage.png',
              FileStatus.added,
              directory,
            ),
            GitFile(
              'pkgs/package5/lib/src/package5_base.dart',
              FileStatus.modified,
              directory,
            ),
            GitFile(
              'pkgs/package5/pubspec.yaml',
              FileStatus.modified,
              directory,
            ),
            ...additional
          ],
        );

    await Process.run('dart', ['pub', 'global', 'activate', 'dart_apitool']);
    await Process.run('dart', ['pub', 'global', 'activate', 'coverage']);
  });

  for (var check in Check.values) {
    test(
      'Check health workflow "${check.name}" against golden files',
      () async => await checkGolden(
        check,
        fakeGithubApi([]),
        directory,
      ),
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Check health workflow "${check.name}" against golden files '
      'with health.yaml changed itself',
      () async => await checkGolden(
          check,
          fakeGithubApi([
            GitFile(
              '.github/workflows/health.yaml',
              FileStatus.added,
              directory,
            ),
          ]),
          directory,
          suffix: '_healthchanged'),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('Ignore license test', () async {
    await checkGolden(
      Check.license,
      fakeGithubApi([]),
      directory,
      suffix: '_ignore_license',
      ignoredLicense: ['pkgs/package3/**'],
    );
  });

  test(
    'Ignore packages test',
    () async {
      for (var check in Check.values) {
        await checkGolden(
          check,
          fakeGithubApi([]),
          directory,
          suffix: '_ignore_package',
          ignoredPackage: ['pkgs/package1'],
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> checkGolden(
  Check check,
  GithubApi githubApi,
  Directory directory, {
  String suffix = '',
  List<String> ignoredLicense = const [],
  List<String> ignoredPackage = const [],
  List<String> flutterPackages = const [],
}) async {
  final commentPath = p.join(
      Directory.systemTemp.createTempSync().path, 'comment_${check.name}.md');
  await Health(
    directory,
    check,
    [],
    [],
    false,
    ignoredPackage,
    ignoredLicense,
    [],
    [],
    githubApi,
    flutterPackages,
    base: Directory(p.join('test_data', 'base_test_repo')),
    comment: commentPath,
    log: printOnFailure,
  ).healthCheck();
  var comment = await File(commentPath).readAsString();
  var goldenFile =
      File(p.join('test_data', 'golden', 'comment_${check.name}$suffix.md'));
  if (Platform.environment['RESET_GOLDEN'] == '1') {
    goldenFile.writeAsStringSync(comment);
  } else {
    expect(comment, goldenFile.readAsStringSync());
  }
}
