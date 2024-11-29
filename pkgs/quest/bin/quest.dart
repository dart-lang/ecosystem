import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:firehose/firehose.dart' as fire;
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final repositoriesFile = arguments[0];
  final gitUri = arguments[1];
  final branch = arguments[2];
  final lines = arguments[3].split('\n');
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
    final version = '''
'${package.name}:{"git":{"url":"$gitUri","ref":"$branch","path":"${p.relative(package.directory.path, from: Directory.current.path)}"}}\'''';
    final chronicles = await Quest(
      package.name,
      version,
      repositoriesFile,
    ).embark();
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
  final Map<Level, CheckResult> before;
  final Map<Level, CheckResult> after;

  Chapter(
      {required this.repository, required this.before, required this.after});

  bool get success => failure == null;

  Level? get failure => Level.values.firstWhereOrNull((level) =>
      before[level]?.success == true && after[level]?.success == false);

  String toRow() => '''
| ${repository.name} | ${Level.values.map((l) => '${before[l]?.success.toEmoji ?? '-'}/${after[l]?.success.toEmoji ?? '-'}').join(' | ')} |''';

  @override
  String toString() =>
      'Chapter(repository: $repository, before: $before, after: $after)';
}

class CheckResult {
  final bool success;
  final String stdout;
  final String stderr;

  CheckResult({
    required this.success,
    required this.stdout,
    required this.stderr,
  });

  @override
  String toString() =>
      'ChapterLevel(success: $success, stdout: $stdout, stderr: $stderr)';
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
        final resultBefore = await runChecks(path, repository.level);

        print('Clean repo');
        await runFlutter(['clean'], path);

        print('Rev package:$candidatePackage to version $version $repository');
        final revSuccess =
            await runFlutter(['pub', 'add', version], path, true);

        print('Run checks for modified package');
        final resultAfter = await runChecks(path, repository.level);

        // flutter pub add runs an implicit pub get
        resultAfter[Level.solve] = revSuccess;

        chapters.add(Chapter(
          repository: repository,
          before: resultBefore,
          after: resultAfter,
        ));
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

  Future<Map<Level, CheckResult>> runChecks(String path, Level level) async {
    final success = <Level, CheckResult>{};
    success[Level.solve] = await runFlutter(['pub', 'get'], path);
    if (level.index >= Level.analyze.index) {
      success[Level.analyze] = await runFlutter(['analyze'], path);
    }
    if (level.index >= Level.test.index) {
      success[Level.test] = await runFlutter(['test'], path);
    }
    return success;
  }

  Future<CheckResult> runFlutter(List<String> arguments, String path,
      [bool useDart = false]) async {
    print('Running `flutter ${arguments.join(' ')}` in $path');
    final processResult = await Process.run(
      //Due to https://github.com/flutter/flutter/issues/144898, we can't run Flutter on `pub add`
      useDart ? 'dart' : 'flutter',
      arguments,
      workingDirectory: path,
    );
    return CheckResult(
      success: processResult.exitCode == 0,
      stdout: processResult.stdout as String,
      stderr: processResult.stderr as String,
    );
  }
}

Future<void> writeComment(String content) async {
  final commentFile = File('output/comment.md');
  await commentFile.create(recursive: true);
  await commentFile.writeAsString(content);
}

String createComment(Chronicles chronicles) {
  final contents = '''
## Ecosystem testing

| Package | Solve | Analyze | Test |
| ------- | ----- | ------- | ---- |
${chronicles.chapters.map((chapter) => chapter.toRow()).join('\n')}

<details>
<summary>
<strong>Details per app</strong>
</summary>
${chronicles.chapters.map((chapter) => '''
<details>
<summary>
<strong>${chapter.repository.name}</strong> ${chapter.success ? '✅' : '❌'};
</summary>

${chapter.success ? 'The app tests passed!' : '''
The failure occured at ${chapter.failure!.name}, this is the error output of that step:
```
${chapter.after[chapter.failure!]?.stderr}
```
'''}

The complete list of logs is:

${chapter.before.keys.map((level) => '''
<details>
<summary>
<strong>Logs for ${level.name}</strong>
</summary>


### Before:

StdOut:
```
${chapter.before[level]?.stdout}
```

StdErr:
```
${chapter.before[level]?.stderr}
```

### After:

StdOut:
```
${chapter.after[level]?.stdout}
```

StdErr:
```
${chapter.after[level]?.stderr}
```

</details>
''').join('\n')}

</details>

''').join('\n')}

</details>
  
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
