// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';

GitHub createGitHubClient() => GitHub(
      auth: Authentication.withToken(Platform.environment['GITHUB_TOKEN']),
    );
