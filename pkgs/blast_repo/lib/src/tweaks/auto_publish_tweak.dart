// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../exact_file_tweak.dart';
import '../utils.dart';

final _instance = AutoPublishTweak._();

class AutoPublishTweak extends ExactFileTweak {
  factory AutoPublishTweak() => _instance;

  AutoPublishTweak._()
      : super(
          id: 'auto-publish',
          description:
              'configure a github action to enable package auto-publishing',
          filePath: '.github/workflows/publish.yaml',
        );

  @override
  bool shouldRunByDefault(Directory checkout, String repoSlug) {
    return monoRepo(checkout, repoSlug);
  }

  @override
  String expectedContent(Directory checkout, String repoSlug) {
    final org = repoSlug.split('/').first;
    final branch = gitDefaultBranch(checkout) ?? 'main';
    final glob = singlePackageRepo(checkout)
        ? "'v[0-9]+.[0-9]+.[0-9]+'"
        : "'[A-z]+-v[0-9]+.[0-9]+.[0-9]+'";

    // Substitute for the github org, default branch, and glob pattern values.
    return publishContents
        .replaceAll('{org}', org)
        .replaceAll('{branch}', branch)
        .replaceAll('{glob}', glob);
  }
}

const publishContents = r'''
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  pull_request:
    branches: [ {branch} ]
  push:
    tags: [ {glob} ]

jobs:
  publish:
    if: ${{ github.repository_owner == '{org}' }}
    uses: dart-lang/ecosystem/.github/workflows/publish.yaml@main
''';
