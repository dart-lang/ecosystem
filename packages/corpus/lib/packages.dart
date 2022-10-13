// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:cli_util/cli_logging.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

import 'cache.dart';
import 'pub.dart';
import 'utils.dart';

class PackageManager {
  final Cache cache = Cache();

  late final Client _client;

  PackageManager() {
    _client = RetryClient(
      Client(),
      when: (response) => const [502, 503].contains(response.statusCode),
    );
  }

  // "archive_url":"https://pub.dartlang.org/packages/usage/versions/4.0.2.tar.gz",

  Future<bool> retrievePackageArchive(
    PackageInfo package, {
    Logger? logger,
  }) async {
    var archiveFile = getArchiveFileForPackage(package);

    if (archiveFile.existsSync()) {
      return true;
    }

    var progress =
        logger?.progress('downloading ${path.basename(archiveFile.path)}');
    try {
      Uint8List data = await _getPackageTarGzArchive(package);
      archiveFile.writeAsBytesSync(data);
      return true;
    } finally {
      progress?.finish(showTiming: true);
    }

    // This is live as _getPackageTarGzArchive can throw.
    // ignore: dead_code
    return false;
  }

  File getArchiveFileForPackage(PackageInfo package) {
    var name = '${package.name}-${package.version}.tar.gz';
    return File(path.join(cache.archivesDir.path, name));
  }

  Directory getDirectoryForPackage(PackageInfo package) {
    var name = '${package.name}-${package.version}';
    return Directory(path.join(cache.packagesDir.path, name));
  }

  Future<LocalPackage> rehydratePackage(PackageInfo package) async {
    var archiveFile = getArchiveFileForPackage(package);
    var localPackage = LocalPackage(package, getDirectoryForPackage(package));

    if (localPackage.directory.existsSync()) {
      return localPackage;
    }

    localPackage.directory.createSync(recursive: true);

    var result = await runProcess(
      'tar',
      [
        '-xf',
        '../../archives/${path.basename(archiveFile.path)}',
      ],
      workingDirectory: localPackage.directory.path,
    );
    if (result.exitCode != 0) {
      print(result.stdout);
      print(result.stderr);
    }

    return localPackage;
  }

  Future<Uint8List> _getPackageTarGzArchive(PackageInfo packageInfo) async {
    var response = await _client.get(Uri.parse(packageInfo.archiveUrl));
    if (response.statusCode == 404) {
      return Future.error(response.reasonPhrase!);
    }
    return response.bodyBytes;
  }

  void close() {
    _client.close();
  }
}

class LocalPackage {
  final PackageInfo packageInfo;
  final Directory directory;

  LocalPackage(this.packageInfo, this.directory);

  Future<bool> pubGet({
    bool checkUpToDate = false,
    Logger? logger,
  }) async {
    if (checkUpToDate) {
      var pubspec = File(path.join(directory.path, 'pubspec.yaml'));
      var lock = File(path.join(directory.path, 'pubspec.lock'));

      if (pubspec.existsSync() && lock.existsSync()) {
        if (!lock.lastModifiedSync().isBefore(pubspec.lastModifiedSync())) {
          return true;
        }
      }
    }

    var executable = Platform.resolvedExecutable;

    // Use 'flutter pub get' for flutter packages; it seems to do a better job
    // than 'dart pub get' for some reason.
    if (flutterPackage) {
      var flutterExecutable = path.join(path.dirname(executable), 'flutter');
      if (File(flutterExecutable).existsSync()) {
        executable = flutterExecutable;
      }
    }

    final progress = logger?.progress('${path.basename(executable)} pub get');
    var result = await runProcess(
      executable,
      [
        'pub',
        'get',
      ],
      workingDirectory: directory.path,
      logger: logger,
    );
    progress?.finish(showTiming: true);

    return result.exitCode == 0;
  }

  bool get flutterPackage {
    // Look for:

    // environment:
    //   flutter: ">=2.5.0"

    var pubspecFile = File(path.join(directory.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return false;
    }

    var pubspec = yaml.loadYaml(pubspecFile.readAsStringSync()) as Map;
    if (pubspec.containsKey('environment')) {
      var env = pubspec['environment'] as Map;
      return env.containsKey('flutter');
    }

    return false;
  }
}
