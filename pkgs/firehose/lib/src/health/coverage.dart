// ignore_for_file: public_member_api_docs, sort_constructors_first
// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;

import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'lcov.dart';

class Coverage {
  final bool coverageWeb;
  final Directory directory;

  Coverage(this.coverageWeb, this.directory);

  Future<CoverageResult> compareCoverages(
      GithubApi github, Directory base) async {
    var files = await github.listFilesForPR(directory);

    return compareCoveragesFor(files, base);
  }

  CoverageResult compareCoveragesFor(List<GitFile> files, Directory base) {
    var repository = Repository(directory);
    var packages = repository.locatePackages();
    print('Found packages $packages at $directory');

    var filesOfInterest = files
        .where((file) => path.extension(file.filename) == '.dart')
        .where((file) => file.status != FileStatus.removed)
        .where((file) => isInSomePackage(packages, file.filename))
        .where((file) => isNotATest(packages, file.filename))
        .toList();
    print('The files of interest are $filesOfInterest');

    var baseRepository = Repository(base);
    var basePackages = baseRepository.locatePackages();
    print('Found packages $basePackages at $base');

    var changedPackages = packages
        .where((package) =>
            filesOfInterest.any((file) => file.isInPackage(package)))
        .toList();

    print('The packages of interest are $changedPackages');

    var coverageResult = CoverageResult({});
    for (var package in changedPackages) {
      final newCoverages = getCoverage(package);

      final basePackage = basePackages
          .where((element) => element.name == package.name)
          .firstOrNull;
      final oldCoverages = getCoverage(basePackage);
      var filePaths = filesOfInterest
          .where((file) => file.isInPackage(package))
          .map((file) => file.filename);
      for (var filePath in filePaths) {
        var oldCoverage = oldCoverages[filePath];
        var newCoverage = newCoverages[filePath];
        print('Compage coverage for $filePath: $oldCoverage vs $newCoverage');
        coverageResult[filePath] = Change(
          oldCoverage: oldCoverage,
          newCoverage: newCoverage,
        );
      }
    }
    return coverageResult;
  }

  bool isNotATest(List<Package> packages, String file) {
    return packages.every((package) => !path.isWithin(
        path.join(package.directory.path, 'test'),
        path.join(directory.path, file)));
  }

  bool isInSomePackage(List<Package> packages, String file) =>
      packages.any((package) => path.isWithin(
            package.directory.path,
            path.join(directory.path, file),
          ));

  Map<String, double> getCoverage(Package? package) {
    if (package != null) {
      var hasTests =
          Directory(path.join(package.directory.path, 'test')).existsSync();
      if (hasTests) {
        print('''
Get coverage for ${package.name} by running coverage in ${package.directory.path}''');
        Process.runSync(
          'dart',
          ['pub', 'get'],
          workingDirectory: package.directory.path,
        );
        if (coverageWeb) {
          print('Get test coverage for web');
          var resultChrome = Process.runSync(
            'dart',
            ['test', '-p', 'chrome', '--coverage=coverage'],
            workingDirectory: package.directory.path,
          );
          print(resultChrome.stdout);
          print(resultChrome.stderr);
        }
        print('Get test coverage for vm');
        var resultVm = Process.runSync(
          'dart',
          ['test', '--coverage=coverage'],
          workingDirectory: package.directory.path,
        );
        print(resultVm.stdout);
        print(resultVm.stderr);
        var resultLcov = Process.runSync(
          'dart',
          [
            'pub',
            'global',
            'run',
            'coverage:format_coverage',
            '--lcov',
            '--check-ignore',
            '--report-on lib/',
            '-i',
            'coverage/',
            '-o',
            'coverage/lcov.info'
          ],
          workingDirectory: package.directory.path,
        );
        print(resultLcov.stdout);
        print(resultLcov.stderr);
        return parseLCOV(
          path.join(package.directory.path, 'coverage/lcov.info'),
          relativeTo: package.repository.baseDirectory.path,
        );
      }
    }
    return {};
  }
}

class CoverageResult {
  final Map<String, Change> coveragePerFile;

  CoverageResult(this.coveragePerFile);

  CoverageResult operator +(CoverageResult other) {
    return CoverageResult({...coveragePerFile, ...other.coveragePerFile});
  }

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
      var totalString = format(absoluteCoverage);
      if (existedBefore && relativeChange != 0) {
        var relativeString = '''
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
