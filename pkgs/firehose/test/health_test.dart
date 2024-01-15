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
    for (var check in checkTypes) {
      var comment = await checkFor(check, fakeGithubApi);
      var goldenFile =
          File(p.join('test', 'data', 'golden', 'comment_$check.md'));
      var goldenComment = goldenFile.readAsStringSync();
      if (Platform.environment.containsKey('RESET_GOLDEN')) {
        goldenFile.writeAsStringSync(comment);
      } else {
        expect(comment, goldenComment);
      }
    }
  });
}

Future<String> checkFor(String check, FakeGithubApi fakeGithubApi) async {
  final comment = p.join(Directory.systemTemp.path, 'comment_$check.md');
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
    comment: comment,
  ).healthCheck();
  return await File(comment).readAsString();
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
  Future<List<GitFile>> listFilesForPR(
      [List<Glob> ignoredFiles = const []]) async {
    return files;
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
