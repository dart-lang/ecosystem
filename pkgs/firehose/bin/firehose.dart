// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

void main() {
  stderr.writeln(
    'The `firehose` CLI executable is deprecated.\n'
    '- To run PR health and publish verification checks, use:\n'
    '  dart run firehose:health --check publish\n'
    '- To publish packages, use '
    'dart-lang/setup-dart/.github/workflows/publish.yml.',
  );
  exitCode = 1;
}
