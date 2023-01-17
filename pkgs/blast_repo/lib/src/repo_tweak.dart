// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

abstract class RepoTweak {
  const RepoTweak({
    required this.id,
    required this.description,
  });

  final String id;
  final String description;

  bool get stable => true;

  /// Checks to see if the [checkout] needs to be fixed.
  ///
  /// If no fix is needed, nothing happens and `false` is returned.
  ///
  /// If a fix is needed, the fix is run and `true` is returned.
  ///
  /// If the repo cannot be checked or if a required fix cannot be applied,
  /// an error is thrown.
  FutureOr<FixResult> fix(Directory checkout, {required String repoSlug});

  @override
  String toString() => id;
}

class CheckResult {
  static const noFixNeeded = CheckResult._();

  const CheckResult._() : neededFixes = const [];

  CheckResult({required this.neededFixes}) {
    neededFixes.forEach(_validateItem);
  }

  final List<Object> neededFixes;

  bool get fixNeeded => neededFixes.isNotEmpty;
}

class FixResult {
  static const noFixesMade = FixResult._();

  const FixResult._() : fixes = const [];

  FixResult({required this.fixes}) {
    fixes.forEach(_validateItem);
  }

  final List<Object> fixes;
}

void _validateItem(Object item) {
  if (item is String) {
    if (item.trim().isEmpty) {
      throw ArgumentError('Bad item! Cannot be trimmed empty!');
    }
    return;
  }

  if (item is Map) {
    if (item.length != 1) {
      throw ArgumentError('Item must be a single item map');
    }
    final entry = item.entries.single;
    if (entry.key is! String) {
      throw ArgumentError('Map key must be a String');
    }
    final value = entry.value;
    if (value is List) {
      value.cast<Object>().forEach(_validateItem);
      return;
    }
    throw ArgumentError(
      'Map value must be a List it was ${value.runtimeType}.',
    );
  }

  throw ArgumentError('We do not support ${item.runtimeType}');
}
