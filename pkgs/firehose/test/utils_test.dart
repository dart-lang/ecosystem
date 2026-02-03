// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:firehose/src/utils.dart';
import 'package:test/test.dart';

void main() {
  group('Tag', () {
    test('invalid', () {
      final tag = Tag('1.2.4');
      expect(tag.valid, false);
    });

    test('invalid 2', () {
      final tag = Tag('v1.2');
      expect(tag.valid, false);
    });

    test('single package repo', () {
      final tag = Tag('v1.2.3');
      expect(tag.version, '1.2.3');
    });

    test('pre-release package repo', () {
      final tag = Tag('v1.2.3-beta');
      expect(tag.version, '1.2.3-beta');
    });

    test('service release', () {
      final tag = Tag('v1.2.3+1');
      expect(tag.version, '1.2.3+1');
    });

    test('mono repo', () {
      final tag = Tag('foobar-v1.2.3');
      expect(tag.package, 'foobar');
      expect(tag.version, '1.2.3');
    });

    test('mono repo 2', () {
      final tag = Tag('foo_bar-v1.2.3');
      expect(tag.package, 'foo_bar');
      expect(tag.version, '1.2.3');
    });

    test('mono repo pre-release', () {
      final tag = Tag('foo_bar-v1.2.3-dev.1');
      expect(tag.package, 'foo_bar');
      expect(tag.version, '1.2.3-dev.1');
    });

    test('mono repo bad', () {
      final tag = Tag('foobar_v1.2.3');
      expect(tag.valid, false);
    });

    test('mono repo bad 2', () {
      var tag = Tag('foobar_1.2.3');
      expect(tag.valid, false);

      tag = Tag('foobar-1.2.3');
      expect(tag.valid, false);
    });
  });
}
