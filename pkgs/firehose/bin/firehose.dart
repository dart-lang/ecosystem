// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/firehose.dart';
import 'package:glob/glob.dart';

const helpFlag = 'help';
const validateFlag = 'validate';
const validateReleaseFlag = 'validate-release';
const publishFlag = 'publish';
const packageOnlyFlag = 'package-only';
const useFlutterFlag = 'use-flutter';
const tagPrefixOption = 'tag-prefix';
const provenanceFlag = 'provenance';

void main(List<String> arguments) async {
  final argParser = _createArgs();
  try {
    final argResults = argParser.parse(arguments);

    if (argResults[helpFlag] as bool) {
      _usage(argParser);
      return;
    }

    final validate = argResults[validateFlag] as bool;
    final validateRelease = argResults[validateReleaseFlag] as bool;
    final publish = argResults[publishFlag] as bool;
    final packageOnly = argResults[packageOnlyFlag] as bool;
    final useFlutter = argResults[useFlutterFlag] as bool;
    final tagPrefix = argResults[tagPrefixOption] as String;
    final provenance = argResults[provenanceFlag] as bool;
    final ignoredPackages = (argResults['ignore-packages'] as List<String>)
        .where((pattern) => pattern.isNotEmpty)
        .map((pattern) => Glob(pattern, recursive: true))
        .toList();

    if (!validate && !validateRelease && !publish && !packageOnly) {
      _usage(argParser,
          error: 'Error: one of --validate, --validate-release, --publish, or '
              '--package-only must be specified.');
      exitCode = 1;
      return;
    }

    final github = GithubApi();
    if ((validateRelease || publish || packageOnly) &&
        !github.inGithubContext) {
      _usage(argParser,
          error: 'Error: --validate-release, --publish, and --package-only can '
              'only be executed from within a GitHub action.');
      exitCode = 1;
      return;
    }

    final firehose = Firehose(
      Directory.current,
      useFlutter,
      ignoredPackages,
      tagPrefix: tagPrefix,
      provenance: provenance,
    );

    if (validate) {
      await firehose.validate();
    } else if (validateRelease) {
      await firehose.validateRelease();
    } else if (publish) {
      await firehose.publish();
    } else if (packageOnly) {
      await firehose.packageOnly();
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

ArgParser _createArgs() => ArgParser()
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
    validateReleaseFlag,
    negatable: false,
    help: 'Validate the release package with pub publish --dry-run.',
  )
  ..addFlag(
    publishFlag,
    negatable: false,
    help: 'Publish any changed packages.',
  )
  ..addFlag(
    packageOnlyFlag,
    negatable: false,
    help: 'Package the archive for the release tag without publishing.',
  )
  ..addFlag(
    useFlutterFlag,
    negatable: true,
    help: 'Whether this is a Flutter project.',
  )
  ..addOption(
    tagPrefixOption,
    defaultsTo: 'v',
    help: 'The tag prefix to expect and generate (e.g. "v" or "").',
  )
  ..addFlag(
    provenanceFlag,
    negatable: false,
    help: 'Whether to sign packages with build provenance before publishing.',
  )
  ..addMultiOption(
    'ignore-packages',
    help: 'Which packages to ignore.',
  );
