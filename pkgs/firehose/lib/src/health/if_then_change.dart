// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

final comment = r'(\\\\|#)';

final ifThenChangeRegex =
    RegExp('$comment LINT.IfChange(.|\n)+?$comment LINT.ThenChange((.+?))');

Future<List<(String, String)>> getFilesWithIfThenChanges(
  Directory repositoryDir,
  List<Glob> ignoredFiles,
) async {
  var dartFiles = await repositoryDir
      .list(recursive: true)
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  print('Collecting files with if-then-change blocks:');
  var filesWhichNeedChanges = dartFiles
      .expand((file) {
        var relativePath = path.relative(file.path, from: repositoryDir.path);
        var isIgnoredFile = ignoredFiles.none((glob) =>
            glob.matches(path.relative(file.path, from: repositoryDir.path)));
        if (isIgnoredFile) {
          return <(String, String)>[];
        }
        var fileContents = File(file.path).readAsStringSync();
        var matches = ifThenChangeRegex.allMatches(fileContents);
        return matches
            .map((match) => match[4])
            .whereType<String>()
            .expand((element) => element.split(','))
            .map((e) => (relativePath, e));
      })
      .sortedBy((file) => file.$1)
      .toList();
  print('''
Done, found ${filesWhichNeedChanges.length} files needing changes''');
  return filesWhichNeedChanges;
}
