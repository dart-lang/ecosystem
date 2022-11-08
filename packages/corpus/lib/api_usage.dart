// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import 'api.dart';
import 'cache.dart';
import 'packages.dart';
import 'pub.dart';
import 'report.dart';
import 'surveyor.dart';

Future analyzeUsage({
  required String packageName,
  int packageLimit = 0x7FFFFFFF,
  bool showSrcReferences = false,
}) async {
  var log = Logger.standard();

  log.stdout('API usage analysis for package:$packageName.');
  log.stdout('');

  var pub = Pub();
  var packageManager = PackageManager();

  var progress = log.progress('querying pub.dev');

  var targetPackage = await pub.getPackageInfo(packageName);

  var packageStream = pub.popularDependenciesOf(packageName);

  progress.finish(showTiming: true);

  List<ApiUsage> usageInfo = [];

  var count = 0;

  await for (var package in packageStream) {
    log.stdout('');
    log.stdout('${package.name} v${package.version}');

    // Skip a package when its constraints don't include the latest stable.
    var constraint = package.constraintFor(targetPackage.name);
    if (constraint == null) {
      log.stdout('skipping - no constraint on ${targetPackage.name}');
      continue;
    }
    if (!constraint.allows(Version.parse(targetPackage.version))) {
      log.stdout(
          "skipping - version dep ($constraint) doesn't support the current "
          'stable (${targetPackage.version})');
      continue;
    }

    bool downloadSuccess =
        await packageManager.retrievePackageArchive(package, logger: log);
    if (!downloadSuccess) {
      log.stdout('error downloading ${package.archiveUrl}');
      continue;
    }

    var localPackage = await packageManager.rehydratePackage(package);

    var pubSuccess =
        await localPackage.pubGet(checkUpToDate: true, logger: log);
    if (!pubSuccess) {
      continue;
    }

    count++;

    progress = log.progress('analyzing package');
    var usage =
        await _analyzePackage(targetPackage, package, localPackage.directory);
    progress.finish(message: usage.describeUsage());

    usageInfo.add(usage);

    if (count >= packageLimit) {
      break;
    }
  }

  var report = Report(targetPackage);
  var file = report.generateReport(
    usageInfo,
    showSrcReferences: showSrcReferences,
  );

  log.stdout('');
  log.stdout('wrote ${file.path}.');

  packageManager.close();

  pub.close();
}

Future<ApiUsage> _analyzePackage(
  PackageInfo targetPackage,
  PackageInfo usingPackage,
  Directory usingPackageDir,
) async {
  var cache = Cache();
  var file = File(path.join(
    cache.usageDir.path,
    '${targetPackage.name}-${targetPackage.version}',
    '${usingPackage.name}-${usingPackage.version}.json',
  ));

  if (file.existsSync()) {
    ApiUsage usage = ApiUsage.fromFile(usingPackage, file);
    return usage;
  }

  var apiUsageCollector =
      ApiUseCollector(targetPackage, usingPackage, usingPackageDir);

  var surveyor = Surveyor.fromDirs(
    directories: [usingPackageDir],
    visitor: apiUsageCollector,
    excludedPaths: ['example'],
  );

  await surveyor.analyze();

  var usage = apiUsageCollector.usage;
  file.parent.createSync();
  usage.toFile(file);
  return usage;
}
