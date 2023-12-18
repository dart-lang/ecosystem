// ignore_for_file: public_member_api_docs, sort_constructors_first
// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'repo.dart';

class GithubApi {
  final RepositorySlug? _repoSlug;

  final int? _issueNumber;

  static Map<String, String> get _env => Platform.environment;

  /// When true, details of any RPC error are printed to the console.
  final bool verbose;

  GithubApi({this.verbose = false, RepositorySlug? repoSlug, int? issueNumber})
      : _repoSlug = repoSlug,
        _issueNumber = issueNumber;

  final http.Client client = http.Client();

  late GitHub github = githubAuthToken != null
      ? GitHub(
          auth: Authentication.withToken(githubAuthToken),
          client: client,
        )
      : GitHub(client: client);

  String? get githubAuthToken => _env['GITHUB_TOKEN'];

  /// The owner and repository name. For example, `octocat/Hello-World`.
  RepositorySlug? get repoSlug {
    return _repoSlug ??
        (_env['GITHUB_REPOSITORY'] != null
            ? RepositorySlug.full(_env['GITHUB_REPOSITORY']!)
            : null);
  }

  /// The PR (or issue) number.
  int? get issueNumber =>
      _issueNumber ?? int.tryParse(_env['ISSUE_NUMBER'] ?? '');

  /// Any labels applied to this PR.
  List<String> get prLabels =>
      _env.containsKey('PR_LABELS') ? _env['PR_LABELS']!.split(',') : [];

  /// The commit SHA that triggered the workflow.
  String? get sha => _env['GITHUB_SHA'];

  /// The name of the person or app that initiated the workflow.
  String? get actor => _env['GITHUB_ACTOR'];

  /// Whether we're running withing the context of a GitHub action.
  bool get inGithubContext => _env['GITHUB_ACTIONS'] != null;

  /// The short ref name of the branch or tag that triggered the workflow run.
  /// This value matches the branch or tag name shown on GitHub. For example,
  /// `feature-branch-1`.
  String? get refName => _env['GITHUB_REF_NAME'];

  /// The ref name of the base where the PR branched off of.
  String? get baseRef => _env['base_ref'];

  /// Write the given [markdownSummary] content to the GitHub
  /// `GITHUB_STEP_SUMMARY` file. This will cause the markdown output to be
  /// appended to the GitHub job summary for the current PR.
  ///
  /// See also:
  /// https://docs.github.com/en/actions/learn-github-actions/variables.
  void appendStepSummary(String markdownSummary) {
    var summaryPath = _env['GITHUB_STEP_SUMMARY'];
    if (summaryPath == null) {
      stderr.writeln("'GITHUB_STEP_SUMMARY' doesn't exist.");
      return;
    }

    var file = File(summaryPath);
    file.writeAsStringSync('${markdownSummary.trimRight()}\n\n',
        mode: FileMode.append);
  }

  /// Find a comment on the PR matching the given criteria ([user],
  /// [searchTerm]). Return the issue ID if a matching comment is found or null
  /// if there's no match.
  Future<int?> findCommentId({
    required String user,
    String? searchTerm,
  }) async {
    final matchingComment = await github.issues
        .listCommentsByIssue(repoSlug!, issueNumber!)
        .map<IssueComment?>((comment) => comment)
        .firstWhere(
      (comment) {
        final userMatch = comment?.user?.login == user;
        final containsSearchTerm = searchTerm == null ||
            (comment?.body?.contains(searchTerm) ?? false);
        return userMatch && containsSearchTerm;
      },
      orElse: () => null,
    );
    return matchingComment?.id;
  }

  Future<List<GitFile>> listFilesForPR() async => await github.pullRequests
      .listFiles(repoSlug!, issueNumber!)
      .map((prFile) =>
          GitFile(prFile.filename!, FileStatus.fromString(prFile.status!)))
      .toList();

  /// Write a notice message to the github log.
  void notice({required String message}) {
    print('::notice ::$message');
  }

  Future<String> pullrequestBody() async {
    final pullRequest = await github.pullRequests.get(repoSlug!, issueNumber!);
    return pullRequest.body ?? '';
  }

  void close() => github.dispose();
}

class GitFile {
  final String filename;
  final FileStatus status;

  bool isInPackage(Package package) {
    print('Check if $relativePath is in ${package.directory.path}');
    return path.isWithin(package.directory.path, relativePath);
  }

  GitFile(this.filename, this.status);

  String get relativePath =>
      path.relative(filename, from: Directory.current.path);

  @override
  String toString() => '$filename: $status';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GitFile &&
        other.filename == filename &&
        other.status == status;
  }

  @override
  int get hashCode => filename.hashCode ^ status.hashCode;
}

enum FileStatus {
  added,
  removed,
  modified,
  renamed,
  copied,
  changed,
  unchanged;

  static FileStatus fromString(String s) =>
      FileStatus.values.firstWhere((element) => element.name == s);
}
