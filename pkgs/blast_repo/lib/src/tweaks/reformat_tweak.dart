// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:firehose/firehose.dart';

import '../repo_tweak.dart';
import '../utils.dart';

final _instance = ReformatTweak._();

/// Reformat the Dart files in all packages in a repo.
class ReformatTweak extends RepoTweak {
  factory ReformatTweak() => _instance;

  ReformatTweak._()
      : super(
          id: 'reformat',
          description: 'file a PR for a run of `dart format`',
        );

  @override
  bool shouldRunByDefault(Directory checkout, String repoSlug) => true;

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) async {
    var repo = Repository(checkout);
    var packages = repo.locatePackages();

    final fixes = <String>[];
    for (var package in packages) {
      var exitCode = await runProc(
        'running dart format for ${package.name}',
        Platform.resolvedExecutable,
        ['format', '.', '--set-exit-if-changed'],
        workingDirectory: package.directory.path,
        throwOnFailure: false,
      );
      if (exitCode == 1) {
        fixes.add(package.name);
      }
    }

    return fixes.isEmpty ? FixResult.noFixesMade : FixResult(fixes: fixes);
  }
}
