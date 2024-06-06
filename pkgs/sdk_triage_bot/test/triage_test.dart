// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:github/github.dart';
import 'package:sdk_triage_bot/triage.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  test('triages issue', () async {
    final githubService = GithubServiceMock();
    final geminiService = GeminiServiceStub();

    await triage(
      mockIssueNumber,
      githubService: githubService,
      geminiService: geminiService,
    );

    expect(githubService.updatedComment, isNotEmpty);
    expect(githubService.updatedComment, contains('Lorem ipsum'));
    expect(githubService.updatedLabels, contains(startsWith('area-')));
    expect(githubService.updatedLabels, contains('triage-automation'));
  });

  test('skips triaged issues', () async {
    final githubService = GithubServiceMock();
    final geminiService = GeminiServiceStub();

    githubService.returnedIssue = Issue(
      url: 'https://github.com/dart-lang/sdk/issues/55869',
      title: 'Add full support for service ID zones',
      number: mockIssueNumber,
      body: 'Lorem ipsum.',
      labels: [IssueLabel(name: 'area-vm')],
    );

    await triage(
      mockIssueNumber,
      githubService: githubService,
      geminiService: geminiService,
    );

    expect(githubService.updatedComment, isNull);
    expect(githubService.updatedLabels, isNull);
  });

  test('respects --force flag', () async {
    final githubService = GithubServiceMock();
    final geminiService = GeminiServiceStub();

    githubService.returnedIssue = Issue(
      url: 'https://github.com/dart-lang/sdk/issues/55869',
      title: 'Add full support for service ID zones',
      number: mockIssueNumber,
      body: 'Lorem ipsum.',
      labels: [IssueLabel(name: 'area-vm')],
    );

    await triage(
      mockIssueNumber,
      githubService: githubService,
      geminiService: geminiService,
      force: true,
    );

    expect(githubService.updatedComment, isNotEmpty);
    expect(githubService.updatedComment, contains('Lorem ipsum'));
    expect(githubService.updatedLabels, contains(startsWith('area-')));
    expect(githubService.updatedLabels, contains('triage-automation'));
  });
}
