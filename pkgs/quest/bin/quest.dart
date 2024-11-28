import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:firehose/firehose.dart' as fire;

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final repositoriesFile = arguments[0];
  print(arguments[1]);
  final lines = arguments[1].split('\n');
  final labels = lines
      .sublist(1, lines.length - 1)
      .map((e) => e.trim())
      .where((line) => line.startsWith('ecosystem-test'));
  print('Labels: $labels');
  final packages = fire.Repository().locatePackages();
  final package = packages.firstWhereOrNull((package) =>
      labels.any((label) => label == 'ecosystem-test-${package.name}'));
  if (package != null) {
    print('Found $package. Embark on a quest!');
    final chronicles =
        await Quest(package.name, package.version!.toString(), repositoriesFile)
            .embark();
    final comment = createComment(chronicles);
    await writeComment(comment);
    print(chronicles);
  }
}

enum Level { solve, analyze, test }

class Chronicles {
  final String package;
  final String version;
  final List<Chapter> chapters;

  Chronicles(this.package, this.version, this.chapters);

  @override
  String toString() {
    return '''
Chronicles(package: $package, version: $version, chapters: $chapters)''';
  }
}

class Chapter {
  final Repository repository;
  final Map<Level, bool> successBefore;
  final Map<Level, bool> successAfter;

  Chapter(this.repository, this.successBefore, this.successAfter);

  @override
  String toString() {
    return '''
Chapter(packageName: ${repository.name}, packageUri: ${repository.url}, successBefore: $successBefore, successAfter: $successAfter)''';
  }
}

class Repository {
  final String url;
  final String name;
  final Level level;

  const Repository({
    required this.url,
    required this.name,
    required this.level,
  });

  static Future<Iterable<Repository>> listFromFile(String path) async {
    final s = await File(path).readAsString();
    return (jsonDecode(s) as Map)
        .entries
        .where((e) => e.key != r'$schema')
        .map((e) => MapEntry(e.key as String, e.value as Map))
        .map((e) {
      return Repository(
        url: e.key,
        name: (e.value['name'] as String?) ?? p.basename(e.key),
        level: Level.values.firstWhere((l) => l.name == e.value['level']),
      );
    });
  }

  @override
  String toString() => 'Repository(url: $url, name: $name, level: $level)';
}

class Quest {
  final String candidatePackage;
  final String version;
  final String repositoriesFile;

  Quest(this.candidatePackage, this.version, this.repositoriesFile);

  Future<Chronicles> embark() async {
    final chapters = <Chapter>[];
    for (var repository in await Repository.listFromFile(repositoriesFile)) {
      final path = await cloneRepo(repository.url);
      print('Cloned $repository');
      final processResult = await Process.run(
          'flutter',
          [
            'pub',
            'deps',
            '--json',
          ],
          workingDirectory: path);
      final depsListResult = processResult.stdout as String;
      print(depsListResult);
      final depsJson =
          jsonDecode(depsListResult.substring(depsListResult.indexOf('{')))
              as Map<String, dynamic>;
      final depsPackages = depsJson['packages'] as List;
      print(depsPackages);
      if (depsPackages.any((p) => (p as Map)['name'] == candidatePackage)) {
        print('Run checks for vanilla package');
        final successBefore = await runChecks(path, repository.level);

        print('Clean repo');
        await runFlutter(['clean'], path);

        print('Rev package:$candidatePackage to version $version $repository');
        final revSuccess = await runFlutter([
          'pub',
          'add',
          "$candidatePackage:'$version'",
        ], path);

        print('Run checks for modified package');
        final successAfter = await runChecks(path, repository.level);
        successAfter.update(
          Level.solve,
          (value) => value ? revSuccess : value,
          ifAbsent: () => revSuccess,
        );
        chapters.add(Chapter(repository, successBefore, successAfter));
      } else {
        print('No package:$candidatePackage found in $repository');
      }
    }
    return Chronicles(candidatePackage, version, chapters);
  }

  Future<String> cloneRepo(String url) async {
    var path = url.split('/').last;
    if (Directory(path).existsSync()) {
      path = '${path}_${url.hashCode}';
    }
    await Process.run('gh', ['repo', 'clone', url, '--', path]);
    return path;
  }

  Future<Map<Level, bool>> runChecks(String path, Level level) async {
    final success = <Level, bool>{};
    success[Level.solve] = await runFlutter(['pub', 'get'], path);
    if (level.index >= Level.analyze.index) {
      success[Level.analyze] = await runFlutter(['analyze'], path);
    }
    if (level.index >= Level.test.index) {
      success[Level.test] = await runFlutter(['test'], path);
    }
    return success;
  }

  Future<bool> runFlutter(List<String> arguments, String path) async {
    final processResult = await Process.run(
      'flutter',
      arguments,
      workingDirectory: path,
    );
    print('${processResult.stdout}');
    print('${processResult.stderr}');
    return processResult.exitCode == 0;
  }
}

Future<void> writeComment(String content) async {
  final commentFile = File('output/comment.md');
  await commentFile.create(recursive: true);
  await commentFile.writeAsString(content);
}

String createComment(Chronicles chronicles) {
  final contents = '''
## Ecosystem testing summary


| Package | Solve | Analyze | Test |
| ------- | ----- | ------- | ---- |
${chronicles.chapters.map((e) => '| ${e.repository.name} | ${Level.values.map((l) => '${e.successBefore[l]?.toEmoji ?? '-'}/${e.successAfter[l]?.toEmoji ?? '-'}').join(' | ')} |').join('\n')}
  
  ''';
  return contents;
}

extension on bool {
  String get toEmoji {
    if (this) {
      return '✅';
    } else {
      return '❌';
    }
  }
}
