import 'package:test/test.dart';

import '../bin/quest.dart';

void main() {
  test('test name', () async {
    final chronicles =
        await FakeQuest('intl', '^0.20.0', Level.analyze, '').embark();
    print(chronicles);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class FakeQuest extends Quest {
  final locations = {
    'https://github.com/mosuem/my_app_old_web':
        '/home/mosum/projects/ecosystem_testing/my_app_old_web/',
    'https://github.com/mosuem/my_app_new_web':
        '/home/mosum/projects/ecosystem_testing/my_app_new_web/',
  };

  FakeQuest(
    super.candidatePackage,
    super.version,
    super.level,
    super.repositoriesFile,
  );

  @override
  Future<String> cloneRepo(String repository) async {
    return locations[repository]!;
  }

  @override
  Future<Iterable<String>> getRepositories() async => <String>[
    'https://github.com/mosuem/my_app_old_web',
    'https://github.com/mosuem/my_app_new_web',
  ];
}
