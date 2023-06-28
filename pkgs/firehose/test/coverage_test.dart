import 'dart:io';

import 'package:firehose/health.dart';
import 'package:test/test.dart';

void main() {
  test('LCOV parser', () {
    var parseLCOV =
        Health.parseLCOV('test/lcov.info', relativeTo: Directory.current.path);
    expect(
      parseLCOV.coveragePerFile.values.map((e) => e.value),
      orderedEquals([
        1.0,
        0.02857142857142857,
        0.8,
        0.8333333333333334,
        0.40625,
        0.0,
        1.0,
        0.0,
      ]),
    );
  });
}
