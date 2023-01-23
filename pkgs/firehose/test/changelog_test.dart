// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/changelog.dart';
import 'package:test/test.dart';

void main() {
  group('changelog', () {
    late Changelog changelog;

    setUp(() {
      changelog = Changelog(File('CHANGELOG.md'));
    });

    test('exists', () {
      var version = changelog.exists;
      expect(version, isTrue);
    });

    test('latestVersion', () {
      var version = changelog.latestVersion;
      expect(version, isNotNull);
    });

    test('latestChangeEntries', () {
      var version = changelog.latestChangeEntries;
      expect(version, isNotEmpty);
    });
  });
}
