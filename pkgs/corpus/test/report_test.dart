// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:corpus/pub.dart';
import 'package:corpus/report.dart';
import 'package:path/path.dart' as path;
import 'package:test/scaffolding.dart';
import 'package:test_descriptor/test_descriptor.dart';

void main() {
  group('Report', () {
    late Directory previousCurrent;

    setUp(() {
      previousCurrent = Directory.current;
      Directory.current = Directory(sandbox);
    });

    tearDown(() {
      Directory.current = previousCurrent;
    });

    test('generates report for DartLibraryTarget', () {
      final target = DartLibraryTarget(name: 'collection', version: '3.9.0');
      final file = Report(target).generateReport([]);

      check(file.path).equals(path.join('reports', 'dart_collection.md'));
      final content = file.readAsStringSync();
      check(content).contains('# Report for dart:collection');
      check(content).contains(
        'https://api.dart.dev/dart-collection/dart-collection-library.html',
      );
    });

    test('includes description for PackageTarget when non-null', () {
      final target = PackageTarget.fromPackage(
        PackageInfo.from({
          'name': 'path',
          'latest': {
            'version': '1.9.0',
            'pubspec': {
              'name': 'path',
              'version': '1.9.0',
              'description': 'A string-based path manipulation library.',
            },
            'archive_url':
                'https://pub.dev/packages/path/versions/1.9.0.tar.gz',
            'published': '2024-01-01T00:00:00Z',
          },
        }),
      );
      final file = Report(target).generateReport([]);

      check(file.path).equals(path.join('reports', 'package_path.md'));
      final content = file.readAsStringSync();
      check(content).contains('A string-based path manipulation library.');
      check(content).contains('- pub page: https://pub.dev/packages/path');
    });

    test('omits description for PackageTarget when null', () {
      final target = PackageTarget.fromPackage(
        PackageInfo.from({
          'name': 'path',
          'latest': {
            'version': '1.9.0',
            'pubspec': {'name': 'path', 'version': '1.9.0'},
            'archive_url':
                'https://pub.dev/packages/path/versions/1.9.0.tar.gz',
            'published': '2024-01-01T00:00:00Z',
          },
        }),
      );
      final file = Report(target).generateReport([]);

      final content = file.readAsStringSync();
      check(content).not((it) => it.contains('null'));
      check(content).contains(
        '## General info\n\n- pub page: https://pub.dev/packages/path',
      );
    });
  });
}
