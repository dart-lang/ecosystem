// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../exact_file_tweak.dart';
import '../repo_tweak.dart';

final _instance = NoResponseTweak._();

class NoResponseTweak extends ExactFileTweak {
  factory NoResponseTweak() => _instance;

  NoResponseTweak._()
      : super(
          name: 'No Response',
          description:
              "Configure a 'no response' bot to handle needs-info labels.",
          filePath: _filePath,
          expectedContent: _noResponseContent,
        );

  // TODO(devoncarew): Remove this after some iteration.
  @override
  bool get stable => false;

  @override
  FutureOr<FixResult> fix(Directory checkout) {
    // Check for and fail if this fix is not being run for a dart-lang repo.
    if (!_isDartLangOrgRepo(checkout)) {
      print('  repo is not in the dart-lang/ org');
      return FixResult.noFixesMade;
    }

    return super.fix(checkout);
  }
}

bool _isDartLangOrgRepo(Directory checkout) {
  final gitConfigFile = File(path.join(checkout.path, '.git', 'config'));
  final contents = gitConfigFile.readAsStringSync();

  return contents.contains('@github.com:dart-lang/') ||
      contents.contains('github.com/dart-lang/');
}

const _filePath = '.github/workflows/no-response.yml';

// The content below - as is - should only be run on dart-lang repos.
// Alternatively, we could substitue in the GitHub org for the repo into the
// config content.

const _noResponseContent = r'''
# A workflow to close issues where the author hasn't responded to a request for
# more information; see https://github.com/godofredoc/no-response for docs.

name: No Response

# Both `issue_comment` and `scheduled` event types are required.
on:
  issue_comment:
    types: [created]
  schedule:
    # Schedule for five minutes after the hour, every hour
    - cron: '5 * * * *'

# All permissions not specified are set to 'none'.
permissions:
  issues: write

jobs:
  noResponse:
    runs-on: ubuntu-latest
    if: ${{ github.repository_owner == 'dart-lang' }}
    steps:
      - uses: godofredoc/no-response@0ce2dc0e63e1c7d2b87752ceed091f6d32c9df09
        with:
          responseRequiredLabel: "needs-info"
          responseRequiredColor: 4774bc
          daysUntilClose: 14
          # Comment to post when closing an Issue for lack of response.
          closeComment: >
            Without additional information we're not able to resolve this
            issue, so it will be closed at this time. You're still free to add
            more info and respond to any questions above, though. We'll reopen
            the case if you do. Thanks for your contribution!
          token: ${{ github.token }}
''';
