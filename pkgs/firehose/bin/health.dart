// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/health/health.dart';

void main(List<String> arguments) async {
  var argParser = ArgParser()
    ..addMultiOption(
      'checks',
      allowed: ['version', 'license', 'changelog', 'coverage'],
      help: 'Check PR health.',
    )
    ..addFlag(
      'coverage_web',
      help: 'Whether to run web tests for coverage',
    );
  var parsedArgs = argParser.parse(arguments);
  var checks = parsedArgs['checks'] as List<String>;
  var testWeb = parsedArgs['coverage_web'] as bool;

  await Health(Directory.current).healthCheck(checks, testWeb);
}
