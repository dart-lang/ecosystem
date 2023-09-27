// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

class Pub {
  http.Client? _httpClient;

  http.Client get httpClient => _httpClient ??= http.Client();

  Future<bool> hasPublishedVersion(String name, String version) async {
    var response =
        await httpClient.get(Uri.parse('https://pub.dev/api/packages/$name'));
    if (response.statusCode != 200) {
      return false;
    }

    var json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['versions'] as List)
        .map((versionObject) =>
            (versionObject as Map<String, dynamic>)['version'])
        .contains(version);
  }

  void close() {
    _httpClient?.close();
  }
}

extension VersionExtension on Version {
  bool get wip {
    return isPreRelease && preRelease.length == 1 && preRelease.first == 'wip';
  }
}
