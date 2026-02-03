// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'lcov.dart';

class Coverage {
  final bool coverageWeb;
  final List<Glob> ignored;
  final Directory directory;
  final List<String> experiments;
  final String dartExecutable;

  Coverage(
    this.coverageWeb,
    this.ignored,
    this.directory,
    this.experiments,
    this.dartExecutable,
  );

  CoverageResult compareCoveragesFor(List<GitFile> files, Directory base) {
    final repository = Repository(directory);
    final packages = repository.locatePackages(ignore: ignored);
    print('Found packages $packages at $directory');

    final filesOfInterest = files
        .where((file) => path.extension(file.filename) == '.dart')
        .where((file) => file.status != FileStatus.removed)
        .where((file) => isInSomePackage(packages, file.filename))
        .where((file) => isNotATest(packages, file.filename))
        .where((file) => ignored.none((glob) => glob.matches(file.filename)))
        .toList();
    print('The files of interest are $filesOfInterest');

    final baseRepository = Repository(base);
    final basePackages = baseRepository.locatePackages(ignore: ignored);
    print('Found packages $basePackages at $base');

    final changedPackages = packages
        .where((package) =>
            filesOfInterest.any((file) => file.isInPackage(package)))
        .sortedBy((package) => package.name)
        .toList();

    print('The packages of interest are $changedPackages');

    final coverageResult = CoverageResult({});
    for (final package in changedPackages) {
      final newCoverages = getCoverage(package);

      final basePackage = basePackages
          .where((element) => element.name == package.name)
          .firstOrNull;
      final oldCoverages = getCoverage(basePackage);
      final filenames = filesOfInterest
          .where((file) => file.isInPackage(package))
          .map((file) => file.filename)
          .sortedBy((filename) => filename);
      for (final filename in filenames) {
        final oldCoverage = oldCoverages[filename];
        final newCoverage = newCoverages[filename];
        print('Compage coverage for $filename: $oldCoverage vs $newCoverage');
        coverageResult[filename] = Change(
          oldCoverage: oldCoverage,
          newCoverage: newCoverage,
        );
      }
    }
    return coverageResult;
  }

  bool isNotATest(List<Package> packages, String file) =>
      packages.every((package) => !path.isWithin(
          path.join(package.directory.path, 'test'),
          path.join(directory.path, file)));

  bool isInSomePackage(List<Package> packages, String file) =>
      packages.any((package) => path.isWithin(
            package.directory.path,
            path.join(directory.path, file),
          ));

  Map<String, double> getCoverage(Package? package) {
    if (package != null) {
      final hasTests =
          Directory(path.join(package.directory.path, 'test')).existsSync();
      if (hasTests) {
        print('''
Get coverage for ${package.name} by running coverage in ${package.directory.path}''');
        final coverageDir =
            Directory.systemTemp.createTempSync('coverage-${package.name}');
        Process.runSync(
          dartExecutable,
          [
            if (experiments.isNotEmpty)
              '--enable-experiment=${experiments.join(',')}',
            'pub',
            'get'
          ],
          workingDirectory: package.directory.path,
        );
        if (coverageWeb) {
          print('Run tests with coverage for web');
          final resultChrome = Process.runSync(
            dartExecutable,
            [
              if (experiments.isNotEmpty)
                '--enable-experiment=${experiments.join(',')}',
              'test',
              '-p',
              'chrome',
              '--coverage=${coverageDir.path}}'
            ],
            workingDirectory: package.directory.path,
          );
          if (resultChrome.exitCode != 0) {
            print(resultChrome.stderr);
          }
          print('Dart test browser: ${resultChrome.stdout}');
        }

        print('Run tests with coverage for vm');
        final resultVm = Process.runSync(
          dartExecutable,
          [
            if (experiments.isNotEmpty)
              '--enable-experiment=${experiments.join(',')}',
            'test',
            '--coverage=${coverageDir.path}'
          ],
          workingDirectory: package.directory.path,
        );
        if (resultVm.exitCode != 0) {
          print(resultVm.stderr);
        }
        print('Dart test VM: ${resultVm.stdout}');

        print('Compute coverage from runs');
        final lcovPath = path.join(coverageDir.path, 'lcov.info');
        final resultLcov = Process.runSync(
          dartExecutable,
          [
            'pub',
            'global',
            'run',
            'coverage:format_coverage',
            '--lcov',
            '--check-ignore',
            '--report-on lib/',
            '-i',
            coverageDir.path,
            '-o',
            lcovPath
          ],
          workingDirectory: package.directory.path,
        );
        if (resultLcov.exitCode != 0) {
          print(resultLcov.stderr);
        }
        print('Dart coverage: ${resultLcov.stdout}');
        final parsedLCOV = parseLCOV(
          lcovPath,
          relativeTo: package.repository.baseDirectory.path,
        );
        coverageDir.deleteSync(recursive: true);
        return parsedLCOV;
      }
    }
    return {};
  }
}

class CoverageResult {
  final Map<String, Change> coveragePerFile;

  CoverageResult(this.coveragePerFile);

  CoverageResult operator +(CoverageResult other) =>
      CoverageResult({...coveragePerFile, ...other.coveragePerFile});

  Change? operator [](String s) => coveragePerFile[s];
  void operator []=(String s, Change d) => coveragePerFile[s] = d;
}

class Change {
  final double? newCoverage;
  final double? oldCoverage;

  Change({this.newCoverage, this.oldCoverage});

  double? get relativeChange => oldCoverage != null
      ? ((newCoverage ?? 0) - oldCoverage!) / oldCoverage!.abs()
      : null;

  double? get absoluteCoverage => newCoverage;

  Severity get severity => _severityWithMessage().$1;

  bool get existsNow => newCoverage != null;

  bool get existedBefore => oldCoverage != null;

  String toMarkdown() => _severityWithMessage().$2;

  (Severity, String) _severityWithMessage() {
    if (existedBefore || existsNow) {
      String format(double? value) =>
          '${((value ?? 0) * 100).abs().toStringAsFixed(0)} %';
      final totalString = format(absoluteCoverage);
      if (existedBefore && relativeChange != 0) {
        final relativeString = '''
${relativeChange! >= 0 ? ':arrow_up:' : ':arrow_down:'} ${format(relativeChange)}''';
        if (relativeChange! > 0) {
          return (
            Severity.success,
            ':green_heart: $totalString $relativeString',
          );
        } else {
          return (
            Severity.warning,
            ':broken_heart: $totalString $relativeString'
          );
        }
      } else {
        if (absoluteCoverage! > 0) {
          return (Severity.success, ':green_heart: $totalString');
        }
      }
    }
    return (Severity.warning, ':broken_heart: Not covered');
  }

  @override
  bool operator ==(covariant Change other) {
    if (identical(this, other)) return true;

    return other.newCoverage == newCoverage && other.oldCoverage == oldCoverage;
  }

  @override
  int get hashCode => newCoverage.hashCode ^ oldCoverage.hashCode;

  @override
  String toString() =>
      'Change(newCoverage: $newCoverage, oldCoverage: $oldCoverage)';
}
