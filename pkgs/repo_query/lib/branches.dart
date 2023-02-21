// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'src/common.dart';

class BranchesCommand extends ReportCommand {
  BranchesCommand()
      : super('branches',
            'Show the default branch names of Dart and Flutter repos.');

  @override
  Future<int> run() async {
    print('Repository, Default branch, Stars');

    for (var org in ['dart-lang', 'flutter']) {
      var repos = getReposForOrg(org);

      await repos.forEach((repo) {
        print('$org/${repo.name}, ${repo.defaultBranch}, '
            '${repo.stargazersCount}');
      });
    }

    return 0;
  }
}
