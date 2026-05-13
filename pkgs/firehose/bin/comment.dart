// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/github.dart';

Future<void> main(List<String> arguments) async {
  final parser = _createArgParser();

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on ArgParserException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return;
  }

  final command = results.command;

  if (command == null) {
    stderr.writeln('Usage: comment <command> [options]');
    stderr.writeln(parser.usage);
    stderr.writeln('\nAvailable commands:');
    for (final cmd in parser.commands.keys) {
      stderr.writeln('  $cmd');
    }
    exitCode = 64;
    return;
  }

  if (command.name == 'find') {
    await _findComment(command);
  } else if (command.name == 'create-or-update') {
    await _createOrUpdateComment(command);
  }
}

ArgParser _createArgParser() {
  final parser = ArgParser();

  parser.addCommand('find')
    ..addOption('issue', help: 'PR or issue number', mandatory: true)
    ..addOption('author',
        help: 'Comment author', defaultsTo: 'github-actions[bot]')
    ..addOption('body-includes', help: 'String to search for in comment body');

  parser.addCommand('create-or-update')
    ..addOption('issue', help: 'PR or issue number')
    ..addOption('comment-id', help: 'Existing comment ID to update')
    ..addOption('body', help: 'Comment body text')
    ..addOption('body-path', help: 'Path to file containing comment body');

  return parser;
}

Future<void> _findComment(ArgResults results) async {
  final issue = results.option('issue') as String;
  final author = results.option('author') as String;
  final bodyIncludes = results.option('body-includes');

  final issueNumber = int.tryParse(issue);
  if (issueNumber == null) {
    stderr.writeln('Invalid issue number: $issue');
    exitCode = 64;
    return;
  }

  final github = GithubApi(issueNumber: issueNumber);
  try {
    final commentId = await github.findCommentId(
      user: author,
      searchTerm: bodyIncludes,
    );

    if (commentId != null) {
      print(commentId);
    } else {
      print('0');
    }
  } finally {
    github.close();
  }
}

Future<void> _createOrUpdateComment(ArgResults results) async {
  final issue = results.option('issue');
  final commentId = results.option('comment-id');
  var body = results.option('body');
  final bodyPath = results.option('body-path');

  if (bodyPath != null) {
    try {
      body = await File(bodyPath).readAsString();
    } catch (e) {
      stderr.writeln('Error reading body-path: $e');
      exitCode = 1;
      return;
    }
  }

  if (body == null || body.trim().isEmpty) {
    stderr.writeln('Comment body cannot be empty');
    exitCode = 64;
    return;
  }

  int? issueNumber;
  if (issue != null) {
    issueNumber = int.tryParse(issue);
    if (issueNumber == null) {
      stderr.writeln('Invalid issue number: $issue');
      exitCode = 64;
      return;
    }
  }
  final github = GithubApi(issueNumber: issueNumber);

  try {
    if (commentId != null && commentId != '0' && commentId.isNotEmpty) {
      final id = int.tryParse(commentId);
      if (id == null) {
        stderr.writeln('Invalid comment ID: $commentId');
        exitCode = 64;
        return;
      }
      await github.updateComment(id, body);
      print('Updated comment $id');
    } else {
      final resolvedIssueNumber = github.issueNumber;
      if (resolvedIssueNumber == null) {
        stderr.writeln('Missing issue number for create');
        exitCode = 64;
        return;
      }
      await github.createComment(resolvedIssueNumber, body);
      print('Created comment');
    }
  } finally {
    github.close();
  }
}
