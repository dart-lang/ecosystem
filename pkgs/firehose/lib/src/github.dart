// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// TODO:(devoncarew): Consider replacing some of this class with package:github.

class Github {
  static Map<String, String> get _env => Platform.environment;

  http.Client? _httpClient;

  String? get githubAuthToken => _env['GITHUB_TOKEN'];

  /// The owner and repository name. For example, `octocat/Hello-World`.
  String? get repoSlug => _env['GITHUB_REPOSITORY'];

  /// The PR (or issue) number.
  String? get issueNumber => _env['ISSUE_NUMBER'];

  /// The commit SHA that triggered the workflow.
  String? get sha => _env['GITHUB_SHA'];

  /// The name of the person or app that initiated the workflow.
  String? get actor => _env['GITHUB_ACTOR'];

  /// Whether we're running withing the context of a GitHub action.
  bool get inGithubContext => Platform.environment['GITHUB_ACTIONS'] != null;

  /// The short ref name of the branch or tag that triggered the workflow run.
  /// This value matches the branch or tag name shown on GitHub. For example,
  /// `feature-branch-1`.
  String? get refName => Platform.environment['GITHUB_REF_NAME'];

  http.Client get httpClient => _httpClient ??= http.Client();

  Future<String> callRestApiGet(Uri uri) async {
    var token = githubAuthToken!;

    return httpClient.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
    }).then((response) {
      return response.statusCode != 200
          ? throw RpcException(response.reasonPhrase!)
          : response.body;
    });
  }

  Future<String> callRestApiPost(Uri uri, String body) async {
    var token = githubAuthToken!;

    return httpClient
        .post(uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
            },
            body: body)
        .then((response) {
      return response.statusCode != 201
          ? throw RpcException(response.reasonPhrase!)
          : response.body;
    });
  }

  Future<String> callRestApiPatch(Uri uri, String body) async {
    var token = githubAuthToken!;

    return httpClient
        .patch(uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
            },
            body: body)
        .then((response) {
      return response.statusCode != 200
          ? throw RpcException(response.reasonPhrase!)
          : response.body;
    });
  }

  Future<void> callRestApiDelete(Uri uri) async {
    var token = githubAuthToken!;

    return httpClient.delete(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
    }).then((response) {
      if (response.statusCode != 204) {
        throw RpcException(response.reasonPhrase!);
      }
    });
  }

  /// Create a new comment on the given PR.
  Future<String> createComment(
      String repoSlug, String issueNumber, String commentText) async {
    var result = await callRestApiPost(
      Uri.parse(
          'https://api.github.com/repos/$repoSlug/issues/$issueNumber/comments'),
      jsonEncode({'body': commentText}),
    );
    var json = jsonDecode(result) as Map;
    return json['url'] as String;
  }

  /// Find a comment on the PR matching the given criteria ([user],
  /// [searchTerm]). Return the issue ID if a matching comment is found or null
  /// if there's no match.
  Future<int?> findCommentId(
    String repoSlug,
    String issueNumber, {
    required String user,
    String? searchTerm,
  }) async {
    var result = await callRestApiGet(
      Uri.parse('https://api.github.com/repos/$repoSlug/issues/$issueNumber/'
          'comments?per_page=100'),
    );

    var items = jsonDecode(result) as List;
    for (var item in items) {
      item as Map;
      var id = item['id'] as int;
      var userLogin = (item['user'] as Map)['login'] as String;
      var body = item['body'] as String;

      if (userLogin != user) continue;
      if (searchTerm != null && !body.contains(searchTerm)) continue;

      return id;
    }

    return null;
  }

  /// Update the given PR comment with new text.
  Future<String> updateComment(
      String repoSlug, int commentId, String commentText) async {
    var result = await callRestApiPatch(
      Uri.parse(
          'https://api.github.com/repos/$repoSlug/issues/comments/$commentId'),
      jsonEncode({'body': commentText}),
    );
    var json = jsonDecode(result) as Map;
    return json['url'] as String;
  }

  Future<void> deleteComment(String repoSlug, int commentId) async {
    await callRestApiDelete(Uri.parse(
        'https://api.github.com/repos/$repoSlug/issues/comments/$commentId'));
  }

  void close() {
    _httpClient?.close();
  }
}

class RpcException implements Exception {
  final String message;

  RpcException(this.message);

  @override
  String toString() => 'RpcException: $message';
}
