// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../exact_file_tweak.dart';

final _instance = AutoPublishTweak._();

// TODO: We'd also like to print some post-install steps (configure the repo
// thuswise, ...).

// TODO: We may also want to make a change to the readme (add a new section on
// auto-publishing).

class AutoPublishTweak extends ExactFileTweak {
  factory AutoPublishTweak() => _instance;

  AutoPublishTweak._()
      : super(
          id: 'auto-publish',
          description:
              'configure a github action to enable package auto-publishing',
          filePath: '.github/workflows/publish.yml',
        );

  @override
  bool get stable => false;

  @override
  String expectedContent(String repoSlug) {
    final org = repoSlug.split('/').first;

    // Substitute the org value for the pattern '{org}'.
    return publishContents.replaceAll('{org}', org);
  }
}

const publishContents = r'''
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  # Run on PRs for general validation (changelog, pubspec version, ...).
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, labeled, unlabeled]
  # Run on git tags to perform the publish.
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+*'

jobs:
  auto-publish:
    # Update this to the host GitHub org.
    if: github.repository_owner == '{org}'

    # This is required for authentication using OIDC.
    permissions:
      id-token: write 

    runs-on: ubuntu-latest
    steps:
      # Fetches all commits in order to determine the changed files.
      - name: Check out repo
        uses: actions/checkout@755da8c3cf115ac066823e79a1e1788f8940201b
        with:
          fetch-depth: 0

      - name: Set up Dart
        uses: dart-lang/setup-dart@v1.4

      - name: Install Firehose
        run: dart pub global activate firehose

      - name: Validate package changes
        if: ${{ github.event_name == 'pull_request' }}
        run: dart pub global run firehose --verify
        env:
          PR_LABELS: "${{ join(github.event.pull_request.labels.*.name) }}"

      - name: Publish package
        if: ${{ github.event_name == 'push' }}
        run: dart pub global run firehose --publish
''';
