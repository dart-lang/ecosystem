// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math' as math;

import 'package:cli_util/cli_logging.dart';

String percent(int val, int count) {
  return '${(val * 100 / count).round()}%';
}

String pluralize(int count, String word, {String? plural}) {
  return count == 1 ? word : (plural ?? '${word}s');
}

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool verbose = false,
  Logger? logger,
}) async {
  if (verbose) {
    print('$executable ${arguments.join(' ')}');
  }

  var result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    var out = result.stdout as String;
    if (out.isNotEmpty) {
      logger == null ? print(out.trimRight()) : logger.stdout(out.trimRight());
    }
    out = result.stderr as String;
    if (out.isNotEmpty) {
      logger == null ? print(out.trimRight()) : logger.stderr(out.trimRight());
    }
  }
  return result;
}

/// A utility class to generate a markdown table into a string.
///
/// To use this class:
///
/// ```
/// var table = MarkdownTable();
/// for (var foo in foos) {
///   table.startRow()
///     ..cell(foo.bar)
///     ..cell(foo.baz.toStringAsFixed(1), right: true)
///     ..cell(foo.qux);
/// }
/// print(table.finish());
/// ```
class MarkdownTable {
  static const int defaultMaxWidth = 90;
  static const int _minWidth = 3;

  final List<List<_MarkdownCell>> _data = [];

  MarkdownRow startRow() {
    _data.add([]);
    return MarkdownRow(this);
  }

  String finish() {
    if (_data.isEmpty) return '';
    var header = _data.first;

    var widths = <int>[];

    for (int col = 0; col < header.length; col++) {
      var width = _data.map((row) {
        var item = row.length >= col ? row[col] : null;
        return item?.value.length ?? 0;
      }).reduce(math.max);
      widths.add(math.max(width, _minWidth));
    }

    var buffer = StringBuffer();

    for (var row in _data) {
      buffer.write('| ');
      for (int col = 0; col < row.length; col++) {
        if (col != 0) buffer.write(' | ');
        var cell = row[col];
        var width = math.min(widths[col], defaultMaxWidth);
        var value = cell.value;
        buffer.write(cell.right ? value.padLeft(width) : value.padRight(width));
      }
      buffer.writeln(' |');

      if (row == _data.first) {
        // Write the alignment row.
        buffer.write('| ');
        for (int col = 0; col < row.length; col++) {
          if (col != 0) buffer.write(' | ');
          var cell = row[col];
          var width = math.min(widths[col], defaultMaxWidth);
          var value = cell.right ? '--:' : '---';
          buffer.write(value.padLeft(width, '-'));
        }
        buffer.writeln(' |');
      }
    }

    return buffer.toString();
  }
}

/// Used to build a row in a markdown table.
class MarkdownRow {
  final MarkdownTable _table;

  MarkdownRow(this._table);

  void cell(String value, {bool right = false}) {
    _table._data.last.add(_MarkdownCell(value, right));
  }
}

class _MarkdownCell {
  final String value;
  final bool right;

  _MarkdownCell(this.value, this.right);
}
