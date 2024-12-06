// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/canary.dart';

void main() {
  test('test name', () async {
    final temp = await Directory.systemTemp.createTemp();
    final repoFile = await File(p.join(temp.path, 'repos.json')).create();
    await repoFile.writeAsString(
      jsonEncode({
        'https://github.com/mosuem/my_app_old_web': {'level': 'analyze'},
        'https://github.com/mosuem/my_app_new_web': {'level': 'test'},
      }),
    );

    final mineAirQuality = await Canary(
      'intl',
      'intl:{"git":{"url":"https://github.com/mosuem/i18n","ref":"pr","path":"pkgs/intl"}}',
      repoFile.path,
    ).intoTheMine();

    final comment = createComment(mineAirQuality);
    expect(comment, startsWith(goldenComment));
    await temp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

final goldenComment = '''
## Ecosystem testing

| Package | Solve | Analyze | Test |
| ------- | ----- | ------- | ---- |
| my_app_old_web | $checkEmoji/$crossEmoji | $checkEmoji/$checkEmoji | -/- |
| my_app_new_web | $checkEmoji/$checkEmoji | $checkEmoji/$checkEmoji | $checkEmoji/$checkEmoji |
''';
