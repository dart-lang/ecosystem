// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Outputs information in CSV format for all the dependencies of a given
/// package.

import 'dart:io';

import 'package:args/args.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:corpus/packages.dart';
import 'package:corpus/pub.dart';

// TODO: show the 'discontinued' property

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
  bool excludeOld = argResults['exclude-old'] as bool;

  var log = Logger.standard();

  log.stdout('Analysis of deps for package:$packageName.');
  log.stdout('');

  var pub = Pub();
  var packageManager = PackageManager();

  var progress = log.progress('querying pub.dev');

  var targetPackage = await pub.getPackageInfo(packageName);

  final dateOneYearAgo = DateTime.now().subtract(Duration(days: 365));

  var limit = packageLimit == null ? null : int.parse(packageLimit);

  var packages = await pub.dependenciesOf(
    packageName,
    limit: limit == null ? null : limit * 2,
  );

  progress.finish(showTiming: true);

  var usageInfos = <PackageUsageInfo>[];

  int count = 0;

  for (var package in packages) {
    progress = log.progress('  $package');
    var usage = await getPackageUsageInfo(pub, package);
    progress.finish();

    if (excludeOld) {
      if (!usage.packageInfo.publishedDate.isAfter(dateOneYearAgo)) {
        continue;
      }
    }

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

Future<PackageUsageInfo> getPackageUsageInfo(Pub pub, String package) async {
  var packageInfo = await pub.getPackageInfo(package);
  var packageOptions = await pub.getPackageOptions(packageInfo.name);
  var packageScore = await pub.getPackageScore(packageInfo.name);

  return PackageUsageInfo(packageInfo, packageOptions, packageScore);
}

File generateCsvReport(
  PackageInfo targetPackage,
  List<PackageUsageInfo> usageInfos,
) {
  var buf = StringBuffer();

  buf.writeln('${targetPackage.name} ${targetPackage.version}');
  buf.writeln();
  buf.writeln('Package,Version,Last Published (days),Popularity,Quality Score,'
      'SDK Constraint,Package Constraint,Constraint Type,Likes,Repo');

  for (var usage in usageInfos) {
    var package = usage.packageInfo;
    var score = usage.packageScore;
    buf.writeln(
      '${package.name},'
      '${package.version},'
      '${daysOld(package.publishedDate)},'
      '${printDouble(score.popularityScore * 100)},'
      '${printDouble(score.grantedPoints * 100 / score.maxPoints)},'
      '${package.sdkConstraint ?? ''},'
      '${package.constraintFor(targetPackage.name) ?? ''},'
      '${package.constraintType(targetPackage.name) ?? ''},'
      '${score.likeCount},'
      '${package.repo ?? ''}',
    );
  }

  var file = File('reports/${targetPackage.name}.csv');
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
    'package-limit',
    help: 'Limit the number of packages usage data is collected from.',
    valueHelp: 'count',
  );
  parser.addFlag(
    'exclude-old',
    negatable: false,
    help: 'Exclude packages that haven\'t been published in the last year.',
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
