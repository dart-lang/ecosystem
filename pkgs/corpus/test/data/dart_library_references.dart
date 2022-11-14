// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

void main() {
  var map = SplayTreeMap<String, int>();
  map['one'] = 1;
  map['two'] = 2;
  map['three'] = 3;
  print(map);

  dynamic local;
  Queue.castFrom(local);
}
