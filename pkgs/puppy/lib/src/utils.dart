// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

List<Directory> findPackages(Directory root, {bool deep = false}) {
  final results = <Directory>[];

  void traverse(Directory dir, {required bool deep}) {
    final pubspecs = dir
        .listSync()
        .whereType<File>()
        .where((element) => element.uri.pathSegments.last == 'pubspec.yaml')
        .toList();

    if (pubspecs.isNotEmpty) {
      results.add(dir);
    }

    if (!pubspecs.isNotEmpty || deep) {
      for (var subDir in dir.listSync().whereType<Directory>().where(
          (element) => !element.uri.pathSegments
              .any((element) => element.startsWith('.')))) {
        traverse(subDir, deep: deep);
      }
    }
  }

  traverse(Directory.current, deep: deep);

  return results;
}
