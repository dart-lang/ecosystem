import 'dart:io';

void main(List<String> args) async {
  final excludeArg = args.firstWhere((a) => a.startsWith('--exclude='), orElse: () => '');
  final excludes = excludeArg.isEmpty
      ? <String>[]
      : excludeArg.substring('--exclude='.length).split(',').map((e) => e.trim()).toList();

  // Normalize excludes (remove leading ./ and trailing /)
  for (var i = 0; i < excludes.length; i++) {
    var e = excludes[i];
    if (e.startsWith('./')) e = e.substring(2);
    if (e.endsWith('/')) e = e.substring(0, e.length - 1);
    excludes[i] = e;
  }

  final runFormat = !args.contains('--no-format');
  final runFix = !args.contains('--no-fix');

  print('Excludes: $excludes');
  print('Run format: $runFormat');
  print('Run fix: $runFix');

  if (runFormat) {
    print('Running dart format...');
    final result = await Process.run('dart', ['format', '.']);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      exit(result.exitCode);
    }
  }

  if (runFix) {
    final packages = findPackages(Directory.current, excludes);
    print('Found packages: ${packages.map((e) => e.path).toList()}');

    for (final pkg in packages) {
      print('Tidying package in ${pkg.path}...');
      
      print('  Running dart pub get...');
      final pubGetResult = await Process.run('dart', ['pub', 'get'], workingDirectory: pkg.path);
      stdout.write(pubGetResult.stdout);
      stderr.write(pubGetResult.stderr);
      if (pubGetResult.exitCode != 0) {
        print('Error: dart pub get failed in ${pkg.path}');
        exit(pubGetResult.exitCode);
      }

      print('  Running dart fix --apply...');
      final fixResult = await Process.run('dart', ['fix', '--apply'], workingDirectory: pkg.path);
      stdout.write(fixResult.stdout);
      stderr.write(fixResult.stderr);
      if (fixResult.exitCode != 0) {
        print('Error: dart fix failed in ${pkg.path}');
        exit(fixResult.exitCode);
      }
    }
  }
}

List<Directory> findPackages(Directory root, List<String> excludes) {
  final packages = <Directory>[];
  final rootPath = root.absolute.path;

  void recruit(Directory dir) {
    final absolutePath = dir.absolute.path;
    var relativePath = absolutePath.substring(rootPath.length);
    if (relativePath.startsWith('/')) {
      relativePath = relativePath.substring(1);
    }
    
    if (excludes.contains(relativePath)) {
      print('Skipping excluded directory: $relativePath');
      return;
    }
    
    final name = absolutePath.split('/').last;
    if (name == '.dart_tool' || name == '.git' || name == 'node_modules') {
      return;
    }

    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      packages.add(dir);
    }

    try {
      for (final entity in dir.listSync()) {
        if (entity is Directory) {
          recruit(entity);
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }

  recruit(root);
  return packages;
}
