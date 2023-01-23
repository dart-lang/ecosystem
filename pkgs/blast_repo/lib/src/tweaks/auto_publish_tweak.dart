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
    if: ${{ github.repository_owner == '{org}' }}
    uses: dart-lang/ecosystem/.github/workflows/publish.yaml@main
''';

const String readmeSection = '''
## Publishing automation

For information about our publishing automation and release process, see
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
''';
