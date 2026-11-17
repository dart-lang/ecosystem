// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

/// Maximum allowed length for git commit headers and PR titles.
const int maxTitleLength = 71;

/// Line width used when wrapping commit message body text.
const int commitBodyWrapWidth = 72;

/// Callback matching [Process.run] for running external tools.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Generated commit and pull request text for a groundskeeper run.
class GroundskeeperMessages {
  final String title;
  final String body;
  final String commitMessage;

  const GroundskeeperMessages({
    required this.title,
    required this.body,
    required this.commitMessage,
  });
}

/// Diagnostic metadata extracted from `dart analyze --format=json`.
class DiagnosticMetadata {
  final String? documentation;
  final List<String> justifications;

  const DiagnosticMetadata({
    required this.documentation,
    required this.justifications,
  });
}

/// Aggregated fix counts for a single diagnostic code from `dart fix --apply`.
class FixVarietySummary {
  final String code;
  final int occurrences;
  final int fileCount;

  const FixVarietySummary({
    required this.code,
    required this.occurrences,
    required this.fileCount,
  });
}

/// Parsed results from running `dart format`.
class FormatSummary {
  final List<String> formattedFiles;
  final int changedCount;

  const FormatSummary({
    required this.formattedFiles,
    required this.changedCount,
  });
}

/// Parsed results from running `dart fix --apply`.
class FixSummary {
  final List<FixVarietySummary> fixes;
  final int totalFixes;

  const FixSummary({
    required this.fixes,
    required this.totalFixes,
  });
}

final _formatSummaryPattern = RegExp(
  r'^Formatted \d+ files? \((\d+) changed\) in [0-9.]+ seconds\.$',
);
final _formatNoFilesPattern =
    RegExp(r'^Formatted no files in [0-9.]+ seconds\.$');
final _fixLinePattern = RegExp(
  r'^  ([a-zA-Z0-9_]+)\s+[•-]\s+(\d+)\s+fix(?:es)?$',
);
final _fixSummaryPattern = RegExp(
  r'^(\d+)\s+fix(?:es)?\s+made\s+in\s+\d+\s+files?\.$',
);
final _terminalPunctuationPattern = RegExp(r'[.!?]$');
final _whitespacePattern = RegExp(r'\s+');

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

/// Runs groundskeeper formatting and automated fixes in [targetDirectory].
///
/// Returns the exit code (0 on success, non-zero if a required step fails).
Future<int> runGroundskeeper({
  Directory? targetDirectory,
  bool runFormat = true,
  bool runFix = true,
  bool useFlutter = false,
  File? githubOutputFile,
  ProcessRunner processRunner = _defaultProcessRunner,
  StringSink? out,
  StringSink? err,
}) async {
  final dir = targetDirectory ?? Directory.current;
  final pkgPath = dir.path;
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  stdoutSink.writeln('Target Directory: ${dir.absolute.path}');
  stdoutSink.writeln('Run format: $runFormat');
  stdoutSink.writeln('Run fix: $runFix');
  stdoutSink.writeln('Use Flutter: $useFlutter');

  final pubspecFile = File(path.join(pkgPath, 'pubspec.yaml'));
  final isPackage = pubspecFile.existsSync();

  if (runFix && !isPackage) {
    stdoutSink.writeln(
      'Error: Run fix is enabled, but no pubspec.yaml found in $pkgPath',
    );
    return 1;
  }

  final targetLabel = _resolveTargetLabel(dir, pubspecFile);

  if (isPackage) {
    final tool = useFlutter ? 'flutter' : 'dart';
    final sdkLabel = useFlutter ? 'Flutter' : 'Dart';

    stdoutSink.writeln('Tidying package in $pkgPath ($sdkLabel)...');
    stdoutSink.writeln('  Running $tool pub get...');
    final pubGetResult = await processRunner(
      tool,
      ['pub', 'get'],
      workingDirectory: pkgPath,
    );
    stdoutSink.write(pubGetResult.stdout);
    stderrSink.write(pubGetResult.stderr);
    if (pubGetResult.exitCode != 0) {
      stdoutSink.writeln('Error: $tool pub get failed in $pkgPath');
      return pubGetResult.exitCode;
    }
  }

  var formatSummary = const FormatSummary(formattedFiles: [], changedCount: 0);
  if (runFormat) {
    stdoutSink.writeln('Running dart format...');
    final formatResult = await processRunner(
      'dart',
      ['format', '.'],
      workingDirectory: pkgPath,
    );
    stdoutSink.write(formatResult.stdout);
    stderrSink.write(formatResult.stderr);
    if (formatResult.exitCode != 0) {
      return formatResult.exitCode;
    }
    formatSummary = parseFormatOutput('${formatResult.stdout}');
  }

  var fixSummary = const FixSummary(fixes: [], totalFixes: 0);
  var diagnosticMetadata = const <String, DiagnosticMetadata>{};
  if (runFix) {
    final analyzeResult = await processRunner(
      'dart',
      ['analyze', '--format=json'],
      workingDirectory: pkgPath,
    );
    diagnosticMetadata = parseAnalyzeJson('${analyzeResult.stdout}');

    stdoutSink.writeln('  Running dart fix --apply...');
    final fixResult = await processRunner(
      'dart',
      ['fix', '--apply'],
      workingDirectory: pkgPath,
    );
    stdoutSink.write(fixResult.stdout);
    stderrSink.write(fixResult.stderr);
    if (fixResult.exitCode != 0) {
      stdoutSink.writeln('Error: dart fix failed in $pkgPath');
      return fixResult.exitCode;
    }
    fixSummary = parseFixOutput('${fixResult.stdout}');
  }

  final messages = buildGroundskeeperMessages(
    target: targetLabel,
    formatSummary: formatSummary,
    fixSummary: fixSummary,
    diagnosticMetadata: diagnosticMetadata,
  );

  if (githubOutputFile != null) {
    writeGithubOutputs(githubOutputFile, {
      'title': messages.title,
      'body': messages.body,
      'commit-message': messages.commitMessage,
    });
  }

  return 0;
}

String _resolveTargetLabel(Directory targetDirectory, File pubspecFile) {
  if (pubspecFile.existsSync()) {
    final packageName = _parsePackageName(pubspecFile);
    if (packageName != null && packageName.isNotEmpty) {
      return 'package:$packageName';
    }
  }
  return path.basename(targetDirectory.absolute.path);
}

String? _parsePackageName(File pubspecFile) {
  final contents = pubspecFile.readAsStringSync();
  try {
    return Pubspec.parse(contents).name;
  } on Object {
    try {
      final parsed = loadYaml(contents);
      if (parsed is YamlMap) {
        final name = parsed['name'];
        if (name is String && name.trim().isNotEmpty) {
          return name.trim();
        }
      }
    } on Object {
      // Fall back to directory basename.
    }
  }
  return null;
}

/// Parses formatted file paths and changed count from `dart format` output.
FormatSummary parseFormatOutput(String rawStdout) {
  final formattedFiles = <String>[];
  int? changedCount;

  for (final rawLine in LineSplitter.split(rawStdout)) {
    final line = rawLine.trim();
    if (!line.startsWith('Formatted ')) continue;

    final summaryMatch = _formatSummaryPattern.firstMatch(line);
    if (summaryMatch != null) {
      changedCount = int.parse(summaryMatch.group(1)!);
      continue;
    }
    if (_formatNoFilesPattern.hasMatch(line)) continue;

    final filePath = line.substring('Formatted '.length).trim();
    if (filePath.isNotEmpty) {
      formattedFiles.add(filePath);
    }
  }

  return FormatSummary(
    formattedFiles: formattedFiles,
    changedCount: changedCount ?? formattedFiles.length,
  );
}

/// Parses diagnostic metadata keyed by lowercase diagnostic code from
/// `dart analyze --format=json` output.
Map<String, DiagnosticMetadata> parseAnalyzeJson(String rawStdout) {
  final lines = LineSplitter.split(rawStdout).toList();
  final startLineIndex = lines.indexWhere(
    (line) => line.trimLeft().startsWith('{'),
  );
  if (startLineIndex == -1) return const {};

  Object? decoded;
  try {
    decoded = jsonDecode(lines[startLineIndex]);
  } on FormatException {
    try {
      decoded = jsonDecode(lines.sublist(startLineIndex).join('\n'));
    } on FormatException {
      return const {};
    }
  }

  if (decoded is! Map<String, Object?>) return const {};
  final diagnostics = decoded['diagnostics'];
  if (diagnostics is! List<Object?>) return const {};

  final docsByCode = <String, String>{};
  final justificationsByCode = <String, LinkedHashSet<String>>{};

  for (final entry in diagnostics) {
    if (entry is! Map<String, Object?>) continue;
    final rawCode = entry['code'];
    if (rawCode is! String || rawCode.trim().isEmpty) continue;
    final code = rawCode.trim().toLowerCase();

    final rawDoc = entry['documentation'];
    if (rawDoc is String &&
        rawDoc.trim().isNotEmpty &&
        !docsByCode.containsKey(code)) {
      docsByCode[code] = rawDoc.trim();
    }

    final justification = _buildJustification(
      entry['problemMessage'],
      entry['correctionMessage'],
    );
    if (justification != null) {
      justificationsByCode
          .putIfAbsent(code, LinkedHashSet<String>.new)
          .add(justification);
    }
  }

  final codes = <String>{
    ...docsByCode.keys,
    ...justificationsByCode.keys,
  };

  return {
    for (final code in codes)
      code: DiagnosticMetadata(
        documentation: docsByCode[code],
        justifications: justificationsByCode[code]?.toList() ?? const [],
      ),
  };
}

String? _buildJustification(Object? rawProblem, Object? rawCorrection) {
  final problem = rawProblem is String
      ? rawProblem.trim().replaceAll(_whitespacePattern, ' ')
      : '';
  final correction = rawCorrection is String
      ? rawCorrection.trim().replaceAll(_whitespacePattern, ' ')
      : '';

  if (problem.isNotEmpty && correction.isNotEmpty) {
    final terminatedProblem =
        _terminalPunctuationPattern.hasMatch(problem) ? problem : '$problem.';
    return '$terminatedProblem $correction';
  }
  if (problem.isNotEmpty) return problem;
  if (correction.isNotEmpty) return correction;
  return null;
}

/// Parses applied fixes by diagnostic code from `dart fix --apply` output.
FixSummary parseFixOutput(String rawStdout) {
  final occurrencesByCode = <String, int>{};
  final filesByCode = <String, Set<String>>{};
  String? currentFile;
  var anonymousEntryIndex = 0;
  int? summaryTotalFixes;

  for (final rawLine in LineSplitter.split(rawStdout)) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      currentFile = null;
      continue;
    }

    final fixMatch = _fixLinePattern.firstMatch(rawLine);
    if (fixMatch != null) {
      final code = fixMatch.group(1)!.toLowerCase();
      final occurrences = int.parse(fixMatch.group(2)!);
      occurrencesByCode[code] = (occurrencesByCode[code] ?? 0) + occurrences;
      final fileKey = currentFile ?? '#${anonymousEntryIndex++}';
      filesByCode.putIfAbsent(code, () => <String>{}).add(fileKey);
      continue;
    }

    final summaryMatch = _fixSummaryPattern.firstMatch(trimmed);
    if (summaryMatch != null) {
      summaryTotalFixes = int.parse(summaryMatch.group(1)!);
      currentFile = null;
      continue;
    }

    if (!rawLine.startsWith('  ')) {
      currentFile = trimmed;
    }
  }

  final fixes = [
    for (final entry in occurrencesByCode.entries)
      FixVarietySummary(
        code: entry.key,
        occurrences: entry.value,
        fileCount: filesByCode[entry.key]?.length ?? 0,
      ),
  ]..sort((a, b) => a.code.compareTo(b.code));

  final sumOccurrences = occurrencesByCode.values.fold<int>(
    0,
    (sum, count) => sum + count,
  );
  final totalFixes =
      sumOccurrences > 0 ? sumOccurrences : (summaryTotalFixes ?? 0);

  return FixSummary(fixes: fixes, totalFixes: totalFixes);
}

/// Builds the PR title, PR body, and git commit message from tidy outputs.
GroundskeeperMessages buildGroundskeeperMessages({
  required String target,
  required FormatSummary formatSummary,
  required FixSummary fixSummary,
  Map<String, DiagnosticMetadata> diagnosticMetadata = const {},
}) {
  final title = _buildTitle(
    target: target,
    totalFixes: fixSummary.totalFixes,
    formattedFileCount: formatSummary.changedCount,
  );

  final prBody = _buildBody(
    formatSummary: formatSummary,
    fixSummary: fixSummary,
    diagnosticMetadata: diagnosticMetadata,
    includeDocLinks: true,
  );

  final plainBody = _buildBody(
    formatSummary: formatSummary,
    fixSummary: fixSummary,
    diagnosticMetadata: diagnosticMetadata,
    includeDocLinks: false,
  );
  final wrappedCommitBody = _wrapCommitBody(plainBody);

  return GroundskeeperMessages(
    title: title,
    body: prBody,
    commitMessage: '$title\n\n$wrappedCommitBody',
  );
}

String _buildTitle({
  required String target,
  required int totalFixes,
  required int formattedFileCount,
}) {
  final hasFixes = totalFixes > 0;
  final hasFormat = formattedFileCount > 0;

  if (!hasFixes && !hasFormat) {
    final full = 'Tidy $target';
    if (full.length <= maxTitleLength) return full;
    if (target.startsWith('package:')) {
      final withoutPrefix = 'Tidy ${target.substring('package:'.length)}';
      if (withoutPrefix.length <= maxTitleLength) return withoutPrefix;
    }
    return 'Tidy';
  }

  final fixPhrase = '$totalFixes tidy ${totalFixes == 1 ? 'fix' : 'fixes'}';
  final formatPhrase = 'Format $formattedFileCount '
      '${formattedFileCount == 1 ? 'file' : 'files'}';

  String prefix;
  if (hasFixes && hasFormat) {
    final combined = '$fixPhrase and formatting in $target';
    if (combined.length <= maxTitleLength) return combined;
    prefix = fixPhrase;
  } else if (hasFixes) {
    prefix = fixPhrase;
  } else {
    prefix = formatPhrase;
  }

  final withTarget = '$prefix in $target';
  if (withTarget.length <= maxTitleLength) return withTarget;

  if (target.startsWith('package:')) {
    final shortTarget = target.substring('package:'.length);
    final withoutPackage = '$prefix in $shortTarget';
    if (withoutPackage.length <= maxTitleLength) return withoutPackage;
  }

  return prefix.length <= maxTitleLength
      ? prefix
      : prefix.substring(0, maxTitleLength);
}

String _buildBody({
  required FormatSummary formatSummary,
  required FixSummary fixSummary,
  required Map<String, DiagnosticMetadata> diagnosticMetadata,
  required bool includeDocLinks,
}) {
  final totalFixes = fixSummary.totalFixes;
  final changedFormatCount = formatSummary.changedCount;
  final sections = <String>[];

  if (totalFixes > 0) {
    if (fixSummary.fixes.isEmpty) {
      final fixWord = totalFixes == 1 ? 'fix' : 'fixes';
      sections.add(
        'Applied $totalFixes automated $fixWord from `dart fix`.',
      );
    } else {
      final fixBuffer = StringBuffer()
        ..writeln('Applied automated fixes from `dart fix`:')
        ..writeln();
      final sortedFixes = [...fixSummary.fixes]
        ..sort((a, b) => a.code.compareTo(b.code));
      final lines = <String>[];
      for (final fix in sortedFixes) {
        final metadata = diagnosticMetadata[fix.code];
        lines.add(
          _formatFixBullet(
            fix: fix,
            metadata: metadata,
            includeDocLinks: includeDocLinks,
          ),
        );
      }
      fixBuffer.write(lines.join('\n'));
      sections.add(fixBuffer.toString());
    }
  }

  if (changedFormatCount > 0) {
    final verb = totalFixes > 0 ? 'Also formatted' : 'Formatted';
    final fileWord = changedFormatCount == 1 ? 'file' : 'files';
    final files = formatSummary.formattedFiles;
    if (files.isNotEmpty && files.length <= 10) {
      final formatBuffer = StringBuffer()
        ..writeln('$verb $changedFormatCount $fileWord with `dart format`:')
        ..writeln();
      final bullets = [for (final file in files) '- `$file`'];
      formatBuffer.write(bullets.join('\n'));
      sections.add(formatBuffer.toString());
    } else {
      sections.add('$verb $changedFormatCount $fileWord with `dart format`.');
    }
  }

  if (sections.isEmpty) {
    return 'Applied automated changes from `dart format` and '
        '`dart fix --apply`.';
  }

  return sections.join('\n\n');
}

String _formatFixBullet({
  required FixVarietySummary fix,
  required DiagnosticMetadata? metadata,
  required bool includeDocLinks,
}) {
  final docUrl = metadata?.documentation;
  final codeLabel = includeDocLinks && docUrl != null
      ? '[`${fix.code}`]($docUrl)'
      : '`${fix.code}`';

  final fixWord = fix.occurrences == 1 ? 'fix' : 'fixes';
  final fileWord = fix.fileCount == 1 ? 'file' : 'files';
  final countPhrase =
      '${fix.occurrences} $fixWord in ${fix.fileCount} $fileWord';

  final justifications = metadata?.justifications ?? const [];
  if (justifications.isEmpty) {
    return '- $codeLabel ($countPhrase)';
  }
  if (justifications.length == 1) {
    return '- $codeLabel ($countPhrase): ${justifications.first}';
  }
  if (justifications.length <= 3) {
    final buffer = StringBuffer('- $codeLabel ($countPhrase):');
    for (final justification in justifications) {
      buffer.write('\n  - $justification');
    }
    return buffer.toString();
  }
  return '- $codeLabel ($countPhrase): e.g., ${justifications.first}';
}

String _wrapCommitBody(String body) {
  final wrappedLines = <String>[];
  for (final line in LineSplitter.split(body)) {
    if (line.isEmpty) {
      wrappedLines.add('');
      continue;
    }

    final String firstPrefix;
    final String continuationPrefix;
    final String content;
    if (line.startsWith('  - ')) {
      firstPrefix = '  - ';
      continuationPrefix = '    ';
      content = line.substring(4);
    } else if (line.startsWith('- ')) {
      firstPrefix = '- ';
      continuationPrefix = '  ';
      content = line.substring(2);
    } else {
      firstPrefix = '';
      continuationPrefix = '';
      content = line;
    }

    final words = content
        .trim()
        .split(_whitespacePattern)
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      wrappedLines.add(firstPrefix.trimRight());
      continue;
    }

    var current = StringBuffer(firstPrefix)..write(words.first);
    for (final word in words.skip(1)) {
      if (current.length + 1 + word.length <= commitBodyWrapWidth) {
        current
          ..write(' ')
          ..write(word);
      } else {
        wrappedLines.add(current.toString());
        current = StringBuffer(continuationPrefix)..write(word);
      }
    }
    wrappedLines.add(current.toString());
  }
  return wrappedLines.join('\n');
}

/// Appends GitHub Actions multiline outputs to [outputFile].
void writeGithubOutputs(File outputFile, Map<String, String> outputs) {
  final buffer = StringBuffer();
  if (outputFile.existsSync() && outputFile.lengthSync() > 0) {
    final existing = outputFile.readAsBytesSync();
    if (existing.last != 10) {
      buffer.writeln();
    }
  }

  for (final entry in outputs.entries) {
    final delimiter = _collisionFreeDelimiter(entry.value);
    buffer
      ..writeln('${entry.key}<<$delimiter')
      ..writeln(entry.value)
      ..writeln(delimiter);
  }

  outputFile.writeAsStringSync(buffer.toString(), mode: FileMode.append);
}

String _collisionFreeDelimiter(String value) {
  var delimiter = 'EOF_GROUNDSKEEPER';
  var suffix = 0;
  while (value.contains(delimiter)) {
    delimiter = 'EOF_GROUNDSKEEPER_${suffix++}';
  }
  return delimiter;
}
