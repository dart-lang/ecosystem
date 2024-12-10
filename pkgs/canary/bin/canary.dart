// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:firehose/firehose.dart' as fire;
import 'package:path/path.dart' as p;

final checkEmoji = '\u2705';
final crossEmoji = '\u274C';

Future<void> main(List<String> arguments) async {
  final repositoriesFile = arguments[0];
  var gitUri = arguments[1].replaceRange(0, 'git'.length, 'https');
  gitUri = gitUri.substring(0, gitUri.length - '.git'.length);
  final branch = arguments[2];
  final labels = arguments[3]
      .split('\n')
      .map((e) => e.trim())
      .where((line) => line.startsWith('ecosystem-test'));
  print('Labels: $labels');
  final packages = fire.Repository().locatePackages();
  //TODO: Possibly run for all packages, not just the first.
  final package = packages.firstWhereOrNull(
    (package) =>
        labels.any((label) => label == 'ecosystem-test-${package.name}'),
  );
  if (package != null) {
    print('Found $package to serve as a canary.');
    final version = '${package.name}:${json.encode({
          'git': {
            'url': gitUri,
            'ref': branch,
            'path': p.relative(
              package.directory.path,
              from: Directory.current.path,
            )
          },
        })}';
    final mineAirQuality =
        await Canary(package.name, version, repositoriesFile).intoTheMine();
    final comment = createComment(mineAirQuality);
    await writeComment(comment);
    print(mineAirQuality);
    exitCode = mineAirQuality.success ? 0 : 1;
  }
}

enum Level { solve, analyze, test }

/// A mapping of a package to application test results.
///
/// The result of sending a canary into the mine. Stores the [package] which was
/// tested with its new [version] as well as the [shaftAirQualities] holding the
/// information on each individual [Application] which was tested against.
class MineAirQuality {
  final String package;
  final String version;
  final Map<Application, ShaftAirQuality> shaftAirQualities;

  MineAirQuality(this.package, this.version, this.shaftAirQualities);

  bool get success => shaftAirQualities.values.every((shaft) => shaft.success);

  @override
  String toString() => '''
MineAirQuality(package: $package, version: $version, shaftAirQualities: $shaftAirQualities)''';
}

/// Test results for a specific application.
///
/// This stores the result of testing the canary against an individual
/// [Application].
class ShaftAirQuality {
  final Map<Level, AirQuality> before;
  final Map<Level, AirQuality> after;

  ShaftAirQuality({required this.before, required this.after});

  bool get success => failure == null;

  Level? get failure => Level.values.firstWhereOrNull(
        (level) =>
            before[level]?.breathable == true &&
            after[level]?.breathable == false,
      );

  String toRow(Application application) => '''
| ${application.name} | ${Level.values.map((l) => '${before[l]?.breathable.toEmoji ?? '-'}/${after[l]?.breathable.toEmoji ?? '-'}').join(' | ')} |''';

  @override
  String toString() => 'ShaftAirQuality(before: $before, after: $after)';
}

/// A success bool paired with the stdout and stderr for easier debugging.
class AirQuality {
  /// Whether the check was a success.
  final bool breathable;
  final String stdout;
  final String stderr;

  AirQuality({
    required this.breathable,
    required this.stdout,
    required this.stderr,
  });

  @override
  String toString() =>
      'AirQuality(success: $breathable, stdout: $stdout, stderr: $stderr)';
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
  String toString() => 'Application(url: $url, name: $name, level: $level)';
}

/// Contains the logic to determine the [MineAirQuality] and its individual
/// [ShaftAirQuality]s, by testing the [canaryPackage] at [version] against the
/// [Application]s listed in the [applicationFile].
class Canary {
  final String canaryPackage;
  final String version;

  /// The mine in the analogy, where we send our canary to test.
  final String applicationFile;

  Canary(this.canaryPackage, this.version, this.applicationFile);

  /// For each package under test, this:
  /// * Does a pub get (and optionally analyze and test)
  /// * Upgrades to the new dep version
  /// * Again runs pub get (and optionally analyze and test)
  Future<MineAirQuality> intoTheMine() async {
    final tempDir = await Directory.systemTemp.createTemp();
    final shaftAirQualities = <Application, ShaftAirQuality>{};
    for (var application in await Application.listFromFile(applicationFile)) {
      final path = await cloneRepo(application.url, tempDir);
      print('Cloned $application into $path');
      final depsListResult =
          (await runFlutter(['pub', 'deps', '--json'], path)).stdout;
      final depsJson =
          jsonDecode(depsListResult.substring(depsListResult.indexOf('{')))
              as Map<String, dynamic>;
      final depsPackages = depsJson['packages'] as List;
      print(depsPackages);
      if (depsPackages.any((p) => (p as Map)['name'] == canaryPackage)) {
        print('Test against the vanilla package');
        final resultBefore = await runChecks(path, application.level);

        print('Clean repo');
        await runFlutter(['clean'], path);

        print('Rev package:$canaryPackage to version $version $application');
        final revSuccess = await runFlutter(
          ['pub', 'add', version],
          path,
          true,
        );

        print('Test against the modified package');
        final resultAfter = await runChecks(path, application.level);

        // flutter pub add runs an implicit pub get
        resultAfter[Level.solve] = revSuccess;

        shaftAirQualities[application] = ShaftAirQuality(
          before: resultBefore,
          after: resultAfter,
        );
      } else {
        print('No package:$canaryPackage found in $application');
      }
    }
    await tempDir.delete(recursive: true);
    return MineAirQuality(canaryPackage, version, shaftAirQualities);
  }

  /// Uses `gh` to clone the Github repo at [url].
  Future<String> cloneRepo(String url, Directory tempDir) async {
    final name = url.split('/').last;

    var fullPath = p.join(tempDir.path, name);
    if (Directory(fullPath).existsSync()) {
      fullPath = p.join(tempDir.path, '${name}_${url.hashCode}');
    }
    final arguments = ['repo', 'clone', url, '--', fullPath];
    print('Running `gh ${arguments.join(' ')}`');
    final processResult = await Process.run('gh', arguments);
    final stdout = processResult.stdout as String;
    final stderr = processResult.stderr as String;
    print('stdout:');
    print(stdout);
    print('stderr:');
    print(stderr);
    return fullPath;
  }

  Future<Map<Level, AirQuality>> runChecks(String path, Level level) async {
    final result = <Level, AirQuality>{};
    result[Level.solve] = await runFlutter(['pub', 'get'], path);
    if (level.index >= Level.analyze.index &&
        result[Level.solve]?.breathable == true) {
      result[Level.analyze] = await runFlutter(['analyze'], path);
    }
    if (level.index >= Level.test.index &&
        result[Level.solve]?.breathable == true) {
      result[Level.test] = await runFlutter(['test'], path);
    }
    return result;
  }

  Future<AirQuality> runFlutter(
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
    return AirQuality(
      breathable: processResult.exitCode == 0,
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

String createComment(MineAirQuality mine) {
  final contents = '''
## Ecosystem testing

| Package | Solve | Analyze | Test |
| ------- | ----- | ------- | ---- |
${mine.shaftAirQualities.entries.map((shaft) => shaft.value.toRow(shaft.key)).join('\n')}

<details>
<summary>
<strong>Details per app</strong>
</summary>
${mine.shaftAirQualities.entries.map((entry) {
    final application = entry.key;
    final shaft = entry.value;
    return '''
<details>
<summary>
<strong>${application.name}</strong> ${shaft.success ? checkEmoji : crossEmoji}
</summary>

${shaft.success ? 'The app tests passed!' : '''
The failure occured at the "${shaft.failure!.name}" step, this is the error output of that step:
```
${shaft.after[shaft.failure!]?.stderr}
```
'''}

The complete list of logs is:

${shaft.before.keys.map((level) => '''
<details>
<summary>
<strong>Logs for step: ${level.name}</strong>
</summary>


### Before:

StdOut:
```
${shaft.before[level]?.stdout}
```

StdErr:
```
${shaft.before[level]?.stderr}
```

### After:

StdOut:
```
${shaft.after[level]?.stdout}
```

StdErr:
```
${shaft.after[level]?.stderr}
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
      return checkEmoji;
    } else {
      return crossEmoji;
    }
  }
}
