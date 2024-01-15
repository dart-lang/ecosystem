import 'dart:io';

import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';
import 'package:github/src/common/model/repos.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('test name', () async {
    var fakeGithubApi = FakeGithubApi(prLabels: [], files: [
      GitFile('pkgs/package1/bin/package1.dart', FileStatus.modified),
      GitFile('pkgs/package2/lib/anotherLib.dart', FileStatus.added),
    ]);
    // await checkFor('version', fakeGithubApi);
    // await checkFor('license', fakeGithubApi);
    await checkFor('breaking', fakeGithubApi);
  });
}

Future<void> checkFor(String check, FakeGithubApi fakeGithubApi) async =>
    await Health(
      Directory(p.join('test', 'data', 'test_repo')),
      check,
      [],
      [],
      false,
      fakeGithubApi,
      [],
      [],
      [],
      base: Directory(p.join('test', 'data', 'base_test_repo')),
    ).healthCheck();

class FakeGithubApi implements GithubApi {
  final List<GitFile> files;

  FakeGithubApi({
    required this.prLabels,
    required this.files,
  });

  @override
  // TODO: implement actor
  String? get actor => throw UnimplementedError();

  @override
  void appendStepSummary(String markdownSummary) {
    // TODO: implement appendStepSummary
  }

  @override
  // TODO: implement baseRef
  String? get baseRef => throw UnimplementedError();

  @override
  void close() {
    // TODO: implement close
  }

  @override
  Future<int?> findCommentId({required String user, String? searchTerm}) {
    // TODO: implement findCommentId
    throw UnimplementedError();
  }

  @override
  // TODO: implement githubAuthToken
  String? get githubAuthToken => throw UnimplementedError();

  @override
  // TODO: implement inGithubContext
  bool get inGithubContext => throw UnimplementedError();

  @override
  int? get issueNumber => 1;

  @override
  Future<List<GitFile>> listFilesForPR(
      [List<Glob> ignoredFiles = const []]) async {
    return files;
  }

  @override
  void notice({required String message}) {
    // TODO: implement notice
  }

  @override
  final List<String> prLabels;

  @override
  Future<String> pullrequestBody() {
    // TODO: implement pullrequestBody
    throw UnimplementedError();
  }

  @override
  // TODO: implement refName
  String? get refName => throw UnimplementedError();

  @override
  RepositorySlug? get repoSlug => RepositorySlug('test_owner', 'test_repo');

  @override
  String? get sha => 'test_sha';
}
