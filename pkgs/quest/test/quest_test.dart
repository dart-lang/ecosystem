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
    final tempLocations = locations.map((key, value) {
      final path = p.join(temp.path, p.basename(value));
      copyPathSync(value, path);
      return MapEntry(key, path);
    });

    final chronicles =
        await FakeQuest(
          'intl',
          '^0.20.0',
          Level.analyze,
          '',
          tempLocations,
        ).embark();

    final comment = createComment(chronicles);
    print(comment);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class FakeQuest extends Quest {
  final Map<String, String> locations;

  FakeQuest(
    super.candidatePackage,
    super.version,
    super.level,
    super.repositoriesFile,
    this.locations,
  );

  @override
  Future<String> cloneRepo(String repository) async {
    return locations[repository]!;
  }

  @override
  Future<Iterable<String>> getRepositories(String file) async => locations.keys;
}
