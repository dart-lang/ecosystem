// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:corpus/api.dart';
import 'package:corpus/cache.dart';
import 'package:corpus/packages.dart';
import 'package:corpus/pub.dart';
import 'package:corpus/report.dart';
import 'package:corpus/surveyor.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

void main(List<String> args) async {
  var argParser = createArgParser();

  late ArgResults argResults;
  try {
    argResults = argParser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print('');
    printUsage(argParser);
    exit(64);
  }

  if (argResults.rest.length != 1 || argResults['help']) {
    printUsage(argParser);
    exit(1);
  }

  final packageName = argResults.rest.first;
  final packageLimit =
      int.tryParse(argResults['package-limit'] ?? '') ?? 0x7fffffff;
  bool showSrcReferences = argResults['show-src-references'] as bool;

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
        await analyzePackage(targetPackage, package, localPackage.directory);
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

ArgParser createArgParser() {
  var parser = ArgParser();
  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print this usage information.',
  );
  parser.addOption(
    'package-limit',
    aliases: ['limit'],
    help: 'Limit the number of packages usage data is collected from.',
    valueHelp: 'count',
  );
  parser.addFlag(
    'show-src-references',
    negatable: false,
    help: 'Report specific references to src/ libraries.',
  );
  return parser;
}

void printUsage(ArgParser argParser) {
  print('usage: dart bin/api_usage.dart [options] <package-name>');
  print('');
  print('options:');
  print(argParser.usage);
}

Future<ApiUsage> analyzePackage(
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

  var driver = SurveyorDriver.fromDirs(
    directories: [usingPackageDir],
    visitor: apiUsageCollector,
    excludedPaths: ['example'],
  );

  await driver.analyze();

  var usage = apiUsageCollector.usage;
  file.parent.createSync();
  usage.toFile(file);
  return usage;
}
