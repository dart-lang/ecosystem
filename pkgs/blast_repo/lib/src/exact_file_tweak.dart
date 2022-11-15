// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'repo_tweak.dart';

abstract class ExactFileTweak extends RepoTweak {
  ExactFileTweak({
    required this.filePath,
    required this.expectedContent,
    required super.name,
    required super.description,
    this.alternateFilePaths = const {},
  }) : assert(p.isRelative(filePath)) {
    if (!p.isRelative(filePath)) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Must be a relative path!',
      );
    }

    for (var entry in alternateFilePaths) {
      if (p.equals(entry, filePath)) {
        throw ArgumentError.value(
          alternateFilePaths,
          'alternateFilePaths',
          'Should not contain `filePath` ($filePath).',
        );
      }
      if (!p.isRelative(entry)) {
        throw ArgumentError.value(
          alternateFilePaths,
          'alternateFilePaths',
          'Must be a relative path ($entry)',
        );
      }
    }
  }

  final String filePath;
  final Set<String> alternateFilePaths;
  final String expectedContent;

  @override
  FutureOr<FixResult> fix(Directory checkout) {
    final file = _targetFile(checkout);

    final exists = file.existsSync();
    if (exists) {
      final existingContent = file.readAsStringSync();
      assert(existingContent != expectedContent);
    }
    file.writeAsStringSync(expectedContent);

    return FixResult(
      fixes: ['$filePath has been ${exists ? 'updated' : 'created'}.'],
    );
  }

  File _targetFile(Directory checkout) {
    assert(checkout.existsSync());

    for (var option in [filePath, ...alternateFilePaths]) {
      final realPath = p.join(checkout.path, option);

      final realFile = File(realPath);
      if (realFile.existsSync()) {
        return realFile;
      }
    }

    return File(p.join(checkout.path, filePath));
  }
}
