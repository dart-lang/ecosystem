import 'package:firehose/src/github.dart';
import 'package:github/github.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var github = GithubApi(
    repoSlug: RepositorySlug('dart-lang', 'ecosystem'),
    issueNumber: 148,
  );
  test('Fetching pull request description', () async {
    var pullrequestDescription = await github.pullrequestDescription();
    expect(
        pullrequestDescription,
        startsWith(
            'Bumps [actions/labeler](https://github.com/actions/labeler) from 4.0.4 to 4.3.0.\n'));
  });
  test('Listing files for PR', () async {
    var files = await github.listFilesForPR();
    expect(files, [
      GitFile('.github/workflows/pull_request_label.yml', FileStatus.modified),
    ]);
  });
  test('Find comment', () async {
    var commentId = await github.findCommentId(user: 'auto-submit[bot]');
    expect(commentId, 1660891263);
  });
  test('Find comment with searchterm', () async {
    var commentId = await github.findCommentId(
      user: 'auto-submit[bot]',
      searchTerm: 'before re-applying this label.',
    );
    expect(commentId, 1660891263);
  });

  tearDownAll(() => github.close());
}
