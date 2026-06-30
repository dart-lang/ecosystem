import 'dart:io';
import 'package:args/args.dart';
import 'package:firehose/firehose.dart';
import 'package:glob/glob.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('directory', defaultsTo: '.')
    ..addOption('format', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption('fix', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption('exclude', defaultsTo: '');

  final argResults = parser.parse(args);

  final targetDirectoryPath = argResults['directory'] as String;
  final targetDirectory = Directory(targetDirectoryPath);

  final runFormat = argResults['format'] != 'false';
  final runFix = argResults['fix'] != 'false';
  final excludeStr = argResults['exclude'] as String;

  final excludes = excludeStr.isEmpty
      ? <String>[]
      : excludeStr.split(',').map((e) => e.trim()).toList();

  print('Target Directory: ${targetDirectory.absolute.path}');
  print('Excludes: $excludes');
  print('Run format: $runFormat');
  print('Run fix: $runFix');

  // Locate packages early to use for both format and fix
  final repo = Repository(targetDirectory);
  final packages = repo.locatePackages(
    ignore: excludes.map(Glob.new).toList(),
    includeUnpublished: true,
  );

  if (runFormat) {
    print('Running dart format...');
    // Respect excludes by only formatting located packages.
    // If no packages are found, default to the target directory.
    final pathsToFormat = packages.isEmpty
        ? [targetDirectory.path]
        : packages.map((p) => p.directory.path).toList();

    final result = await Process.run(
      'dart',
      ['format', ...pathsToFormat],
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      exit(result.exitCode);
    }
  }

  if (runFix) {
    print('Found packages: ${packages.map((e) => e.directory.path).toList()}');

    for (final pkg in packages) {
      final pkgPath = pkg.directory.path;

      // Detect if it is a Flutter package
      final isFlutter = pkg.pubspec.dependencies.containsKey('flutter') ||
          pkg.pubspec.devDependencies.containsKey('flutter');
      final tool = isFlutter ? 'flutter' : 'dart';

      print(
          'Tidying package in $pkgPath (${isFlutter ? 'Flutter' : 'Dart'})...');

      print('  Running $tool pub get...');
      final pubGetResult =
          await Process.run(tool, ['pub', 'get'], workingDirectory: pkgPath);
      stdout.write(pubGetResult.stdout);
      stderr.write(pubGetResult.stderr);
      if (pubGetResult.exitCode != 0) {
        print('Error: $tool pub get failed in $pkgPath');
        exit(pubGetResult.exitCode);
      }

      print('  Running dart fix --apply...');
      final fixResult = await Process.run('dart', ['fix', '--apply'],
          workingDirectory: pkgPath);
      stdout.write(fixResult.stdout);
      stderr.write(fixResult.stderr);
      if (fixResult.exitCode != 0) {
        print('Error: dart fix failed in $pkgPath');
        exit(fixResult.exitCode);
      }
    }
  }
}
