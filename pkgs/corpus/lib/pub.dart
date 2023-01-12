// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:pub_semver/pub_semver.dart';

typedef PackageFilter = bool Function(PackageInfo packageInfo);

/// Utilities to query pub.dev.
class Pub {
  late final Client _client;

  Pub() {
    _client = RetryClient(
      Client(),
      when: (response) => const [502, 503].contains(response.statusCode),
    );
  }

  /// Return all the packages that depend on [packageName], sorted by package
  /// popularity.
  Stream<PackageInfo> popularDependenciesOf(String packageName) {
    return _packagesForSearch(
      query: 'dependency:$packageName',
      sort: 'top',
    );
  }

  /// Return all the pub.dev hosted packages sorted by package popularity.
  ///
  /// Note that this will be tens of thousands of packages, so the caller should
  /// plan to limit the number of packages they iterate through.
  Stream<PackageInfo> allPubPackages() {
    return _packagesForSearch(
      query: '',
      sort: 'top',
    );
  }

  Future<List<String>> dependenciesOf(
    String packageName, {
    int? limit,
  }) async {
    return await _packageNamesForSearch(
      'dependency:$packageName',
      limit: limit,
      sort: 'top',
    ).toList();
  }

  Future<PackageInfo> getPackageInfo(String pkgName) async {
    final json = await _getJson(Uri.https('pub.dev', 'api/packages/$pkgName'));

    return PackageInfo.from(json /*, options: options*/);
  }

  Future<PackageOptions> getPackageOptions(String packageName) async {
    final json = await _getJson(
        Uri.https('pub.dev', 'api/packages/$packageName/options'));
    return PackageOptions.from(json);
  }

  Future<PackageScore> getPackageScore(String packageName) async {
    final json =
        await _getJson(Uri.https('pub.dev', 'api/packages/$packageName/score'));
    return PackageScore.from(json);
  }

  Stream<PackageInfo> _packagesForSearch({
    required String query,
    int page = 1,
    String? sort,
  }) async* {
    final uri = Uri.parse('https://pub.dev/api/search');

    for (;;) {
      final targetUri = uri.replace(queryParameters: {
        'q': query,
        'page': page.toString(),
        if (sort != null) 'sort': sort,
      });

      final map = await _getJson(targetUri);

      for (var packageName in (map['packages'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['package'] as String?)) {
        var packageInfo = await getPackageInfo(packageName!);

        yield packageInfo;
      }

      if (map.containsKey('next')) {
        page = page + 1;
      } else {
        break;
      }
    }
  }

  Stream<String> _packageNamesForSearch(
    String query, {
    int page = 1,
    int? limit,
    String? sort,
  }) async* {
    final uri = Uri.parse('https://pub.dev/api/search');

    var count = 0;

    for (;;) {
      final targetUri = uri.replace(queryParameters: {
        if (query.isNotEmpty) 'q': query,
        'page': page.toString(),
        if (sort != null) 'sort': sort,
      });

      final map = await _getJson(targetUri);

      for (var packageName in (map['packages'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['package'] as String?)) {
        count++;
        yield packageName!;
      }

      if (map.containsKey('next')) {
        page = page + 1;
      } else {
        break;
      }

      if (limit != null && count >= limit) {
        break;
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final result = await _client.get(uri);
    if (result.statusCode == 200) {
      return jsonDecode(result.body) as Map<String, dynamic>;
    } else {
      throw StateError('Error getting `$uri` - ${result.statusCode}');
    }
  }

  void close() {
    _client.close();
  }
}

class PackageInfo {
  // {
  // "name":"usage",
  // "latest":{
  //   "version":"4.0.2",
  //   "pubspec":{
  //     "name":"usage",
  //     "version":"4.0.2",
  //     "description":"A Google Analytics wrapper for command-line, web, and Flutter apps.",
  //     "repository":"https://github.com/dart-lang/wasm",
  //     "environment":{
  //       "sdk":">=2.12.0-0 <3.0.0"
  //     },
  //     "dependencies":{
  //       "path":"^1.8.0"
  //     },
  //     "dev_dependencies":{
  //       "pedantic":"^1.9.0",
  //       "test":"^1.16.0"
  //     }
  //   },
  //   "archive_url":"https://pub.dartlang.org/packages/usage/versions/4.0.2.tar.gz",
  //   "published":"2021-03-30T17:44:54.093423Z"
  // },

  final Map<String, dynamic> json;

  PackageInfo.from(this.json);

  String get name => json['name'] as String;
  String? get description => _pubspec['description'] as String?;

  String? get repository => _pubspec['repository'] as String?;
  String? get homepage => _pubspec['homepage'] as String?;

  String? get repo => repository ?? homepage;
  Map<String, dynamic>? get environment =>
      _pubspec['environment'] as Map<String, dynamic>?;
  String? get sdkConstraint => (environment ?? {})['sdk'] as String?;

  String get version => _latest['version'] as String;
  String get archiveUrl => _latest['archive_url'] as String;
  DateTime get publishedDate => DateTime.parse(_published);

  String get _published => _latest['published'] as String;

  late final Map<String, dynamic> _latest =
      json['latest'] as Map<String, dynamic>;
  late final Map<String, dynamic> _pubspec =
      _latest['pubspec'] as Map<String, dynamic>;

  @override
  String toString() => '$name: $version';

  VersionConstraint? constraintFor(String name) {
    if (_pubspec['dependencies'] is Map) {
      var deps = _pubspec['dependencies'] as Map;
      if (deps.containsKey(name)) {
        var constraint = (deps[name] as String?) ?? 'any';
        if (constraint.isEmpty) {
          constraint = 'any';
        }
        return VersionConstraint.parse(constraint);
      }
    }

    if (_pubspec['dev_dependencies'] is Map) {
      var deps = _pubspec['dev_dependencies'] as Map;
      if (deps.containsKey(name)) {
        var constraint = (deps[name] as String?) ?? 'any';
        if (constraint.isEmpty) {
          constraint = 'any';
        }
        return VersionConstraint.parse(constraint);
      }
    }

    return null;
  }

  VersionConstraint? get sdkContraint {
    var environment = _pubspec['environment'] as Map?;
    var sdk = environment?['sdk'] as String?;
    if (sdk == null) return null;
    return VersionConstraint.parse(sdk);
  }

  String? constraintType(String name) {
    if (_pubspec['dependencies'] is Map) {
      var deps = _pubspec['dependencies'] as Map;
      if (deps.containsKey(name)) {
        return 'regular';
      }
    }

    if (_pubspec['dev_dependencies'] is Map) {
      var deps = _pubspec['dev_dependencies'] as Map;
      if (deps.containsKey(name)) {
        return 'dev';
      }
    }

    return null;
  }
}

class PackageOptions {
  // {"isDiscontinued":false,"replacedBy":null,"isUnlisted":true}

  final Map<String, dynamic> json;

  PackageOptions.from(this.json);

  bool get isDiscontinued => json['isDiscontinued'] as bool;
  String? get replacedBy => json['replacedBy'] as String?;
  bool get isUnlisted => json['isUnlisted'] as bool;
}

class PackageScore {
  // {
  //   grantedPoints: 85, maxPoints: 140, likeCount: 0, popularityScore: 0.0,
  //   tags: [sdk:dart, sdk:flutter, platform:android, platform:ios, ...],
  //   lastUpdated: 2022-09-16T10:33:33.105325Z
  // }

  final Map<String, dynamic> json;

  PackageScore.from(this.json);

  int get grantedPoints => json['grantedPoints'] as int;
  int get maxPoints => json['maxPoints'] as int;
  int get likeCount => json['likeCount'] as int;
  double get popularityScore => json['popularityScore'] as double;
}
