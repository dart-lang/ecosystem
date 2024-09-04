// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

String? _envFileTokenOrEnvironment({required String key}) {
  final envFile = File('.env');
  if (envFile.existsSync()) {
    final env = <String, String>{};
    for (var line in envFile.readAsLinesSync().map((line) => line.trim())) {
      if (line.isEmpty || line.startsWith('#')) continue;
      var split = line.indexOf('=');
      env[line.substring(0, split).trim()] = line.substring(split + 1).trim();
    }
    return env[key];
  } else {
    return Platform.environment[key];
  }
}

String get githubToken {
  var token = _envFileTokenOrEnvironment(key: 'GITHUB_TOKEN');
  if (token == null) {
    throw StateError('This tool expects a github access token in the '
        'GITHUB_TOKEN environment variable.');
  }
  return token;
}

String get geminiKey {
  var token = _envFileTokenOrEnvironment(key: 'GOOGLE_API_KEY');
  if (token == null) {
    throw StateError('This tool expects a gemini api key in the '
        'GOOGLE_API_KEY environment variable.');
  }
  return token;
}

/// Maximal length of body used for querying.
const bodyLengthLimit = 10 * 1024;

/// The [body], truncated if larger than [bodyLengthLimit].
String trimmedBody(String body) {
  return body.length > bodyLengthLimit
      ? body = body.substring(0, bodyLengthLimit)
      : body;
}

class Logger {
  void log(String message) {
    print(message);
  }
}
