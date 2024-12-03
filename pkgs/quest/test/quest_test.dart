// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/quest.dart';

void main() {
  test('test name', () async {
    final locations = {
      'https://github.com/mosuem/my_app_old_web':
          '/home/mosum/projects/ecosystem_testing/my_app_old_web/',
      'https://github.com/mosuem/my_app_new_web':
          '/home/mosum/projects/ecosystem_testing/my_app_new_web/',
    };
    final temp = await Directory.systemTemp.createTemp();
    final repoFile = await File(p.join(temp.path, 'repos.json')).create();
    await repoFile.writeAsString(
      jsonEncode({
        'https://github.com/mosuem/my_app_old_web': {'level': 'analyze'},
        'https://github.com/mosuem/my_app_new_web': {'level': 'test'},
      }),
    );
    final tempLocations = locations.map((key, value) {
      final path = p.join(temp.path, p.basename(value));
      copyPathSync(value, path);
      return MapEntry(key, path);
    });

    final chronicles = await FakeQuest(
      'intl',
      'intl:{"git":{"url":"https://github.com/mosuem/i18n","ref":"pr","path":"pkgs/intl"}}',
      repoFile.path,
      tempLocations,
    ).embark();

    final comment = createComment(chronicles);
    print(comment);
    await temp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class FakeQuest extends Quest {
  final Map<String, String> locations;

  FakeQuest(
    super.candidatePackage,
    super.version,
    super.repositoriesFile,
    this.locations,
  );

  @override
  Future<String> cloneRepo(String url) async => locations[url]!;
}
