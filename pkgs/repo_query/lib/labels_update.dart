// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';

import 'src/common.dart';

/// A map from the desired canonical label name to the synonyms for that label
/// currently in use by various dart-lang repos.
final Map<String, List<String>> synonyms = {
  'closed-as-intended': [
    'resolution: intended',
    'resolution: works as intended',
  ],
  'closed-cannot-reproduce': ['cannot reproduce', 'cannot-reproduce'],
  'closed-duplicate': ['duplicate', 'resolution: duplicate'],
  'closed-invalid': ['invalid', 'resolution: invalid'],
  'closed-not-planned': [
    'not planned',
    'resolution: not planned',
    'resolution: wontfix',
    'wontfix',
  ],
  'contributions-welcome': ['help wanted', 'state: help wanted'],
  'P0': ['p0 critical', 'p0', 'p0-critical'],
  'P1': ['p1 high', 'p1', 'p1-high'],
  'P2': ['p2 medium', 'p2', 'p2-medium'],
  'P3': ['p3 low', 'p3', 'p3-low'],
  'status-blocked': ['blocked', 'state: blocked'],
  'status-needs-info': [
    'needs info',
    'needs-info',
    'state: needs info',
    'waiting for customer response',
  ],
  'type-bug': ['bug', 'type: bug'],
  'type-code-health': ['code health'],
  'type-documentation': ['documentation', 'docs'],
  'type-enhancement': ['enhancement', 'type: enhancement'],
  'type-infra': ['github_actions', 'infrastructure', 'infra'],
  'type-performance': ['performance', 'type: perf'],
  'type-question': ['question', 'type: question'],
  'type-ux': ['ux'],
};

/// These single-word label names are grandfathered in.
final Set<String> allowList = {
  'dependencies',
  'Epic',
  'meta',
};

/// The cannonical set of dart-lang labels.
const String templateRepoSlug = 'dart-lang/.github';

/// If a package:<name> label exists, ensure it has this color.
final String packageLabelColor = '4774bc';

// todo: help
// todo: --dry-run
// todo: --apply-changes

class LabelsUpdateCommand extends ReportCommand {
  LabelsUpdateCommand()
      : super('labels-update',
            'Audit and update the labels used by dart-lang repos.') {
    argParser.addFlag(
      'apply-changes',
      negatable: false,
      help: 'Rename, edit, and add labels to bring them in line with those '
          "at $templateRepoSlug.\nWARNING: this will make changes to a repo's "
          'labels; please preview the changes first by running without '
          "'--apply-changes'.",
    );
  }

  @override
  String get invocation => '${super.invocation} <repo-org/repo-name>';

  @override
  Future<int> run() async {
    var applyChanges = argResults!['apply-changes'] as bool;

    var rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('For the --audit flag, provide a repo slug '
          '(e.g. dart-lang/foo_repo).');
      return 1;
    }
    return await performAudit(rest, alsoFix: applyChanges);
  }

  Future<int> performAudit(
    List<String> repoSlugs, {
    required bool alsoFix,
  }) async {
    final templateRepo = RepositorySlug.full(templateRepoSlug);

    var templateLabels =
        await reportRunner.github.issues.listLabels(templateRepo).toList()
          ..sort(labelCompare);

    print('## template repo: $templateRepo');
    for (var label in templateLabels) {
      print('  ${label.name} 0x${label.color} "${label.description}"');
    }

    final templateSet = templateLabels.map((l) => l.name).toSet();

    for (var slug in repoSlugs) {
      print('');
      print('## $slug');

      final labelsEncountered = <String>{};

      var labels = await reportRunner.github.issues
          .listLabels(RepositorySlug.full(slug))
          .toList()
        ..sort(labelCompare);

      var advisories = <String, String>{};
      var edits = <String, LabelEdit>{};

      for (var label in labels) {
        IssueLabel? templateLabel;

        if (templateSet.contains(label.name)) {
          labelsEncountered.add(label.name);
          templateLabel =
              templateLabels.firstWhere((l) => l.name == label.name);
        } else if (checkSynonym(label.name) != null) {
          var renameTo = checkSynonym(label.name);
          labelsEncountered.add(renameTo!);
          edits
              .putIfAbsent(label.name, LabelEdit.new)
              .join(LabelEdit(newName: renameTo));
          templateLabel = templateLabels.firstWhere((l) => l.name == renameTo);
        } else if (wellFormed(label.name) != null) {
          advisories[label.name] = wellFormed(label.name)!;
        }

        if (templateLabel != null) {
          if (templateLabel.color != label.color) {
            var edit = edits.putIfAbsent(label.name, LabelEdit.new);
            edit.join(LabelEdit(color: templateLabel.color));
          }
          if (templateLabel.description != label.description) {
            var edit = edits.putIfAbsent(label.name, LabelEdit.new);
            edit.join(LabelEdit(description: templateLabel.description));
          }
        }

        // package: colors
        if (label.name.startsWith('package:') &&
            label.color != packageLabelColor) {
          edits
              .putIfAbsent(label.name, LabelEdit.new)
              .join(LabelEdit(color: packageLabelColor));
        }
      }

      var adds = templateSet.difference(labelsEncountered).map((name) {
        var templateLabel = templateLabels.firstWhere((l) => l.name == name);
        return LabelEdit(
          newName: name,
          color: templateLabel.color,
          description: templateLabel.description,
        );
      });

      // renames
      for (var entry in edits.entries.where((e) => e.value.newName != null)) {
        print('  (rename) ${entry.key}: ${entry.value}');
      }

      // updates
      for (var entry in edits.entries.where((e) => e.value.newName == null)) {
        print('  (update) ${entry.key}: ${entry.value}');
      }

      // adds
      for (var edit in adds) {
        print('  (add) ${edit.newName}: #${edit.color} "${edit.description}"');
      }

      // advisories
      for (var entry in advisories.entries) {
        print('  (consistency) ${entry.key}: ${entry.value}');
      }

      if (alsoFix) {
        print('');
        print('Updating labels for $slug');

        var repoSlug = RepositorySlug.full(slug);
        var repo =
            await reportRunner.github.repositories.getRepository(repoSlug);
        print('  $slug has ${repo.openIssuesCount} issues and '
            '${labels.length} labels.');

        if (slug == templateRepoSlug || slug == 'dart-lang/sdk') {
          print("  skipping: won't update labels for $slug.");
        } else if (repo.openIssuesCount >= 100) {
          print("  skipping: won't update labels when issue count >=100.");
        } else {
          // Perform updates.
          for (var entry in edits.entries) {
            var oldName = entry.key;
            var edit = entry.value;

            print('  updating $oldName: $edit');
            await reportRunner.github.issues.updateLabel(
              repoSlug,
              oldName,
              newName: edit.newName,
              color: edit.color,
              description: edit.description,
            );
          }

          for (var edit in adds) {
            print('  adding ${edit.newName}');
            await reportRunner.github.issues.createLabel(
              repoSlug,
              edit.newName!,
              color: edit.color,
              description: edit.description,
            );
          }

          print('');
          print('  ${repo.htmlUrl}/labels');
        }
      }
    }

    return 0;
  }
}

String? checkSynonym(String label) {
  for (var entry in synonyms.entries) {
    if (entry.value.contains(label.toLowerCase())) {
      return entry.key;
    }
  }

  return null;
}

String? wellFormed(String label) {
  if (allowList.contains(label)) return null;

  if (label.startsWith('package:')) {
    const avoidPrefix = 'package: ';
    if (label.startsWith(avoidPrefix)) {
      return 'rename to package:${label.substring(avoidPrefix.length)}';
    } else {
      return null;
    }
  } else if (label.startsWith('pkg:')) {
    return 'rename to package:${label.substring('pkg:'.length)}';
  } else if (label.contains(' ')) {
    return 'avoid spaces; use lowercase-dashes to join words';
  } else if (label != label.toLowerCase()) {
    return 'avoid upper case; use lowercase names';
  } else if (!label.contains('-')) {
    return 'avoid single word labels (prefer using a category prefix)';
  }

  return null;
}

int labelCompare(IssueLabel a, IssueLabel b) {
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

class LabelEdit {
  String? newName;
  String? color;
  String? description;

  LabelEdit({this.newName, this.color, this.description});

  void join(LabelEdit other) {
    newName ??= other.newName;
    color ??= other.color;
    description ??= other.description;
  }

  @override
  String toString() {
    return [
      if (newName != null) 'rename => $newName',
      if (color != null) 'color => #$color',
      if (description != null) 'description => "${overflow(description!)}"',
    ].join(', ');
  }
}
