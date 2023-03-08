// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:repo_manage/src/common.dart';

void main(List<String> args) async {
  final runner = ReportCommandRunner();
  exit(await runner.run(args) ?? 0);
}
