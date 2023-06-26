// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/firehose.dart';
import 'package:firehose/src/github.dart';

void main(List<String> arguments) async {
  var argParser = _createArgs();
  try {
    var argResults = argParser.parse(arguments);

    if (argResults['help'] == true) {
      _usage(argParser);
      exit(0);
    }

    var validate = argResults['validate'] == true;
    var publish = argResults['publish'] == true;
    var health = argResults['health'] == true;

    if (!validate && !publish && !health) {
      _usage(argParser, error: '''
Error: one of --validate, --publish, or --health must be specified.''');
      exit(1);
    }

    var github = Github();
    if (publish && !github.inGithubContext) {
      _usage(argParser,
          error: 'Error: --publish can only be executed from within a GitHub '
              'action.');
      exit(1);
    }

    var firehose = Firehose(Directory.current);

    if (validate) {
      await firehose.validate();
    } else if (publish) {
      await firehose.publish();
    } else if (health) {
      await firehose.healthCheck();
    }
  } on ArgParserException catch (e) {
    _usage(argParser, error: e.message);
    exit(1);
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
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print tool help.',
    )
    ..addFlag(
      'validate',
      negatable: false,
      help: 'Validate packages and indicate whether --publish would publish '
          'anything.',
    )
    ..addFlag(
      'health',
      negatable: false,
      help: 'Check PR health.',
    )
    ..addFlag(
      'publish',
      negatable: false,
      help: 'Publish any changed packages.',
    );
}
