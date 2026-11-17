// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firehose/src/groundskeeper.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

typedef _CommandRecord = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
});

Directory _createTempDir() {
  final dir = Directory.systemTemp.createTempSync('groundskeeper_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  group('parseFormatOutput', () {
    test('parses formatted files and changed count', () {
      const output = '''
Formatted lib/a.dart
Formatted lib/src/b.dart
Formatted 5 files (2 changed) in 0.12 seconds.
''';
      final summary = parseFormatOutput(output);
      expect(summary.formattedFiles, ['lib/a.dart', 'lib/src/b.dart']);
      expect(summary.changedCount, 2);
    });

    test('handles zero files and zero changes', () {
      const noFiles = 'Formatted no files in 0.01 seconds.\n';
      expect(parseFormatOutput(noFiles).formattedFiles, isEmpty);
      expect(parseFormatOutput(noFiles).changedCount, 0);

      const unchanged = 'Formatted 1 file (0 changed) in 0.02 seconds.\n';
      expect(parseFormatOutput(unchanged).formattedFiles, isEmpty);
      expect(parseFormatOutput(unchanged).changedCount, 0);
    });

    test('falls back to file list length when summary is absent', () {
      const output = 'Formatted lib/only.dart\n';
      final summary = parseFormatOutput(output);
      expect(summary.formattedFiles, ['lib/only.dart']);
      expect(summary.changedCount, 1);
    });
  });

  group('parseAnalyzeJson', () {
    test('parses diagnostics with leading banner and deduplicates', () {
      final jsonPayload = jsonEncode({
        'version': 1,
        'diagnostics': [
          {
            'code': 'DEPRECATED_WEB_CONFIGURATION',
            'problemMessage':
                "'dart:html' is deprecated and shouldn't be used as an "
                    'import/export configuration',
            'correctionMessage': "Try using 'dart.library.js_interop' instead.",
            'documentation':
                'https://dart.dev/diagnostics/deprecated_web_configuration',
          },
          {
            'code': 'deprecated_web_configuration',
            'problemMessage':
                "'dart:html' is deprecated and shouldn't be used as an "
                    'import/export configuration.',
            'correctionMessage': "Try using 'dart.library.js_interop' instead.",
          },
          {
            'code': 'deprecated_web_configuration',
            'problemMessage':
                "'dart:js_util' is deprecated and shouldn't be used as an "
                    'import/export configuration.',
            'correctionMessage': "Try using 'dart.library.js_interop' instead.",
          },
        ],
      });
      final output = 'Analyzing package...\nSome warning banner\n$jsonPayload';

      final parsed = parseAnalyzeJson(output);
      final meta = parsed['deprecated_web_configuration'];
      expect(meta, isNotNull);
      expect(
        meta!.documentation,
        'https://dart.dev/diagnostics/deprecated_web_configuration',
      );
      expect(meta.justifications, [
        "'dart:html' is deprecated and shouldn't be used as an import/export "
            "configuration. Try using 'dart.library.js_interop' instead.",
        "'dart:js_util' is deprecated and shouldn't be used as an "
            'import/export configuration. Try using '
            "'dart.library.js_interop' instead.",
      ]);
    });

    test('preserves ! and ? punctuation when joining messages', () {
      final payload = jsonEncode({
        'version': 1,
        'diagnostics': [
          {
            'code': 'first_lint',
            'problemMessage': 'Why did this happen?',
            'correctionMessage': 'Fix it.',
          },
          {
            'code': 'second_lint',
            'problemMessage': 'Avoid this!',
            'correctionMessage': 'Use that.',
          },
        ],
      });
      final parsed = parseAnalyzeJson(payload);
      expect(parsed['first_lint']!.justifications, [
        'Why did this happen? Fix it.',
      ]);
      expect(parsed['second_lint']!.justifications, [
        'Avoid this! Use that.',
      ]);
    });

    test('returns empty map on missing or malformed JSON', () {
      expect(parseAnalyzeJson('No issues found!\n'), isEmpty);
      expect(parseAnalyzeJson('{not valid json'), isEmpty);
    });
  });

  group('parseFixOutput', () {
    test('supports both unicode bullet and ASCII hyphen bullets', () {
      const output = '''
Computing fixes in my_pkg... (ran in 0.8s)
Applying fixes... (ran in 0.1s)

lib/a.dart
  unnecessary_import • 2 fixes
  prefer_const_constructors - 1 fix

lib/b.dart
  unnecessary_import - 1 fix

4 fixes made in 2 files.
''';
      final summary = parseFixOutput(output);
      expect(summary.totalFixes, 4);
      expect(summary.fixes.length, 2);

      expect(summary.fixes[0].code, 'prefer_const_constructors');
      expect(summary.fixes[0].occurrences, 1);
      expect(summary.fixes[0].fileCount, 1);

      expect(summary.fixes[1].code, 'unnecessary_import');
      expect(summary.fixes[1].occurrences, 3);
      expect(summary.fixes[1].fileCount, 2);
    });

    test('falls back to summary count when per-file bullets are absent', () {
      const output = '2 fixes made in 1 file.\n';
      final summary = parseFixOutput(output);
      expect(summary.totalFixes, 2);
      expect(summary.fixes, isEmpty);
    });
  });

  group('buildGroundskeeperMessages', () {
    test('builds package:fixnum deprecated_web_configuration messages', () {
      const docUrl =
          'https://dart.dev/diagnostics/deprecated_web_configuration';
      final messages = buildGroundskeeperMessages(
        target: 'package:fixnum',
        formatSummary: const FormatSummary(formattedFiles: [], changedCount: 0),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(
              code: 'deprecated_web_configuration',
              occurrences: 1,
              fileCount: 1,
            ),
          ],
          totalFixes: 1,
        ),
        diagnosticMetadata: const {
          'deprecated_web_configuration': DiagnosticMetadata(
            documentation: docUrl,
            justifications: [
              "'dart:html' is deprecated and shouldn't be used as an "
                  'import/export configuration. '
                  "Try using 'dart.library.js_interop' instead.",
            ],
          ),
        },
      );

      expect(messages.title, '1 tidy fix in package:fixnum');
      expect(messages.title.length, lessThan(72));
      expect(
        messages.body,
        'Applied automated fixes from `dart fix`:\n'
        '\n'
        '- [`deprecated_web_configuration`]($docUrl) (1 fix in 1 file): '
        "'dart:html' is deprecated and shouldn't be used as an "
        'import/export configuration. '
        "Try using 'dart.library.js_interop' instead.",
      );

      final commitLines = LineSplitter.split(messages.commitMessage).toList();
      expect(commitLines.first, '1 tidy fix in package:fixnum');
      expect(commitLines[1], isEmpty);
      expect(messages.commitMessage, isNot(contains(docUrl)));
      expect(
        messages.commitMessage,
        contains('- `deprecated_web_configuration` (1 fix in 1 file):'),
      );
      for (final line in commitLines) {
        expect(line.length, lessThanOrEqualTo(72));
      }
    });

    test('renders 0, 2-3, and 4+ justifications and sorts codes', () {
      final messages = buildGroundskeeperMessages(
        target: 'package:sample',
        formatSummary: const FormatSummary(formattedFiles: [], changedCount: 0),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(code: 'zeta_lint', occurrences: 4, fileCount: 2),
            FixVarietySummary(code: 'alpha_lint', occurrences: 1, fileCount: 1),
            FixVarietySummary(code: 'beta_lint', occurrences: 3, fileCount: 2),
          ],
          totalFixes: 8,
        ),
        diagnosticMetadata: const {
          'beta_lint': DiagnosticMetadata(
            documentation: null,
            justifications: ['Reason one.', 'Reason two.', 'Reason three.'],
          ),
          'zeta_lint': DiagnosticMetadata(
            documentation: 'https://dart.dev/diagnostics/zeta_lint',
            justifications: ['First.', 'Second.', 'Third.', 'Fourth.'],
          ),
        },
      );

      expect(messages.title, '8 tidy fixes in package:sample');
      expect(
        messages.body,
        'Applied automated fixes from `dart fix`:\n'
        '\n'
        '- `alpha_lint` (1 fix in 1 file)\n'
        '- `beta_lint` (3 fixes in 2 files):\n'
        '  - Reason one.\n'
        '  - Reason two.\n'
        '  - Reason three.\n'
        '- [`zeta_lint`](https://dart.dev/diagnostics/zeta_lint) '
        '(4 fixes in 2 files): e.g., First.',
      );
      expect(
        messages.commitMessage,
        contains('- `zeta_lint` (4 fixes in 2 files): e.g., First.'),
      );
    });

    test('formats 1 file, <=10 files, and >10 files cleanly', () {
      final single = buildGroundskeeperMessages(
        target: 'package:one',
        formatSummary: const FormatSummary(
          formattedFiles: ['lib/a.dart'],
          changedCount: 1,
        ),
        fixSummary: const FixSummary(fixes: [], totalFixes: 0),
      );
      expect(single.title, 'Format 1 file in package:one');
      expect(
        single.body,
        'Formatted 1 file with `dart format`:\n\n- `lib/a.dart`',
      );

      final tenFiles = [for (var i = 0; i < 10; i++) 'lib/f$i.dart'];
      final ten = buildGroundskeeperMessages(
        target: 'package:ten',
        formatSummary: FormatSummary(
          formattedFiles: tenFiles,
          changedCount: 10,
        ),
        fixSummary: const FixSummary(fixes: [], totalFixes: 0),
      );
      expect(ten.title, 'Format 10 files in package:ten');
      expect(ten.body, contains('- `lib/f9.dart`'));

      final elevenFiles = [for (var i = 0; i < 11; i++) 'lib/f$i.dart'];
      final eleven = buildGroundskeeperMessages(
        target: 'package:eleven',
        formatSummary: FormatSummary(
          formattedFiles: elevenFiles,
          changedCount: 11,
        ),
        fixSummary: const FixSummary(fixes: [], totalFixes: 0),
      );
      expect(eleven.title, 'Format 11 files in package:eleven');
      expect(eleven.body, 'Formatted 11 files with `dart format`.');
    });

    test('combines fixes and formatting and respects <72 char title limit', () {
      final combined = buildGroundskeeperMessages(
        target: 'package:http',
        formatSummary: const FormatSummary(
          formattedFiles: ['lib/a.dart', 'lib/b.dart'],
          changedCount: 2,
        ),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(
              code: 'unnecessary_import',
              occurrences: 2,
              fileCount: 1,
            ),
          ],
          totalFixes: 2,
        ),
      );
      expect(combined.title, '2 tidy fixes and formatting in package:http');
      expect(
        combined.body,
        'Applied automated fixes from `dart fix`:\n'
        '\n'
        '- `unnecessary_import` (2 fixes in 1 file)\n'
        '\n'
        'Also formatted 2 files with `dart format`:\n'
        '\n'
        '- `lib/a.dart`\n'
        '- `lib/b.dart`',
      );

      // Combined title exceeds 71 chars -> drops "and formatting".
      final mediumTarget = 'package:${'a' * 40}';
      final droppedFormat = buildGroundskeeperMessages(
        target: mediumTarget,
        formatSummary: const FormatSummary(
          formattedFiles: ['lib/a.dart'],
          changedCount: 1,
        ),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(
                code: 'unused_import', occurrences: 1, fileCount: 1),
          ],
          totalFixes: 1,
        ),
      );
      expect(droppedFormat.title, '1 tidy fix in $mediumTarget');
      expect(droppedFormat.title.length, lessThan(72));

      // Drops "package:" prefix when that fits <72 chars.
      final stripPackageTarget = 'package:${'b' * 55}';
      final strippedPackage = buildGroundskeeperMessages(
        target: stripPackageTarget,
        formatSummary: const FormatSummary(formattedFiles: [], changedCount: 0),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(
                code: 'unused_import', occurrences: 2, fileCount: 1),
          ],
          totalFixes: 2,
        ),
      );
      expect(strippedPackage.title, '2 tidy fixes in ${'b' * 55}');
      expect(strippedPackage.title.length, lessThan(72));

      // Drops "in <target>" completely when still >=72 chars.
      final hugeTarget = 'package:${'c' * 70}';
      final droppedTarget = buildGroundskeeperMessages(
        target: hugeTarget,
        formatSummary: const FormatSummary(formattedFiles: [], changedCount: 0),
        fixSummary: const FixSummary(
          fixes: [
            FixVarietySummary(
                code: 'unused_import', occurrences: 3, fileCount: 2),
          ],
          totalFixes: 3,
        ),
      );
      expect(droppedTarget.title, '3 tidy fixes');
      expect(droppedTarget.title.length, lessThan(72));

      // Fallback title truncation guard.
      final fallback = buildGroundskeeperMessages(
        target: hugeTarget,
        formatSummary: const FormatSummary(formattedFiles: [], changedCount: 0),
        fixSummary: const FixSummary(fixes: [], totalFixes: 0),
      );
      expect(fallback.title, 'Tidy');
      expect(
        fallback.body,
        'Applied automated changes from `dart format` and `dart fix --apply`.',
      );
    });
  });

  group('writeGithubOutputs', () {
    test('writes multiline outputs with collision-free delimiters', () {
      final dir = _createTempDir();
      final outputFile = File(path.join(dir.path, 'github_output'));
      outputFile.writeAsStringSync('changed=true');

      writeGithubOutputs(outputFile, {
        'title': '1 tidy fix in package:fixnum',
        'body': 'Line 1\nEOF_GROUNDSKEEPER\nLine 2',
      });

      final written = outputFile.readAsStringSync();
      expect(written, startsWith('changed=true\ntitle<<EOF_GROUNDSKEEPER\n'));
      expect(written, contains('body<<EOF_GROUNDSKEEPER_0\n'));
      expect(written,
          contains('Line 1\nEOF_GROUNDSKEEPER\nLine 2\nEOF_GROUNDSKEEPER_0\n'));
    });
  });

  group('runGroundskeeper', () {
    test('runs end-to-end for package:fixnum and writes outputs', () async {
      final dir = _createTempDir();
      File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixnum
version: 1.1.1
environment:
  sdk: ^3.5.0
''');
      final outputFile = File(path.join(dir.path, 'github_output'));
      final commands = <_CommandRecord>[];

      final code = await runGroundskeeper(
        targetDirectory: dir,
        githubOutputFile: outputFile,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async {
          commands.add((
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
          ));
          if (executable == 'dart' && arguments.first == 'format') {
            return ProcessResult(
              0,
              0,
              'Formatted 3 files (0 changed) in 0.05 seconds.\n',
              '',
            );
          }
          if (executable == 'dart' && arguments.first == 'analyze') {
            return ProcessResult(
              0,
              2,
              'Analyzing fixnum...\n'
                  '${jsonEncode({
                    'version': 1,
                    'diagnostics': [
                      {
                        'code': 'deprecated_web_configuration',
                        'problemMessage':
                            "'dart:html' is deprecated and shouldn't be used "
                                'as an import/export configuration.',
                        'correctionMessage':
                            "Try using 'dart.library.js_interop' instead.",
                        'documentation': 'https://dart.dev/diagnostics/'
                            'deprecated_web_configuration',
                      },
                    ],
                  })}\n',
              '',
            );
          }
          if (executable == 'dart' && arguments.first == 'fix') {
            return ProcessResult(
              0,
              0,
              '''
Computing fixes in fixnum... (ran in 1.2s)
Applying fixes... (ran in 0.1s)

lib/src/int64.dart
  deprecated_web_configuration • 1 fix

1 fix made in 1 file.
''',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(code, 0);
      expect(commands.map((c) => '${c.executable} ${c.arguments.join(' ')}'), [
        'dart pub get',
        'dart format .',
        'dart analyze --format=json',
        'dart fix --apply',
      ]);

      final written = outputFile.readAsStringSync();
      expect(written,
          contains('title<<EOF_GROUNDSKEEPER\n1 tidy fix in package:fixnum\n'));
      expect(
        written,
        contains(
          '- [`deprecated_web_configuration`]'
          '(https://dart.dev/diagnostics/deprecated_web_configuration) '
          '(1 fix in 1 file):',
        ),
      );
      expect(
        written,
        contains(
          'commit-message<<EOF_GROUNDSKEEPER\n'
          '1 tidy fix in package:fixnum\n\n'
          'Applied automated fixes from `dart fix`:\n\n'
          '- `deprecated_web_configuration` (1 fix in 1 file):',
        ),
      );
    });

    test('falls back to yaml package name when Pubspec.parse fails', () async {
      final dir = _createTempDir();
      File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: custom_minimal_pkg
version: not_a_semver
''');
      final outputFile = File(path.join(dir.path, 'github_output'));

      final code = await runGroundskeeper(
        targetDirectory: dir,
        runFix: false,
        useFlutter: true,
        githubOutputFile: outputFile,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async {
          if (executable == 'dart' && arguments.first == 'format') {
            return ProcessResult(
              0,
              0,
              'Formatted lib/main.dart\n'
                  'Formatted 1 file (1 changed) in 0.03 seconds.\n',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(code, 0);
      expect(
        outputFile.readAsStringSync(),
        contains('Format 1 file in package:custom_minimal_pkg'),
      );
    });

    test(
        'handles non-package directory formatting and errors when runFix is '
        'true', () async {
      final dir = _createTempDir();
      final failCode = await runGroundskeeper(
        targetDirectory: dir,
        runFix: true,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(0, 0, '', ''),
      );
      expect(failCode, 1);

      final outputFile = File(path.join(dir.path, 'github_output'));
      final okCode = await runGroundskeeper(
        targetDirectory: dir,
        runFix: false,
        githubOutputFile: outputFile,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(
          0,
          0,
          'Formatted tool/check.dart\n'
              'Formatted 2 files (1 changed) in 0.04 seconds.\n',
          '',
        ),
      );
      expect(okCode, 0);
      expect(
        outputFile.readAsStringSync(),
        contains('Format 1 file in ${path.basename(dir.path)}'),
      );
    });

    test('propagates non-zero exit codes from pub get, format, and fix',
        () async {
      final dir = _createTempDir();
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: pkg\n');

      final pubFail = await runGroundskeeper(
        targetDirectory: dir,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(0, 69, '', 'pub failed'),
      );
      expect(pubFail, 69);

      final formatFail = await runGroundskeeper(
        targetDirectory: dir,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async {
          if (executable == 'dart' && arguments.first == 'format') {
            return ProcessResult(0, 65, '', 'format failed');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(formatFail, 65);

      final fixFail = await runGroundskeeper(
        targetDirectory: dir,
        out: StringBuffer(),
        err: StringBuffer(),
        processRunner: (executable, arguments, {workingDirectory}) async {
          if (executable == 'dart' && arguments.first == 'fix') {
            return ProcessResult(0, 3, '', 'fix failed');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(fixFail, 3);
    });
  });
}
