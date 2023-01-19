// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;

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
  bool get stable => false;

  @override
  String expectedContent(Directory checkout, String repoSlug) {
    final org = repoSlug.split('/').first;
    final branch = gitDefaultBranch(checkout) ?? 'main';

    // Substitute the org value for the pattern '{org}' and the default branch
    // value for '{branch}'.
    return publishContents
        .replaceAll('{org}', org)
        .replaceAll('{branch}', branch);
  }

  @override
  List<String> performAdditionalFixes(Directory checkout, String repoSlug) {
    var results = <String>[];

    // Update the readme to include contribution + publishing info.
    const tag = 'Contributions, PRs, and publishing';

    var readmeFile = File(path.join(checkout.path, 'README.md'));

    if (readmeFile.existsSync()) {
      var contents = readmeFile.readAsStringSync();

      if (!contents.contains(tag)) {
        var newContents = '${contents.trimRight()}\n\n$readmeSection';
        readmeFile.writeAsStringSync(newContents);
        results.add('README.md updated with contribution and publishing info.');
      }
    }

    return results;
  }
}

const publishContents = r'''
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  pull_request:
    branches: [ {branch} ]
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  publish:
    if: ${{ github.repository_owner == {org} }}
    uses: devoncarew/firehose/.github/workflows/publish.yaml@main
''';

const String readmeSection = '''
## Contributions, PRs, and publishing

When contributing to this repo:

- if the package version is a stable semver version (`x.y.z`), the latest
  changes have been published to pub. Please add a new changelog section for
  your change, rev the service portion of the version, append `-dev`, and update
  the pubspec version to agree with the new version
- if the package version ends in `-dev`, the latest changes are unpublished;
  please add a new changelog entry for your change in the most recent section.
  When we decide to publish the latest changes we'll drop the `-dev` suffix
  from the package version
- for PRs, the `Publish` bot will perform basic validation of the info in the
  pubspec.yaml and CHANGELOG.md files
- when the PR is merged into the main branch, if the change includes reving to
  a new stable version, a repo maintainer will tag that commit with the pubspec
  version (e.g., `v1.2.3`); that tag event will trigger the `Publish` bot to
  publish a new version of the package to pub.dev
''';
