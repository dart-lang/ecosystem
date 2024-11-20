import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final candidatePackage = arguments.first;
  final version = arguments[1];
  final level = Level.values.firstWhere((l) => l.name == arguments[2]);
  final repositoriesFile = arguments[3];
  final chronicles =
      await Quest(candidatePackage, version, level, repositoriesFile).embark();
  final comment = createComment(chronicles);
  await writeComment(comment);
  print(chronicles);
}

enum Level { solve, analyze, test }

class Chronicles {
  final String package;
  final String version;
  final Level level;
  final List<Chapter> chapters;

  Chronicles(this.package, this.version, this.level, this.chapters);

  @override
  String toString() {
    return '''
Chronicles(package: $package, version: $version, level: $level, chapters: $chapters)''';
  }
}

class Chapter {
  final String packageName;
  final String packageUri;
  final Map<Level, bool> successBefore;
  final Map<Level, bool> successAfter;

  Chapter(
    this.packageName,
    this.packageUri,
    this.successBefore,
    this.successAfter,
  );

  @override
  String toString() {
    return '''
Chapter(packageName: $packageName, packageUri: $packageUri, successBefore: $successBefore, successAfter: $successAfter)''';
  }
}

class Quest {
  final String candidatePackage;
  final String version;
  final Level level;
  final String repositoriesFile;

  Quest(this.candidatePackage, this.version, this.level, this.repositoriesFile);

  Future<Chronicles> embark() async {
    final chapters = <Chapter>[];
    for (var repository in await getRepositories(repositoriesFile)) {
      final applicationName = await cloneRepo(repository);
      print('Cloned $repository');
      final processResult = await Process.run('flutter', [
        'pub',
        'deps',
        '--json',
      ], workingDirectory: applicationName);
      final depsListResult = processResult.stdout as String;
      print(depsListResult);
      final depsJson =
          jsonDecode(depsListResult.substring(depsListResult.indexOf('{')))
              as Map<String, dynamic>;
      final depsPackages = depsJson['packages'] as List;
      print(depsPackages);
      if (depsPackages.any((p) => (p as Map)['name'] == candidatePackage)) {
        print('Run checks for vanilla package');
        final successBefore = await runChecks(applicationName, level);

        print('Clean repo');
        await runFlutter(['clean'], applicationName);

        print('Rev package:$candidatePackage to version $version $repository');
        final revSuccess = await runFlutter([
          'pub',
          'add',
          "$candidatePackage:'$version'",
        ], applicationName);

        print('Run checks for modified package');
        final successAfter = await runChecks(applicationName, level);
        successAfter.update(
          Level.solve,
          (value) => value ? revSuccess : value,
          ifAbsent: () => revSuccess,
        );
        chapters.add(
          Chapter(
            p.basename(applicationName),
            repository,
            successBefore,
            successAfter,
          ),
        );
      } else {
        print('No package:$candidatePackage found in $repository');
      }
    }
    return Chronicles(candidatePackage, version, level, chapters);
  }

  Future<Iterable<String>> getRepositories(String path) async =>
      await File(path).readAsLines();

  Future<String> cloneRepo(String repository) async {
    var applicationName = repository.split('/').last;
    if (Directory(applicationName).existsSync()) {
      applicationName = '${applicationName}_${repository.hashCode}';
    }
    await Process.run('gh', [
      'repo',
      'clone',
      repository,
      '--',
      applicationName,
    ]);
    return applicationName;
  }

  Future<Map<Level, bool>> runChecks(String currentPackage, Level level) async {
    final success = <Level, bool>{};
    success[Level.solve] = await runFlutter(['pub', 'get'], currentPackage);
    if (level.index >= Level.analyze.index) {
      success[Level.analyze] = await runFlutter(['analyze'], currentPackage);
    }
    if (level.index >= Level.test.index) {
      success[Level.test] = await runFlutter(['test'], currentPackage);
    }
    return success;
  }

  Future<bool> runFlutter(List<String> arguments, String currentPackage) async {
    final processResult = await Process.run(
      'flutter',
      arguments,
      workingDirectory: currentPackage,
    );
    print('${processResult.stdout}');
    print('${processResult.stderr}');
    return processResult.exitCode == 0;
  }
}

Future<void> writeComment(String content) async {
  final commentFile = File('output/comment.md');
  await commentFile.create();
  await commentFile.writeAsString(content);
}

String createComment(Chronicles chronicles) {
  final contents = '''
## Ecosystem testing summary


| Package | Solve | Analyze | Test |
| ------- | ----- | ------- | ---- |
${chronicles.chapters.map((e) => '| ${e.packageName} | ${Level.values.map((l) => '${e.successBefore[l]?.toEmoji ?? '-'}/${e.successAfter[l]?.toEmoji ?? '-'}').join(' | ')} |').join('\n')}
  
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
