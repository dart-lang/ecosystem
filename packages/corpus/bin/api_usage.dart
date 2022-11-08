// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:corpus/api_usage.dart';

void main(List<String> args) async {
  var argParser = _createArgParser();

  ArgResults argResults;
  try {
    argResults = argParser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print('');
    _printUsage(argParser);
    exit(64);
  }

  if (argResults.rest.length != 1 || argResults['help']) {
    _printUsage(argParser);
    exit(1);
  }

  final packageName = argResults.rest.first;
  final packageLimit =
      int.tryParse(argResults['package-limit'] ?? '') ?? 0x7FFFFFFF;
  bool showSrcReferences = argResults['show-src-references'] as bool;

  await analyzeUsage(
    packageName: packageName,
    packageLimit: packageLimit,
    showSrcReferences: showSrcReferences,
  );
}

ArgParser _createArgParser() {
  var parser = ArgParser();
  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print this usage information.',
  );
  parser.addOption(
    'package-limit',
    aliases: ['limit'],
    help: 'Limit the number of packages usage data is collected from.',
    valueHelp: 'count',
  );
  parser.addFlag(
    'show-src-references',
    negatable: false,
    help: 'Report specific references to src/ libraries.',
  );
  return parser;
}

void _printUsage(ArgParser argParser) {
  print('usage: dart bin/api_usage.dart [options] <package-name>');
  print('');
  print('options:');
  print(argParser.usage);
}
