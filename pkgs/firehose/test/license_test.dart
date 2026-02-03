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
  late File fileWithLicense;
  late File fileWithoutLicense;
  late Directory directory;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('license_test');
    fileWithLicense = File(path.join(directory.path, 'fileWithLicense.dart'));
    fileWithoutLicense =
        File(path.join(directory.path, 'fileWithoutLicense.dart'));
    await fileWithoutLicense.writeAsString('');
  });

  test('Check for license', () async {
    final licenseOptions = LicenseOptions();
    await fileWithLicense.writeAsString(licenseOptions.license);

    final filesWithoutLicenses = await getFilesWithoutLicenses(
        directory, [], licenseOptions.licenseTestString);
    expect(filesWithoutLicenses,
        [path.relative(fileWithoutLicense.path, from: directory.path)]);
  });

  test('Check for custom license', () async {
    final licenseOptions = LicenseOptions(license: '''
// My custom license
// 
// Dabadu''', licenseTestString: '// My ');
    await fileWithLicense.writeAsString(licenseOptions.license);

    final filesWithoutLicenses = await getFilesWithoutLicenses(
        directory, [], licenseOptions.licenseTestString);
    expect(filesWithoutLicenses,
        [path.relative(fileWithoutLicense.path, from: directory.path)]);
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });
}
