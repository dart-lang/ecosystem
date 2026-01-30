// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firehose/src/health/health.dart';
import 'package:firehose/src/health/license.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final fileWithLicense = File('test/fileWithLicense.dart');
  final fileWithoutLicense = File('test/fileWithoutLicense.dart');
  final licenseOptions = LicenseOptions();

  setUp(() async {
    await fileWithLicense.writeAsString(licenseOptions.license);
    await fileWithoutLicense.writeAsString('');
  });

  test('Check for licenses', () async {
    var directory = Directory('test/');
    var filesWithoutLicenses = await getFilesWithoutLicenses(
        directory, [], licenseOptions.licenseTestString);
    expect(filesWithoutLicenses,
        [path.relative(fileWithoutLicense.path, from: directory.path)]);
  });

  tearDown(() async {
    await fileWithLicense.delete();
    await fileWithoutLicense.delete();
  });
}
