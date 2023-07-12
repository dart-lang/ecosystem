// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firehose/src/health/license.dart';
import 'package:test/test.dart';

void main() {
  var fileWithLicense = File('test/fileWithLicense.dart');
  var fileWithoutLicense = File('test/fileWithoutLicense.dart');

  setUp(() async {
    await fileWithLicense.writeAsString(license);
    await fileWithoutLicense.writeAsString('');
  });

  test('Check for licenses', () async {
    var filesWithoutLicenses =
        await getFilesWithoutLicenses(Directory('test/'));
    expect(filesWithoutLicenses, [fileWithoutLicense.path]);
  });

  tearDown(() async {
    await fileWithLicense.delete();
    await fileWithoutLicense.delete();
  });
}
