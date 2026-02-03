// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as path;

Map<String, double> parseLCOV(
  String lcovPath, {
  required String relativeTo,
}) {
  final file = File(lcovPath);
  List<String> lines;
  if (file.existsSync()) {
    lines = file.readAsLinesSync();
  } else {
    print('LCOV file not found at $lcovPath.');
    return {};
  }
  final coveragePerFile = <String, double>{};
  String? fileName;
  int? numberLines;
  int? coveredLines;
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      fileName = line.substring('SF:'.length);
    } else if (line.startsWith('LF:')) {
      numberLines = int.parse(line.substring('LF:'.length));
    } else if (line.startsWith('LH:')) {
      coveredLines = int.parse(line.substring('LH:'.length));
    } else if (line.startsWith('end_of_record')) {
      if (numberLines != null) {
        final change = (coveredLines ?? 0) / numberLines;
        coveragePerFile[path.relative(fileName!, from: relativeTo)] = change;
      }
    }
  }
  print('Found coverage for ${coveragePerFile.length} files.');
  return coveragePerFile;
}
