// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:firehose/src/pub.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('pub', () {
    late Pub pub;

    setUp(() {
      pub = Pub();
    });

    tearDown(() {
      pub.close();
    });

    test('version exists', () async {
      final result = await pub.hasPublishedVersion('path', '1.8.0');
      expect(result, true);
    });

    test('version doesn\'t exist', () async {
      final result = await pub.hasPublishedVersion('path', '1.7.1');
      expect(result, false);
    });

    test('package not published exists', () async {
      final result = await pub.hasPublishedVersion(
          'foo_bar_not_published_package', '1.8.0');
      expect(result, false);
    });
  });

  group('VersionExtension', () {
    test('wip no pre-release', () async {
      final version = Version.parse('1.2.3');
      expect(version.wip, false);
    });

    test('wip pre-release', () async {
      final version = Version.parse('1.2.3-dev');
      expect(version.wip, false);
    });

    test('wip pre-release wip', () async {
      final version = Version.parse('1.2.3-wip');
      expect(version.wip, true);
    });
  });
}
