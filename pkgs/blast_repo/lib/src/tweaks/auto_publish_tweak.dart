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
  bool shouldRunByDefault(Directory checkout, String repoSlug) =>
      monoRepo(checkout, repoSlug);

  @override
  String expectedContent(Directory checkout, String repoSlug) {
    final org = repoSlug.split('/').first;
    final template = singlePackageRepo(checkout)
        ? singlePackagePublishContents
        : monoRepoPublishContents;

    // Substitute for the github org value.
    return template.replaceAll('{org}', org);
  }
}

const singlePackagePublishContents = r'''
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  publish:
    if: ${{ github.repository_owner == '{org}' }}
    permissions:
      id-token: write # Required for authentication using OIDC
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@a5bff6576dfc51b47eb77d4b7084bba6a4daf8d2 # main
    with:
      use-flutter: false
''';

const monoRepoPublishContents = r'''
# A CI configuration to auto-publish pub packages.
#
# Pushing a tag PACKAGE-vVERSION publishes the package in pkgs/PACKAGE.
# Publish checks on pull requests run in the Health workflow.

name: Publish

on:
  push:
    tags: [ '[A-z]+-v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  package:
    if: ${{ github.repository_owner == '{org}' }}
    permissions: {}
    runs-on: ubuntu-latest
    outputs:
      directory: ${{ steps.directory.outputs.directory }}
    steps:
      - id: directory
        name: Find the package directory from the tag
        env:
          TAG: ${{ github.ref_name }}
        run: |
          package="${TAG%%-v*}"
          if [[ ! "$package" =~ ^[a-z0-9_]+$ ]]; then
            echo "No package directory in tag $TAG."
            exit 1
          fi
          echo "directory=pkgs/$package" >> "$GITHUB_OUTPUT"

  publish:
    needs: package
    permissions:
      id-token: write # Required for authentication using OIDC
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@a5bff6576dfc51b47eb77d4b7084bba6a4daf8d2 # main
    with:
      working-directory: ${{ needs.package.outputs.directory }}
      use-flutter: false
''';
