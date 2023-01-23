// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/pubspec.dart';
import 'package:test/test.dart';

void main() {
  group('pubspec', () {
    late Pubspec pubspec;

    setUp(() {
      pubspec = Pubspec(Directory.current);
    });

    test('name', () {
      var name = pubspec.name;
      expect(name, isNotNull);
      expect(name, equals('firehose'));
    });

    test('version', () {
      var version = pubspec.version;
      expect(version, isNotNull);
    });
  });
}
