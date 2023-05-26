// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../repo_tweak.dart';
import '../utils.dart';

final _instance = MonoRepoTweak._();

/// Regenerate the latest configuration files for package:mono_repo.
class MonoRepoTweak extends RepoTweak {
  factory MonoRepoTweak() => _instance;

  MonoRepoTweak._()
      : super(
          id: 'monorepo',
          description:
              'regenerate the latest configuration files for package:mono_repo',
        );

  @override
  bool shouldRunByDefault(Directory checkout, String repoSlug) {
    return File(p.join(checkout.path, 'mono_repo.yaml')).existsSync();
  }

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) async {
    // get the latest mono_repo
    await runProc(
      'activating mono_repo',
      Platform.resolvedExecutable,
      ['pub', 'global', 'activate', 'mono_repo'],
      workingDirectory: checkout.path,
    );

    // record the current values for the files
    final files = {
      '.github/workflows/dart.yml',
      'tool/ci.sh',
    };
    final existingContent = {
      for (var path in files)
        path: File(p.join(checkout.path, path)).existsSync()
            ? File(p.join(checkout.path, path)).readAsStringSync()
            : '',
    };

    // run mono_repo generate
    await runProc(
      'run mono_repo generate',
      Platform.resolvedExecutable,
      ['pub', 'global', 'run', 'mono_repo', 'generate'],
      workingDirectory: checkout.path,
    );

    // return the results
    final fixes = <String>[];

    for (var entry in existingContent.entries) {
      final file = File(p.join(checkout.path, entry.key));
      if (file.readAsStringSync() != entry.value) {
        fixes.add('updated ${entry.key}');
      }
    }

    return fixes.isEmpty ? FixResult.noFixesMade : FixResult(fixes: fixes);
  }
}
