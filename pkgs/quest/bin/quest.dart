// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:firehose/firehose.dart' as fire;
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final repositoriesFile = arguments[0];
  var gitUri = arguments[1].replaceRange(0, 'git'.length, 'https');
  gitUri = gitUri.substring(0, gitUri.length - '.git'.length);
  final branch = arguments[2];
  final lines = arguments[3].split('\n');
  final labels = lines
      .sublist(1, lines.length - 1)
      .map((e) => e.trim())
      .where((line) => line.startsWith('ecosystem-test'));
  print('Labels: $labels');
  final packages = fire.Repository().locatePackages();
  //TODO: Possibly run for all packages, not just the first.
  final package = packages.firstWhereOrNull((package) =>
      labels.any((label) => label == 'ecosystem-test-${package.name}'));
  if (package != null) {
    print('Found $package. Embark on a quest!');
    final version = '${package.name}:${json.encode({
          'git': {
            'url': gitUri,
            'ref': branch,
            'path':
                p.relative(package.directory.path, from: Directory.current.path)
          }
        })}';
    final chronicles = await Quest(
      package.name,
      version,
      repositoriesFile,
    ).embark();
    final comment = createComment(chronicles);
    await writeComment(comment);
    print(chronicles);
    exitCode = chronicles.success ? 0 : 1;
  }
}

enum Level {
  solve,
  analyze,
  test;
}

/// The result of embarking on a quest. Stores the [package] which was tested
/// with its new [version] as well as the [chapters] of the chronicles, each
/// storing the result of testing a single [Application].
class Chronicles {
  final String package;
  final String version;
  final Map<Application, Chapter> chapters;

  Chronicles(this.package, this.version, this.chapters);

  bool get success => chapters.values.every((chapter) => chapter.success);

  @override
  String toString() {
    return '''
Chronicles(package: $package, version: $version, chapters: $chapters)''';
  }
}

/// An individual chapter in the [Chronicles]. This stores the result of testing
///  against an individual [Application].
class Chapter {
  final Map<Level, CheckResult> before;
  final Map<Level, CheckResult> after;

  Chapter({required this.before, required this.after});

  bool get success => failure == null;

  Level? get failure => Level.values.firstWhereOrNull((level) =>
      before[level]?.success == true && after[level]?.success == false);

  String toRow(Application application) => '''
| ${application.name} | ${Level.values.map((l) => '${before[l]?.success.toEmoji ?? '-'}/${after[l]?.success.toEmoji ?? '-'}').join(' | ')} |''';

  @override
  String toString() => 'Chapter(before: $before, after: $after)';
}

/// A success bool paired with the stdout and stderr for easier debugging.
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

/// An application to test against, specified by the [url] where it can be
/// cloned from, its [name] for display purposes, and the maximum [level] it
/// should be tested to.
class Application {
  final String url;
  final String name;
  final Level level;

  const Application({
    required this.url,
    required this.name,
    required this.level,
  });

  static Future<Iterable<Application>> listFromFile(String path) async {
    final s = await File(path).readAsString();
    return (jsonDecode(s) as Map)
        .entries
        .where((e) => e.key != r'$schema')
        .map((e) => MapEntry(e.key as String, e.value as Map))
        .map((e) {
      return Application(
        url: e.key,
        name: (e.value['name'] as String?) ?? p.basename(e.key),
        level: Level.values.firstWhere((l) => l.name == e.value['level']),
      );
    });
  }

  @override
  String toString() => 'Repository(url: $url, name: $name, level: $level)';
}

/// Contains the logic to fill [Chronicles] with the [Chapter]s of testing the
/// [candidatePackage] at [version] against the [Application]s listed in the
/// [applicationFile].
class Quest {
  final String candidatePackage;
  final String version;
  final String applicationFile;

  Quest(this.candidatePackage, this.version, this.applicationFile);

  Future<Chronicles> embark() async {
    final tempDir = await Directory.systemTemp.createTemp();
    final chapters = <Application, Chapter>{};
    for (var application in await Application.listFromFile(applicationFile)) {
      final path = await cloneRepo(application.url, tempDir);
      print('Cloned $application into $path');
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
        final resultBefore = await runChecks(path, application.level);

        print('Clean repo');
        await runFlutter(['clean'], path);

        print('Rev package:$candidatePackage to version $version $application');
        final revSuccess =
            await runFlutter(['pub', 'add', version], path, true);

        print('Run checks for modified package');
        final resultAfter = await runChecks(path, application.level);

        // flutter pub add runs an implicit pub get
        resultAfter[Level.solve] = revSuccess;

        chapters[application] = Chapter(
          before: resultBefore,
          after: resultAfter,
        );
      } else {
        print('No package:$candidatePackage found in $application');
      }
    }
    await tempDir.delete(recursive: true);
    return Chronicles(candidatePackage, version, chapters);
  }

  /// Uses `gh` to clone the Github repo at [url].
  Future<String> cloneRepo(String url, Directory tempDir) async {
    final name = url.split('/').last;

    var fullPath = p.join(tempDir.path, name);
    if (Directory(fullPath).existsSync()) {
      fullPath = p.join(tempDir.path, '${name}_${url.hashCode}');
    }
    await Process.run('gh', ['repo', 'clone', url, '--', fullPath]);
    return fullPath;
  }

  /// Uses `gh` to clone the Github repo at [url].
  Future<Map<Level, CheckResult>> runChecks(String path, Level level) async {
    final result = <Level, CheckResult>{};
    result[Level.solve] = await runFlutter(['pub', 'get'], path);
    if (level.index >= Level.analyze.index &&
        result[Level.solve]?.success == true) {
      result[Level.analyze] = await runFlutter(['analyze'], path);
    }
    if (level.index >= Level.test.index &&
        result[Level.solve]?.success == true) {
      result[Level.test] = await runFlutter(['test'], path);
    }
    return result;
  }

  Future<CheckResult> runFlutter(
    List<String> arguments,
    String path, [
    bool useDart = false,
  ]) async {
    final executable = useDart ? 'dart' : 'flutter';
    print('Running `$executable ${arguments.join(' ')}` in $path');
    final processResult = await Process.run(
      //Due to https://github.com/flutter/flutter/issues/144898, we can't run Flutter on `pub add`
      executable,
      arguments,
      workingDirectory: path,
    );
    final stdout = processResult.stdout as String;
    final stderr = processResult.stderr as String;
    print('stdout:');
    print(stdout);
    print('stderr:');
    print(stderr);
    return CheckResult(
      success: processResult.exitCode == 0,
      stdout: stdout,
      stderr: stderr,
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
${chronicles.chapters.entries.map((chapter) => chapter.value.toRow(chapter.key)).join('\n')}

<details>
<summary>
<strong>Details per app</strong>
</summary>
${chronicles.chapters.entries.map((entry) {
    final application = entry.key;
    final chapter = entry.value;
    return '''
<details>
<summary>
<strong>${application.name}</strong> ${chapter.success ? '✅' : '❌'}
</summary>

${chapter.success ? 'The app tests passed!' : '''
The failure occured at the "${chapter.failure!.name}" step, this is the error output of that step:
```
${chapter.after[chapter.failure!]?.stderr}
```
'''}

The complete list of logs is:

${chapter.before.keys.map((level) => '''
<details>
<summary>
<strong>Logs for step: ${level.name}</strong>
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

''';
  }).join('\n')}

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
