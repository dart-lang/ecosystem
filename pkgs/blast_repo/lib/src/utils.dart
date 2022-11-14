import 'dart:io';

import 'package:git/git.dart';
import 'package:io/ansi.dart';

const packageName = 'blast_repo';

Future<void> cloneGitHubRepoToPath(String slug, String path) {
  printHeader('Cloning repo $slug');
  return runGit(
    ['clone', 'https://github.com/$slug', path],
    echoOutput: true,
  );
}

extension GitDirExtension on GitDir {
  Future<ProcessResult> exec(String description, List<String> args) async {
    printHeader(description);

    printDim(
      [
        'git',
        ...args,
      ].join(' '),
    );

    return await runCommand(args, echoOutput: true);
  }
}

Future<void> runProc(
  String description,
  String proc,
  List<String> args, {
  required String workingDirectory,
}) async {
  printHeader(description);

  printDim(
    [
      proc,
      ...args,
    ].join(' '),
  );
  final ghProc = await Process.start(
    proc,
    args,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );

  final exitCode = await ghProc.exitCode;

  if (exitCode != 0) {
    throw ProcessException(proc, args, 'Process failed', exitCode);
  }
}

Future<void> withSystemTemp(
  Future<void> Function(Directory directory, String runKey) action, {
  bool deleteTemp = true,
}) async {
  final runKey = '$packageName-${_fileDate()}';
  final tempDir = Directory.systemTemp.createTempSync(runKey);
  try {
    await action(tempDir, runKey);
  } finally {
    if (deleteTemp) {
      tempDir.deleteSync(recursive: true);
    } else {
      printHeader('Temp directory retained at: ${tempDir.path}');
    }
  }
}

void printHeader(Object? value) {
  print(styleBold.wrap(value.toString()));
}

void printDim(Object? value) {
  print(styleDim.wrap(value.toString()));
}

void printError(Object? value) {
  print(wrapWith(value.toString(), [red, styleBold]));
}

final _dateSeparators = RegExp('[-:.]');

String _fileDate() => DateTime.now()
    .toUtc()
    .toIso8601String()
    .split(_dateSeparators)
    .take(5)
    .join('_');
