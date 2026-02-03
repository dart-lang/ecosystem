// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:firehose/src/local_github_api.dart';
import 'package:firehose/src/repo.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> main() async {
  late final Directory directory;
  late final LocalGithubApi Function(List<GitFile> additional) fakeGithubApi;

  setUpAll(() async {
    directory = Directory(p.join('test_data', 'test_repo'));
    fakeGithubApi =
        (List<GitFile> additional) => LocalGithubApi(prLabels: [], files: [
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
            ]);

    await Process.run('dart', [
      'pub',
      'global',
      'activate',
      '-sgit',
      'https://github.com/bmw-tech/dart_apitool.git',
      '--git-ref',
      dart_apitoolHash,
    ]);
    await Process.run('dart', ['pub', 'global', 'activate', 'coverage']);
  });

  for (var check in Check.values) {
    test(
      'Check health workflow "${check.displayName}" against golden files',
      () async => await checkGolden(
        check,
        fakeGithubApi([]),
        directory,
      ),
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Check health workflow "${check.displayName}" against golden files '
      'with health.yaml changed itself',
      () async => await checkGolden(
          check,
          fakeGithubApi([
            GitFile(
              '.github/workflows/my_health.yaml',
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
      ignoreFor: {
        Check.license: ['pkgs/package3/**']
      },
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
  LocalGithubApi fakeGithubApi,
  Directory directory, {
  String suffix = '',
  Map<Check, List<String>> ignoreFor = const {},
  List<String> ignoredPackage = const [],
  List<String> flutterPackages = const [],
}) async {
  final commentPath = p.join(Directory.systemTemp.createTempSync().path,
      'comment_${check.displayName}.md');
  await FakeHealth(
    directory,
    check,
    [],
    [],
    false,
    ignoredPackage,
    ignoreFor,
    [],
    fakeGithubApi,
    flutterPackages,
    base: Directory(p.join('test_data', 'base_test_repo')),
    comment: commentPath,
    log: printOnFailure,
  ).healthCheck();
  final comment = await File(commentPath).readAsString();
  final goldenFile = File(
      p.join('test_data', 'golden', 'comment_${check.displayName}$suffix.md'));
  if (Platform.environment['RESET_GOLDEN'] == '1') {
    goldenFile.writeAsStringSync(comment);
  } else {
    expect(comment, goldenFile.readAsStringSync());
  }
}

class FakeHealth extends Health {
  FakeHealth(
    super.directory,
    super.check,
    super.warnOn,
    super.failOn,
    super.coverageweb,
    super.ignoredPackages,
    super.ignoredLicense,
    super.experiments,
    super.github,
    super.flutterPackages, {
    super.base,
    super.comment,
    super.log,
  }) : super(healthYamlNames: {'my_health.yaml'});

  @override
  String getCurrentVersionOfPackage(Package package) =>
      p.join('../base_test_repo/pkgs', package.name);
}
