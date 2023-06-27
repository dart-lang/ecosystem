// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/health.dart';

final possibleArgs = [
  'version',
  'license',
  'changelog',
  'coverage',
];

void main(List<String> arguments) async {
  var health = Health(Directory.current);

  if (arguments.any((element) {
    return !possibleArgs.contains(element);
  })) {
    print('''
Pass only a subset of $possibleArgs as arguments. Example: 

  dart run bin/health.dart version license
''');
    exit(1);
  }

  await health.healthCheck(arguments);
}
