// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:puppy/src/constants.dart';
import 'package:puppy/src/map_command.dart';

Future<void> main(List<String> args) async {
  var runner = CommandRunner<void>(cmdName, 'Dart repository management tools.')
    ..addCommand(MapCommand());

  await runner.run(args);
}
