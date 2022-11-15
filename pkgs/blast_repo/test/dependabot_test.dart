// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:blast_repo/src/tweaks/dependabot_tweak.dart';
import 'package:test/test.dart';

void main() {
  group('bad cases', () {
    const values = {
      'not a map': '"bob"',
      'no version': 'no_version: bob',
      'just a version': 'version: 2',
      'updates null': '''
version: 2
updates:
''',
      'updates not a list': '''
version: 2
updates: "bob"
''',
    };

    for (var entry in values.entries) {
      test(entry.key, () {
        expect(() => doDependabotFix(entry.value), throwsException);
      });
    }
  });

  test('updates missing package-ecosystem', () {
    final result = doDependabotFix(r'''
#some comment
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "monthly"
''');

    expect(result, r'''
#some comment
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "monthly"

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
''');
  });

  test('updates weird value', () {
    final result = doDependabotFix(r'''
# Dependabot configuration file.
# See https://docs.github.com/en/code-security/dependabot/dependabot-version-updates
version: 2

updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: daily
''');

    expect(result, r'''
# Dependabot configuration file.
# See https://docs.github.com/en/code-security/dependabot/dependabot-version-updates
version: 2

updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
''');
  });

  test('default content should be a no-op', () {
    final result = doDependabotFix(dependabotDefaultContent);
    expect(result, dependabotDefaultContent);
  });
}
