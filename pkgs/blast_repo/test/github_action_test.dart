// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:blast_repo/src/action_version.dart';
import 'package:blast_repo/src/github.dart';
import 'package:blast_repo/src/github_action_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('action check', () {
    const actions = {
      'actions/checkout@v2': '2.6.0::dc323e67f16fb5f7663d20ff7941f27f5809e9b6',
      'actions/checkout@v2.3.4':
          '2.3.4::5a4ac9002d0be2fb38bd78e4b4dbde5606d7042f',
      'actions/setup-java@de1bb2b0c5634f0fc4438d7aa9944e68f9bf86cc':
          '3.6.0::de1bb2b0c5634f0fc4438d7aa9944e68f9bf86cc',
      'actions/setup-node@v2':
          '2.5.1::1f8c6b94b26d0feae1e387ca63ccbdc44d27b561',
      'actions/setup-node@v3':
          '3.6.0::64ed1c7eab4cce3362f8c340dee64e5eaeef8f7c',
      'android-actions/setup-android@v2.0.2':
          '2.0.2::72fdd2e74f58fb338a2743720c0847b8becf1589',
      'dart-lang/setup-dart@v1':
          '1.4.0::a57a6c04cf7d4840e88432aad6281d1e125f0d46',
      'dart-lang/setup-dart@v1.0':
          '1.0.0::9a04e6d73cca37bd455e0608d7e5092f881fd603',
      'dart-lang/setup-dart@v1.3':
          '1.4.0::a57a6c04cf7d4840e88432aad6281d1e125f0d46',
      'github/codeql-action/upload-sarif@807578363a7869ca324a79039e6db9c843e0e100':
          '2.1.27::807578363a7869ca324a79039e6db9c843e0e100',
      // Some folks just point to a branch!
      'coverallsapp/github-action@master':
          'master::3284643be2c47fb6432518ecec17f1255e8a06a6',
      'codecov/codecov-action@main':
          'main::e0fbd592d323cb2991fb586fdd260734fcb41fcb',
    };

    group('parse', () {
      for (var action in actions.keys) {
        test('"$action"', () {
          final result = ActionVersion.parse(action);
          expect(result.toString(), action);
        });
      }
    });

    group('resolve', () {
      late final GitHubActionResolver resolver;
      setUpAll(() {
        resolver = GitHubActionResolver(github: createGitHubClient());

        addTearDown(resolver.close);
      });

      for (var action in actions.entries) {
        final result = ActionVersion.parse(action.key);
        test(
          '"${action.key}"',
          skip:
              result.path == null ? null : 'Cannot handle paths at the moment.',
          () async {
            final tag = await resolver.resolve(result);
            expect(tag.toString(), action.value);
          },
        );
      }
    });

    group('latest fun', () {
      late final GitHubActionResolver resolver;
      setUpAll(() {
        resolver = GitHubActionResolver(github: createGitHubClient());

        addTearDown(resolver.close);
      });

      final repos =
          actions.keys.map(ActionVersion.parse).map((e) => e.fullRepo).toSet();

      for (var repo in repos) {
        test('"$repo"', () async {
          // TODO(kevmoo): do more than just run - but better than nothing
          await resolver.latestStable(repo);
        });
      }
    });
  });
}
