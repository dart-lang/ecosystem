// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

Future<List<String>> getFilesWithoutLicenses(Directory repositoryDir,
    List<Glob> ignored, String licenseTestString) async {
  bool fileContainsCopyright(String fileContents) =>
      fileContents.contains(licenseTestString);

  var dartFiles = await repositoryDir
      .list(recursive: true)
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  print('Collecting files without license headers:');
  var filesWithoutLicenses = dartFiles
      .map((file) {
        var relativePath = path.relative(file.path, from: repositoryDir.path);
        if (ignored.none((glob) =>
            glob.matches(path.relative(file.path, from: repositoryDir.path)))) {
          var fileContents = File(file.path).readAsStringSync();
          if (!fileIsGenerated(fileContents, file.path) &&
              !fileContainsCopyright(fileContents)) {
            print(relativePath);
            return relativePath;
          }
        }
      })
      .whereType<String>()
      .sortedBy((fileName) => fileName)
      .toList();
  print('Done, found ${filesWithoutLicenses.length}'
      ' files without license headers');
  return filesWithoutLicenses;
}

bool fileIsGenerated(String fileContents, String path) =>
    path.endsWith('.g.dart') ||
    fileContents
        .split('\n')
        .takeWhile((line) => line.startsWith('//') || line.isEmpty)
        .any((line) => line.toLowerCase().contains('generate'));
