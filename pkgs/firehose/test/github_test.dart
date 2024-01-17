// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/github.dart';
import 'package:github/github.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var github = GithubApi(
    repoSlug: RepositorySlug('dart-lang', 'ecosystem'),
    issueNumber: 148,
  );
  test('Fetching pull request description', () async {
    var pullrequestDescription = await github.pullrequestBody();
    expect(
        pullrequestDescription,
        startsWith(
            'Bumps [actions/labeler](https://github.com/actions/labeler) from 4.0.4 to 4.3.0.\n'));
  });
  test('Listing files for PR', () async {
    var files = await github.listFilesForPR(Directory.current);
    expect(files, [
      GitFile(
        '.github/workflows/pull_request_label.yml',
        FileStatus.modified,
        Directory.current,
      ),
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
  test('Find comment with searchterm', () async {
    var commentId = await github.findCommentId(
      user: 'auto-submit[bot]',
      searchTerm: 'some string not in the comment',
    );
    expect(commentId, isNull);
  });

  tearDownAll(() => github.close());
}
