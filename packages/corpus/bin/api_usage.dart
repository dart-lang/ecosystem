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
import 'package:path/path.dart' as path;
import 'package:surveyor/src/driver.dart';

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
  String? packageLimit = argResults['package-limit'];
  bool showSrcReferences = argResults['show-src-references'] as bool;
  bool includeOld = argResults['include-old'] as bool;

  var log = Logger.standard();

  log.stdout('API usage analysis for package:$packageName.');
  log.stdout('');

  var pub = Pub();
  var packageManager = PackageManager();

  var progress = log.progress('querying pub.dev');

  var targetPackage = await pub.getPackageInfo(packageName);

  final dateOneYearAgo = DateTime.now().subtract(Duration(days: 365));
  bool packageAgeFilter(PackageInfo packageInfo) {
    // TODO: print to stdout when filtered a package

    // Only use packages which have been updated in the last year.
    return packageInfo.publishedDate.isAfter(dateOneYearAgo);
  }

  var packageStream = pub.popularDependenciesOf(
    packageName,
    limit: packageLimit == null ? null : int.parse(packageLimit),
    filter: includeOld ? null : packageAgeFilter,
  );

  progress.finish(showTiming: true);

  List<ApiUsage> usageInfo = [];

  await for (var package in packageStream) {
    log.stdout('');
    log.stdout('${package.name} v${package.version}');

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
    var usage =
        await analyzePackage(targetPackage, package, localPackage.directory);
    progress.finish(message: usage.describeUsage());

    usageInfo.add(usage);
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
    help: 'Limit the number of packages usage data is collected from.',
    valueHelp: 'count',
  );
  parser.addFlag(
    'show-src-references',
    negatable: false,
    help: 'Report specific references to src/ libraries.',
  );
  parser.addFlag(
    'include-old',
    negatable: false,
    help: 'Include packages that haven\'t been published in the last year '
        '(these are normally excluded).',
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

  var driver = Driver.forArgs([usingPackageDir.path]);
  driver.forceSkipInstall = true;
  driver.silent = true;
  driver.showErrors = false;
  driver.excludedPaths = ['example'];
  driver.visitor = apiUsageCollector;

  await driver.analyze();
  var usage = apiUsageCollector.usage;
  file.parent.createSync();
  usage.toFile(file);
  return usage;
}
