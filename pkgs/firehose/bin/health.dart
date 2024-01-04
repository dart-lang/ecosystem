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
      allowed: checkTypes,
      help: 'Check PR health.',
    )
    ..addMultiOption(
      'warn_on',
      allowed: checkTypes,
      help: 'Which checks to display warnings on',
    )
    ..addMultiOption(
      'fail_on',
      allowed: checkTypes,
      help: 'Which checks should lead to workflow failure',
    )
    ..addFlag(
      'coverage_web',
      help: 'Whether to run web tests for coverage',
    );
  var parsedArgs = argParser.parse(arguments);
  var checks = parsedArgs['checks'] as List<String>;
  var warnOn = parsedArgs['warn_on'] as List<String>;
  var failOn = parsedArgs['fail_on'] as List<String>;
  var coverageWeb = parsedArgs['coverage_web'] as bool;
  if (warnOn.toSet().intersection(failOn.toSet()).isNotEmpty) {
    throw ArgumentError('The checks for which warnings are displayed and the '
        'checks which lead to failure must be disjoint.');
  }
  await Health(Directory.current, checks, warnOn, failOn, coverageWeb)
      .healthCheck();
}
