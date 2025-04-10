// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/firehose.dart';
import 'package:glob/glob.dart';

const helpFlag = 'help';
const validateFlag = 'validate';
const publishFlag = 'publish';
const useFlutterFlag = 'use-flutter';

void main(List<String> arguments) async {
  var argParser = _createArgs();
  try {
    final argResults = argParser.parse(arguments);

    if (argResults[helpFlag] as bool) {
      _usage(argParser);
      return;
    }

    final validate = argResults[validateFlag] as bool;
    final publish = argResults[publishFlag] as bool;
    final useFlutter = argResults[useFlutterFlag] as bool;
    final ignoredPackages = (argResults['ignore-packages'] as List<String>)
        .where((pattern) => pattern.isNotEmpty)
        .map((pattern) => Glob(pattern, recursive: true))
        .toList();

    if (!validate && !publish) {
      _usage(argParser,
          error: 'Error: one of --validate or --publish must be specified.');
      exitCode = 1;
      return;
    }

    final github = GithubApi();
    if (publish && !github.inGithubContext) {
      _usage(argParser,
          error: 'Error: --publish can only be executed from within a GitHub '
              'action.');
      exitCode = 1;
      return;
    }

    final firehose = Firehose(Directory.current, useFlutter, ignoredPackages);

    if (validate) {
      await firehose.validate();
    } else if (publish) {
      await firehose.publish();
    }
  } on ArgParserException catch (e) {
    _usage(argParser, error: e.message);
    exitCode = 1;
    return;
  }
}

void _usage(ArgParser argParser, {String? error}) {
  if (error != null) {
    stderr.writeln(error);
    stderr.writeln();
  }

  print('usage: dart bin/firehose.dart <options>');
  print('');
  print(argParser.usage);
}

ArgParser _createArgs() {
  return ArgParser()
    ..addFlag(
      helpFlag,
      abbr: 'h',
      negatable: false,
      help: 'Print tool help.',
    )
    ..addFlag(
      validateFlag,
      negatable: false,
      help: 'Validate packages and indicate whether --publish would publish '
          'anything.',
    )
    ..addFlag(
      publishFlag,
      negatable: false,
      help: 'Publish any changed packages.',
    )
    ..addFlag(
      useFlutterFlag,
      negatable: true,
      help: 'Whether this is a Flutter project.',
    )
    ..addMultiOption(
      'ignore-packages',
      help: 'Which packages to ignore.',
    );
}
