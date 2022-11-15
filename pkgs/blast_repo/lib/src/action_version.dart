// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

class ActionVersion {
  ActionVersion({
    required this.org,
    required this.repo,
    required this.path,
    required this.version,
  });

  factory ActionVersion.parse(String value) {
    final atSplit = value.split('@');
    if (atSplit.length != 2) {
      throw ArgumentError.value(
        value,
        'value',
        'Should have two halves seperated by "@".',
      );
    }

    final pathSegments = p.url.split(atSplit[0]);

    if (pathSegments.length < 2) {
      throw ArgumentError.value(
        value,
        'value',
        'Should have at least two initial path segments.',
      );
    }

    final path =
        pathSegments.length > 2 ? pathSegments.skip(2).join('/') : null;

    return ActionVersion(
      org: pathSegments[0],
      repo: pathSegments[1],
      path: path,
      version: atSplit[1],
    );
  }

  final String org;
  final String repo;
  final String? path;
  final String version;

  String get fullRepo => '$org/$repo';

  @override
  String toString() =>
      '${[org, repo, if (path != null) path].join('/')}@$version';

  @override
  bool operator ==(Object other) =>
      other is ActionVersion &&
      org == other.org &&
      repo == other.repo &&
      path == other.path &&
      version == other.version;

  @override
  int get hashCode => Object.hash(org, repo, path, version);
}
