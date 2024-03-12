// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:github/src/common/model/repos.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> main() async {
  final directory = Directory(p.join('test_data', 'test_repo'));
  var fakeGithubApi = FakeGithubApi(prLabels: [], files: [
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
  ]);
  await Process.run('dart', ['pub', 'global', 'activate', 'dart_apitool']);
  await Process.run('dart', ['pub', 'global', 'activate', 'coverage']);

  for (var check in checkTypes) {
    test(
      'Check health workflow "$check" against golden files',
      () async => await checkGolden(check, fakeGithubApi, directory),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('Ignore license test', () async {
    await checkGolden(
      'license',
      fakeGithubApi,
      directory,
      suffix: '_ignore_license',
      ignoredLicense: ['pkgs/package3/**'],
    );
  });

  test(
    'Ignore packages test',
    () async {
      for (var check in checkTypes) {
        await checkGolden(
          check,
          fakeGithubApi,
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
  String check,
  FakeGithubApi fakeGithubApi,
  Directory directory, {
  String suffix = '',
  List<String> ignoredLicense = const [],
  List<String> ignoredPackage = const [],
}) async {
  final commentPath = p.join(Directory.systemTemp.path, 'comment_$check.md');
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
    fakeGithubApi,
    base: Directory(p.join('test_data', 'base_test_repo')),
    comment: commentPath,
  ).healthCheck();
  var comment = await File(commentPath).readAsString();
  var goldenFile =
      File(p.join('test_data', 'golden', 'comment_$check$suffix.md'));
  if (Platform.environment['RESET_GOLDEN'] == '1') {
    goldenFile.writeAsStringSync(comment);
  } else {
    expect(comment, goldenFile.readAsStringSync());
  }
}

class FakeGithubApi implements GithubApi {
  final List<GitFile> files;

  FakeGithubApi({
    required this.prLabels,
    required this.files,
  });

  @override
  String? get actor => throw UnimplementedError();

  @override
  void appendStepSummary(String markdownSummary) {}

  @override
  String? get baseRef => throw UnimplementedError();

  @override
  void close() {}

  @override
  Future<int?> findCommentId({required String user, String? searchTerm}) {
    throw UnimplementedError();
  }

  @override
  String? get githubAuthToken => throw UnimplementedError();

  @override
  bool get inGithubContext => throw UnimplementedError();

  @override
  int? get issueNumber => 1;

  @override
  Future<List<GitFile>> listFilesForPR(Directory directory,
      [List<Glob> ignoredFiles = const []]) async {
    return files
        .where((element) =>
            ignoredFiles.none((p0) => p0.matches(element.filename)))
        .toList();
  }

  @override
  void notice({required String message}) {}

  @override
  final List<String> prLabels;

  @override
  Future<String> pullrequestBody() async => 'Test body';

  @override
  String? get refName => throw UnimplementedError();

  @override
  RepositorySlug? get repoSlug => RepositorySlug('test_owner', 'test_repo');

  @override
  String? get sha => 'test_sha';
}
