// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Outputs information in CSV format for all the dependents of a given package.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:corpus/packages.dart';
import 'package:corpus/pub.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

const packageLimitFlag = 'package-limit';
const includeOldFlag = 'include-old';
const includeDevDepsFlag = 'include-dev-deps';
const requireSdk212 = true;

// TODO: Turn this and 'usage.dart' into a combined CommandRunner tool.
// TODO: Move the bulk of the implementation into lib/ (to facilitate testing).

void main(List<String> args) async {
  var argParser = createArgParser();

  ArgResults argResults;
  try {
    argResults = argParser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print('');
    printUsage(argParser);
    exit(64);
  }

  if (argResults.rest.length != 1 || argResults['help'] as bool) {
    printUsage(argParser);
    exit(1);
  }

  final packageName = argResults.rest.first;
  var packageLimit = argResults[packageLimitFlag] as String?;
  var includeOld = argResults[includeOldFlag] as bool;
  var includeDevDeps = argResults[includeDevDepsFlag] as bool;

  var log = Logger.standard();

  log.stdout('Analysis of deps for package:$packageName.');
  log.stdout('');

  var pub = Pub();
  var packageManager = PackageManager();

  var progress = log.progress('querying pub.dev');

  var targetPackage = await pub.getPackageInfo(packageName);

  final dateOneYearAgo = DateTime.now().subtract(const Duration(days: 365));

  var limit = packageLimit == null ? null : int.parse(packageLimit);

  var packageStream = pub.popularDependenciesOf(packageName);

  progress.finish(showTiming: true);

  var usageInfos = <PackageUsageInfo>[];

  var count = 0;

  await for (var package in packageStream) {
    var usage = await getPackageUsageInfo(pub, package);

    if (usage.packageOptions.isDiscontinued) {
      continue;
    }

    if (!includeOld &&
        !usage.packageInfo.publishedDate.isAfter(dateOneYearAgo)) {
      continue;
    }

    var constraintType = package.constraintType(targetPackage.name);
    if (!includeDevDeps && constraintType == 'dev') {
      continue;
    }

    var sdkConstraint = usage.packageInfo.sdkConstraint;
    if (requireSdk212 && sdkConstraint != null) {
      // We only want packages that support 2.12 and later. As a close proxy, we
      // skip packages that allow 2.11.0.
      var constraint = VersionConstraint.parse(sdkConstraint);
      if (constraint.allows(Version.parse('2.11.0'))) {
        continue;
      }
    }

    log.stdout('  $package');
    usageInfos.add(usage);
    count++;

    if (limit != null && count >= limit) {
      break;
    }
  }

  // write csv report
  var file = generateCsvReport(targetPackage, usageInfos);

  log.stdout('');
  log.stdout('wrote ${file.path}.');

  packageManager.close();

  pub.close();
}

class PackageUsageInfo {
  final PackageInfo packageInfo;
  final PackageOptions packageOptions;
  final PackageScore packageScore;

  PackageUsageInfo(this.packageInfo, this.packageOptions, this.packageScore);
}

Future<PackageUsageInfo> getPackageUsageInfo(
  Pub pub,
  PackageInfo package,
) async {
  var packageOptions = await pub.getPackageOptions(package.name);
  var packageScore = await pub.getPackageScore(package.name);

  return PackageUsageInfo(package, packageOptions, packageScore);
}

File generateCsvReport(
  PackageInfo targetPackage,
  List<PackageUsageInfo> usageInfos,
) {
  var buf = StringBuffer();

  var columns = [
    Column('Package', (usage) => usage.packageInfo.name),
    Column('Version', (usage) => usage.packageInfo.version),
    Column('Publish Days', (usage) => daysOld(usage.packageInfo.publishedDate)),
    Column('Score', (usage) {
      var score = usage.packageScore;
      return printDouble(score.grantedPoints * 100 / score.maxPoints);
    }),
    Column(
      'Popularity',
      (usage) => printDouble(usage.packageScore.popularityScore * 100),
    ),
    Column('Likes', (usage) => '${usage.packageScore.likeCount}'),
    Column(
      'Constraint',
      (usage) => '${usage.packageInfo.constraintFor(targetPackage.name)}',
    ),
    Column(
      'Dep Type',
      (usage) => '${usage.packageInfo.constraintType(targetPackage.name)}',
    ),
    Column('SDK', (usage) => '${usage.packageInfo.sdkConstraint}'),
    Column('Repo', (usage) => '${usage.packageInfo.repo}'),
  ];

  buf.writeln('${targetPackage.name} ${targetPackage.version}');
  buf.writeln();
  buf.writeln(columns.map((c) => c.title).join(','));

  // Sort the packages by the number of likes.
  usageInfos.sort((usage1, usage2) {
    return usage2.packageScore.likeCount - usage1.packageScore.likeCount;
  });

  for (var usage in usageInfos) {
    buf.writeln(columns.map((c) => c.fn(usage)).join(','));
  }

  var file = File(path.join('reports', '${targetPackage.name}.csv'));
  file.parent.createSync();
  file.writeAsStringSync(buf.toString());
  return file;
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
    packageLimitFlag,
    help: 'Limit the number of packages to return data for.',
    valueHelp: 'count',
  );
  parser.addFlag(
    includeOldFlag,
    negatable: false,
    help: "Include packages that haven't been published in the last year.",
  );
  parser.addFlag(
    includeDevDepsFlag,
    negatable: false,
    help: 'Include usages from dev dependencies.',
  );
  return parser;
}

void printUsage(ArgParser argParser) {
  print('usage: dart bin/deps.dart [options] <package-name>');
  print('');
  print('options:');
  print(argParser.usage);
}

final DateTime now = DateTime.now();

String daysOld(DateTime dateTime) {
  var duration = now.difference(dateTime);
  return '${duration.inDays}';
}

String printDouble(double value) => '${value.round()}';

class Column {
  final String title;
  final String Function(PackageUsageInfo) fn;

  Column(this.title, this.fn);
}
