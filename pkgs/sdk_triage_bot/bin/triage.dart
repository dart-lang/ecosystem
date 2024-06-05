// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:github/github.dart';
import 'package:http/http.dart' as http;
import 'package:sdk_triage_bot/src/common.dart';
import 'package:sdk_triage_bot/src/gemini.dart';
import 'package:sdk_triage_bot/src/github.dart';
import 'package:sdk_triage_bot/triage.dart';

void main(List<String> arguments) async {
  final argParser = ArgParser();
  argParser.addFlag('dry-run',
      negatable: false,
      help: 'Perform triage but don\'t make any actual changes to the issue.');
  argParser.addFlag('force',
      negatable: false,
      help: 'Make changes to the issue even if it already looks triaged.');
  argParser.addFlag('help',
      abbr: 'h', negatable: false, help: 'Print this usage information.');

  final ArgResults results;
  try {
    results = argParser.parse(arguments);
  } on ArgParserException catch (e) {
    print(e.message);
    print('');
    print(usage);
    print('');
    print(argParser.usage);
    io.exit(64);
  }

  if (results.flag('help') || results.rest.isEmpty) {
    print(usage);
    print('');
    print(argParser.usage);
    io.exit(results.flag('help') ? 0 : 64);
  }

  var issue = results.rest.first;
  final dryRun = results.flag('dry-run');
  final force = results.flag('force');

  // Accept either an issue number or a url (i.e.,
  // https://github.com/dart-lang/sdk/issues/55816).
  const sdkToken = 'dart-lang/sdk/issues/';
  if (issue.contains(sdkToken)) {
    issue = issue.substring(issue.indexOf(sdkToken) + sdkToken.length);
  }

  final client = http.Client();

  final github = GitHub(
    auth: Authentication.withToken(githubToken),
    client: client,
  );
  final githubService = GithubServiceImpl(github: github);

  final geminiService = GeminiServiceImpl(
    apiKey: geminiKey,
    httpClient: client,
  );

  await triage(
    int.parse(issue),
    dryRun: dryRun,
    force: force,
    githubService: githubService,
    geminiService: geminiService,
  );

  client.close();
}

const String usage = '''
A tool to triage issues from https://github.com/dart-lang/sdk.

usage: dart bin/triage.dart [options] <issue>''';
