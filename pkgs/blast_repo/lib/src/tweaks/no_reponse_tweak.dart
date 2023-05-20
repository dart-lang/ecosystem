// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../exact_file_tweak.dart';

final _instance = NoResponseTweak._();

class NoResponseTweak extends ExactFileTweak {
  factory NoResponseTweak() => _instance;

  NoResponseTweak._()
      : super(
          id: 'no-response',
          description:
              "configure a 'no response' bot to handle needs-info labels",
          filePath: filePath,
        );

  @override
  bool get stable => false;

  @override
  String expectedContent(Directory checkout, String repoSlug) {
    final org = repoSlug.split('/').first;

    // Substitute for the github org value.
    return noResponseContent.replaceAll('{org}', org);
  }
}

const filePath = '.github/workflows/no-response.yml';

const noResponseContent = r'''
# A workflow to close issues where the author hasn't responded to a request for
# more information; see https://github.com/actions/stale.

name: No Response

# Run as a daily cron.
on:
  schedule:
    # Every day at 8am
    - cron: '0 8 * * *'

# All permissions not specified are set to 'none'.
permissions:
  issues: write
  pull-requests: write

jobs:
  no-response:
    runs-on: ubuntu-latest
    if: ${{ github.repository_owner == '{org}' }}
    steps:
      - uses: actions/stale@1160a2240286f5da8ec72b1c0816ce2481aabf84
        with:
          # Don't automatically mark inactive issues+PRs as stale.
          days-before-stale: -1
          # Close needs-info issues and PRs after 14 days of inactivity.
          days-before-close: 14
          stale-issue-label: "needs-info"
          close-issue-message: >
            Without additional information we're not able to resolve this issue.
            Feel free to add more info or respond to any questions above and we
            can reopen the case. Thanks for your contribution!
          stale-pr-label: "needs-info"
          close-pr-message: >
            Without additional information we're not able to resolve this PR.
            Feel free to add more info or respond to any questions above.
            Thanks for your contribution!
''';
