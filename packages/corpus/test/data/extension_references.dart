// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';

void main() {
  // firstWhereOrNull is on the extension IterableExtension.
  var foo = ['one', 'two', 'three'];
  print(foo.firstWhereOrNull((item) => item == 'four'));
}
