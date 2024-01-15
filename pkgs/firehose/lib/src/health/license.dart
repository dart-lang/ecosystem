// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

final license = '''
// Copyright (c) ${DateTime.now().year}, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.''';

Future<List<String>> getFilesWithoutLicenses(Directory repositoryDir) async {
  var dartFiles = await repositoryDir
      .list(recursive: true)
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  print('Collecting files without license headers:');
  var filesWithoutLicenses = dartFiles
      .map((file) {
        var fileContents = File(file.path).readAsStringSync();
        var fileContainsCopyright = fileContents.contains('// Copyright (c)');
        if (!fileContainsCopyright) {
          var relativePath = path.relative(file.path, from: repositoryDir.path);
          print(relativePath);
          return relativePath;
        }
      })
      .whereType<String>()
      .sorted((a, b) => a.compareTo(b))
      .toList();
  print('''
Done, found ${filesWithoutLicenses.length} files without license headers''');
  return filesWithoutLicenses;
}
