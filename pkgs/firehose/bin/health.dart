// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/health.dart';

void main(List<String> arguments) async {
  var argParser = ArgParser()
    ..addOption(
      'check',
      allowed: checkTypes,
      help: 'Check PR health.',
    )
    ..addMultiOption(
      'ignore_packages',
      help: 'Which packages to ignore.',
    )
    ..addMultiOption(
      'ignore_license',
      help: 'Which files to ignore for the license check.',
    )
    ..addMultiOption(
      'ignore_coverage',
      help: 'Which files to ignore for the coverage check.',
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
  var check = parsedArgs['check'] as String;
  var warnOn = parsedArgs['warn_on'] as List<String>;
  var failOn = parsedArgs['fail_on'] as List<String>;
  var ignorePackages = parsedArgs['ignore_packages'] as List<String>;
  var ignoreLicense = parsedArgs['ignore_license'] as List<String>;
  var ignoreCoverage = parsedArgs['ignore_coverage'] as List<String>;
  var coverageWeb = parsedArgs['coverage_web'] as bool;
  if (warnOn.toSet().intersection(failOn.toSet()).isNotEmpty) {
    throw ArgumentError('The checks for which warnings are displayed and the '
        'checks which lead to failure must be disjoint.');
  }
  await Health(
    Directory.current,
    check,
    warnOn,
    failOn,
    coverageWeb,
    GithubApi(),
    ignorePackages,
    ignoreLicense,
    ignoreCoverage,
  ).healthCheck();
}
