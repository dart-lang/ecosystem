// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/health.dart';

void main(List<String> arguments) async {
  var argParser = ArgParser()
    ..addMultiOption(
      'checks',
      defaultsTo: ['version', 'license', 'changelog'],
      allowed: ['version', 'license', 'changelog'],
      help: 'Check PR health.',
    );
  var parsedArgs = argParser.parse(arguments);

  await Health(Directory.current)
      .healthCheck(parsedArgs['checks'] as List<String>);
}
