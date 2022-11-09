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
  required int packageLimit,
  bool showSrcReferences = false,
}) async {
  var log = Logger.standard();

  var dartLibStrategy = packageName.startsWith('dart:');
  if (dartLibStrategy) {
    packageName = packageName.substring('dart:'.length);

    log.stdout('API usage analysis for dart:$packageName.');
    log.stdout('');
  } else {
    log.stdout('API usage analysis for package:$packageName.');
    log.stdout('');
  }

  var pub = Pub();
  var packageManager = PackageManager();

  var progress = log.progress('querying pub.dev');

  var sdkVersion = Platform.version;
  if (sdkVersion.contains('-')) {
    sdkVersion = sdkVersion.substring(0, sdkVersion.indexOf('-'));
  }

  var reportTarget = dartLibStrategy
      ? ReportTarget.fromDartLibrary(packageName, sdkVersion)
      : ReportTarget.fromPackage(await pub.getPackageInfo(packageName));

  var packageStream = dartLibStrategy
      ? pub.allPubPackages()
      : pub.popularDependenciesOf(packageName);

  progress.finish(showTiming: true);

  List<ApiUsage> usageInfo = [];

  var count = 0;

  await for (var package in packageStream) {
    log.stdout('');
    log.stdout('${package.name} v${package.version}');

    if (reportTarget.isPackage) {
      var targetPackage = reportTarget.targetPackage!;
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
    } else {
      var sdkConstraint = package.sdkContraint;
      if (sdkConstraint != null) {
        if (!sdkConstraint.allows(Version.parse(sdkVersion))) {
          log.stdout(
              "skipping - sdk constraint ($sdkConstraint) doesn't support the "
              'current sdk ($sdkVersion)');
          continue;
        }
      }
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

    progress = log.progress('analyzing package');
    var usage = await _analyzePackage(
      reportTarget,
      package,
      localPackage.directory,
    );
    var message = usage.describeUsage();
    if (reportTarget.isDartLibrary && !usage.hadAnyReferences) {
      message = 'skipping - no dart:${reportTarget.name} references';
    }
    progress.finish(message: message);

    // If collecting usage data for a dart: library, we check if the package
    // we've just analyzed references the dart: lib. We do this after the fact
    // as we don't know ahead of time wrt dart: usage.
    if (reportTarget.isDartLibrary && !usage.hadAnyReferences) {
      continue;
    }

    count++;

    usageInfo.add(usage);

    if (count >= packageLimit) {
      break;
    }
  }

  var report = Report(reportTarget);
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
  ReportTarget reportTarget,
  PackageInfo analyzingPackage,
  Directory usingPackageDir,
) async {
  var cache = Cache();
  var file = File(path.join(
    cache.usageDir.path,
    '${reportTarget.type}-${reportTarget.name}-${reportTarget.version}',
    '${analyzingPackage.name}-${analyzingPackage.version}.json',
  ));

  if (file.existsSync()) {
    ApiUsage usage = ApiUsage.fromFile(analyzingPackage, file);
    return usage;
  }

  var apiUsageCollector = ApiUseCollector(
    reportTarget,
    analyzingPackage,
    usingPackageDir,
  );

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
