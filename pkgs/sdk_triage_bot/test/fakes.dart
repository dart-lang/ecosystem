// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:github/github.dart';
import 'package:sdk_triage_bot/src/common.dart';
import 'package:sdk_triage_bot/src/gemini.dart';
import 'package:sdk_triage_bot/src/github.dart';
import 'package:test/test.dart';

const int mockIssueNumber = 123;

class GithubServiceMock implements GithubService {
  @override
  Future<List<String>> getAllLabels(RepositorySlug repoSlug) async {
    return ['area-analyzer', 'area-vm', 'type-enhancement', 'type-bug'];
  }

  Issue returnedIssue = Issue(
    url: 'https://github.com/dart-lang/sdk/issues/55869',
    title: 'Add full support for service ID zones',
    number: mockIssueNumber,
    body: 'Lorem ipsum.',
    labels: [],
  );

  @override
  Future<Issue> fetchIssue(RepositorySlug sdkSlug, int issueNumber) async {
    return returnedIssue;
  }

  @override
  Future<List<IssueComment>> fetchIssueComments(
      RepositorySlug slug, Issue issue) {
    return Future.value([]);
  }

  String? updatedComment;

  @override
  Future createComment(
      RepositorySlug sdkSlug, int issueNumber, String comment) async {
    updatedComment = comment;
  }

  List<String>? updatedLabels;

  @override
  Future addLabelsToIssue(
      RepositorySlug sdkSlug, int issueNumber, List<String> newLabels) async {
    updatedLabels = newLabels;
  }
}

class GeminiServiceStub implements GeminiService {
  @override
  Future<String> summarize(String prompt) async {
    return 'Lorem ipsum.';
  }

  @override
  Future<List<String>> classify(String prompt) async {
    return ['area-vm', 'type-bug'];
  }
}

class TestLogger implements Logger {
  @override
  void log(String message) {
    printOnFailure(message);
  }
}
