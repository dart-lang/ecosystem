// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;

import '../repo_tweak.dart';
import '../utils.dart';

final _instance = AutoPublishTweak._();

class AutoPublishTweak extends RepoTweak {
  factory AutoPublishTweak() => _instance;

  AutoPublishTweak._()
      : super(
          id: 'auto-publish',
          description:
              'configure github actions to enable package auto-publishing',
        );

  @override
  bool shouldRunByDefault(Directory checkout, String repoSlug) =>
      monoRepo(checkout, repoSlug);

  @override
  FutureOr<FixResult> fix(Directory checkout, String repoSlug) {
    final org = repoSlug.split('/').first;
    final fixes = <String>[];

    if (!monoRepo(checkout, repoSlug) && singlePackageRepo(checkout)) {
      const relPath = '.github/workflows/publish.yaml';
      final pubspec = yaml.loadYaml(
        File(p.join(checkout.path, 'pubspec.yaml')).readAsStringSync(),
      ) as yaml.YamlMap?;
      if (pubspec != null &&
          pubspec['publish_to'] != 'none' &&
          pubspec['workspace'] == null) {
        final useFlutter = _usesFlutter(pubspec);
        final content = singlePackagePublishContents
            .replaceAll('{org}', org)
            .replaceAll('{use_flutter}', '$useFlutter');
        _writeIfChanged(checkout, relPath, content, fixes);
      }
    } else {
      final legacyFile = File(
        p.join(checkout.path, '.github/workflows/publish.yaml'),
      );
      if (legacyFile.existsSync()) {
        legacyFile.deleteSync();
        fixes.add('.github/workflows/publish.yaml has been removed.');
      }

      final packages = _findPublishablePackages(checkout);
      for (final pkg in packages) {
        final relPath = '.github/workflows/publish_${pkg.name}.yaml';
        final content = monoRepoPackagePublishContents
            .replaceAll('{org}', org)
            .replaceAll('{package}', pkg.name)
            .replaceAll('{directory}', pkg.relativeDir)
            .replaceAll('{use_flutter}', '${pkg.useFlutter}');
        _writeIfChanged(checkout, relPath, content, fixes);
      }
    }

    return fixes.isEmpty ? FixResult.noFixesMade : FixResult(fixes: fixes);
  }
}

void _writeIfChanged(
  Directory checkout,
  String relPath,
  String content,
  List<String> fixes,
) {
  final file = File(p.join(checkout.path, relPath));
  if (!file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    fixes.add('$relPath has been created.');
  } else if (file.readAsStringSync() != content) {
    file.writeAsStringSync(content);
    fixes.add('$relPath has been updated.');
  }
}

List<_PackageInfo> _findPublishablePackages(Directory root) {
  final results = <_PackageInfo>[];
  void walk(Directory dir) {
    final pubspecFile = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final map =
          yaml.loadYaml(pubspecFile.readAsStringSync()) as yaml.YamlMap?;
      if (map != null &&
          map['publish_to'] != 'none' &&
          map['version'] != null &&
          map['workspace'] == null) {
        final name = map['name'] as String;
        final relDir = p.posix.joinAll(
          p.split(p.relative(dir.path, from: root.path)),
        );
        results.add(_PackageInfo(name, relDir, _usesFlutter(map)));
        return;
      }
      if (dir.path != root.path) {
        return;
      }
    }
    for (final child in dir.listSync().whereType<Directory>()) {
      final base = p.basename(child.path);
      if (!base.startsWith('.') &&
          base != 'example' &&
          base != 'test' &&
          base != 'test_data' &&
          base != 'test_fixtures') {
        walk(child);
      }
    }
  }

  walk(root);
  results.sort((a, b) => a.name.compareTo(b.name));
  return results;
}

bool _usesFlutter(yaml.YamlMap? pubspec) {
  if (pubspec == null) return false;
  final deps = pubspec['dependencies'] as yaml.YamlMap?;
  final devDeps = pubspec['dev_dependencies'] as yaml.YamlMap?;
  final env = pubspec['environment'] as yaml.YamlMap?;
  return (deps != null && deps.containsKey('flutter')) ||
      (devDeps != null && devDeps.containsKey('flutter_test')) ||
      (env != null && env.containsKey('flutter'));
}

class _PackageInfo {
  final String name;
  final String relativeDir;
  final bool useFlutter;

  _PackageInfo(this.name, this.relativeDir, this.useFlutter);
}

const singlePackagePublishContents = r'''
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  publish:
    if: ${{ github.repository_owner == '{org}' }}
    permissions:
      id-token: write # Required for authentication using OIDC
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@a5bff6576dfc51b47eb77d4b7084bba6a4daf8d2 # main
    with:
      use-flutter: {use_flutter}
''';

const monoRepoPackagePublishContents = r'''
# A CI configuration to publish package:{package} to pub.dev.

name: Publish package:{package}

on:
  push:
    tags:
      - '{package}-v[0-9]+.[0-9]+.[0-9]+*'

jobs:
  publish:
    if: ${{ github.repository_owner == '{org}' }}
    permissions:
      id-token: write # Required for authentication using OIDC
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@a5bff6576dfc51b47eb77d4b7084bba6a4daf8d2 # main
    with:
      working-directory: {directory}
      use-flutter: {use_flutter}
''';
