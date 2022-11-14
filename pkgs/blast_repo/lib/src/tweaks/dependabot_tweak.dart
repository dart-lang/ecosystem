import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;
import 'package:yaml_edit/yaml_edit.dart';

import '../repo_tweak.dart';

final _instance = DependabotTweak._();

class DependabotTweak extends RepoTweak {
  factory DependabotTweak() => _instance;

  DependabotTweak._()
      : super(
          name: 'Dependabot',
          description:
              'Ensure "$_filePath" exists and has the correct content.',
        );

  @override
  FutureOr<FixResult> fix(Directory checkout) {
    final file = _dependabotFile(checkout);

    if (file == null) {
      File(p.join(checkout.path, _filePath))
          .writeAsStringSync(dependabotDefaultContent);
      return FixResult(fixes: ['Created $_filePath']);
    }

    final contentString = file.readAsStringSync();

    final newContent = doDependabotFix(contentString, sourceUrl: file.uri);
    if (newContent == contentString) {
      return FixResult.noFixesMade;
    }
    file.writeAsStringSync(newContent);
    return FixResult(fixes: ['Updated $_filePath']);
  }

  File? _dependabotFile(Directory checkout) {
    for (var option in _options) {
      final file = File(p.join(checkout.path, option));
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }
}

String doDependabotFix(String input, {Uri? sourceUrl}) {
  final contentYaml = yaml.loadYaml(
    input,
    sourceUrl: sourceUrl,
  );

  if (contentYaml is! yaml.YamlMap) {
    throw Exception('Not sure what to do. The source file is not a map!');
  }

  final version = contentYaml['version'];
  if (version != 2) {
    throw Exception('Not sure what to do. The version is not `2`!');
  }

  final editor = YamlEditor(input);

  final updates = contentYaml['updates'];
  if (updates is! List) {
    throw Exception(
      'Not sure what to do. There is no "updates" value as a List',
    );
  }

  var found = false;
  for (var i = 0; i < updates.length; i++) {
    final value = updates[i];
    if (value is! Map) {
      continue;
    }

    final packageEcosystem = value['package-ecosystem'];
    if (packageEcosystem is! String) {
      throw Exception(
        'Not sure what to do with a package-ecosystem that is not String',
      );
    }

    if (packageEcosystem != 'github-actions') {
      continue;
    }

    found = true;

    final directory = value['directory'];
    final schedule = value['schedule'];

    if (directory == '/' &&
        schedule is Map &&
        schedule['interval'] == 'monthly') {
      break;
    }

    editor.update(['updates', i], _githubActionValue);
  }

  if (!found) {
    editor.appendToList(['updates'], _githubActionValue);
  }

  return editor.toString();
}

const _filePath = '.github/dependabot.yml';

const _options = [
  _filePath,
  '.github/dependabot.yaml',
];

const dependabotDefaultContent = r'''
# Dependabot configuration file.
# See https://docs.github.com/en/code-security/dependabot/dependabot-version-updates
version: 2

updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
''';

const _githubActionValue = {
  'package-ecosystem': 'github-actions',
  'directory': '/',
  'schedule': {'interval': 'monthly'}
};
