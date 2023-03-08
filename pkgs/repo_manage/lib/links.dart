// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'src/common.dart';

class LinksCommand extends ReportCommand {
  LinksCommand() : super('links', 'List useful GitHub query urls.');

  @override
  Future<int> run() async {
    var inThreeMonths = DateTime.now().subtract(Duration(days: 90));

    print('''
dart-lang P0 issues:
  https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+label%3AP0

dart-lang P1 issues:
  https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+label%3AP1

dart-lang PRs with no review:
  https://github.com/pulls?q=is%3Aopen+is%3Apr+archived%3Afalse+org%3Adart-lang+review%3Anone

dart-lang issues with more than 75 reactions:
  https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+reactions%3A%3E75+sort%3Areactions-%2B1-desc+

dart-lang P1 issues that haven't been updated in 3 months:
  https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+label%3Ap1+updated%3A%3C${inThreeMonths.toIso8601String()}

dart-lang issues with no label:
  https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+no%3Alabel
''');

    return 0;
  }
}
