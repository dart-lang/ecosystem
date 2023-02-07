// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:github/github.dart';
import 'package:pub_semver/pub_semver.dart';

import 'action_version.dart';

class GitHubActionResolver {
  GitHubActionResolver({required GitHub github}) : _github = github;

  final GitHub _github;

  final _tagCache = <String, List<Tag>>{};
  final _branchCache = <String, List<Branch>>{};

  Future<ActionVersionResolution> resolve(ActionVersion version) async {
    if (version.path != null) {
      throw ArgumentError.value(
        version,
        'version',
        'path is not supported - yet - $version',
      );
    }

    final slug = RepositorySlug(version.org, version.repo);

    final result = await _getTags(slug);

    final matches = result
        .where(
          (element) =>
              element.name == version.version ||
              element.commit.sha == version.version,
        )
        .toList();

    if (matches.isEmpty) {
      // Look for branches?

      final branches = _branchCache[slug.fullName] ??=
          await _github.repositories.listBranches(slug).toList();

      final matchingBranches = branches
          .where(
            (element) =>
                element.name == version.version && element.commit?.sha != null,
          )
          .toList();

      if (matchingBranches.length == 1) {
        return ActionVersionResolution._fromBranch(matchingBranches.single);
      }

      // TODO: if it was a SHA thing coming in, return null?
      throw Exception('No matches found for $version');
    }

    if (matches.length > 1) {
      final mismatches = matches
          .where((element) => element.commit.sha != matches.first.commit.sha)
          .toList();
      if (mismatches.isNotEmpty) {
        throw Exception('This should never happen!');
      }
    }

    final sha = matches.first.commit.sha;

    final shaMatches =
        result.where((element) => element.commit.sha == sha).toList();

    // We want to return the "best" tag. If there is only one match, then fine!
    if (shaMatches.length == 1) {
      return ActionVersionResolution._fromTag(shaMatches.single);
    }

    if (shaMatches.length > 1) {
      final validVersions = shaMatches
          .where((element) => _semVerExpando[element] != null)
          .toList();

      if (validVersions.length == 1) {
        return ActionVersionResolution._fromTag(validVersions.single);
      }
    }

    throw Exception('Too many matches for $version - $shaMatches');
  }

  Future<ActionVersionResolution> latestStable(String repoOrg) async {
    final slug = RepositorySlug.full(repoOrg);

    final tags = await _getTags(slug);

    final versionTags =
        tags.where((element) => _semVerExpando[element] != null).toList();

    final grouped = groupBy(versionTags, (p0) => _semVerExpando[p0]!);

    final allVersions = grouped.keys.toList(growable: false)..sort();

    if (allVersions.isEmpty) {
      throw Exception('Could not figure out "latest" for $repoOrg');
    }

    final latestVersion = allVersions.last;

    final latestTags = grouped[latestVersion]!;

    if (latestTags.length == 1) {
      return ActionVersionResolution._fromTag(latestTags.single);
    }

    final prunedTags = latestTags
        .where((element) => element.name == 'v${_semVerExpando[element]}')
        .toList();

    if (prunedTags.length == 1) {
      return ActionVersionResolution._fromTag(prunedTags.single);
    }

    throw UnimplementedError(
      'We do not have one tag for $repoOrg: $latestTags',
    );
  }

  Future<List<Tag>> _getTags(RepositorySlug slug) async =>
      _tagCache[slug.fullName] ??=
          _process(await _github.repositories.listTags(slug).toList());

  void close() {
    _github.client.close();
  }

  List<Tag> _process(List<Tag> tags) {
    for (var tag in tags) {
      var name = tag.name;
      if (name.startsWith('v')) {
        // Handle the case (with Dart and melos)
        // where we only do vX.Y or vX instead of vX.Y.Z
        // TODO(kevmoo): remove this silly once Dart fixes it's tags
        while ('.'.allMatches(name).length < 2) {
          name = '$name.0';
        }

        try {
          final ver = Version.parse(name.substring(1));
          _semVerExpando[tag] = ver;
        } on FormatException {
          // not a version - skipping
        }
      }
    }
    return tags;
  }
}

class ActionVersionResolution {
  ActionVersionResolution.version({required this.sha, required this.version})
      : branch = null;

  ActionVersionResolution.branch({required this.sha, required this.branch})
      : version = null;

  factory ActionVersionResolution._fromTag(Tag tag) =>
      ActionVersionResolution.version(
        sha: tag.commit.sha!,
        version: _semVerExpando[tag]!,
      );

  factory ActionVersionResolution._fromBranch(Branch branch) =>
      ActionVersionResolution.branch(
        sha: branch.commit!.sha!,
        branch: branch.name!,
      );

  final String sha;
  final Version? version;
  final String? branch;

  @override
  String toString() => '${version ?? branch}::$sha';
}

final _semVerExpando = Expando<Version>();
