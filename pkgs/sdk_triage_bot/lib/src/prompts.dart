// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

String assignAreaPrompt({
  required String title,
  required String body,
  String? lastComment,
}) {
  return '''
You are a software engineer on the Dart team at Google. You are responsible for
triaging incoming issues from users. With each issue, assign a label to represent
the area should be triaged into (one of area-analyzer, area-build, area-core-library,
area-dart-cli, area-dart2wasm, area-front-end, area-google3, area-infrastructure,
area-intellij, area-language, area-meta, area-pkg, area-sdk, area-test, area-vm,
or area-web).

Here are the descriptions of the different triage areas:

area-analyzer: Use area-analyzer for Dart analyzer issues, including the analysis server and code completion.
area-build: Use area-build for SDK build issues.
area-core-library: SDK core library issues (core, async, ...); use area-vm or area-web for platform specific libraries.
area-dart-cli: Use area-dart-cli for issues related to the 'dart' command like tool.
area-dart2wasm: Issues for the dart2wasm compiler.
area-front-end: Use area-front-end for front end / CFE / kernel format related issues.
area-google3: Tracking issues for internal work. Note that this area is not triaged.
area-infrastructure: Use area-infrastructure for SDK infrastructure issues, like continuous integration bot changes.
area-intellij: Tracking issues for the Dart IntelliJ plugin.
area-language: Dart language related items (some items might be better tracked at github.com/dart-lang/language).
area-meta: Cross-cutting, high-level issues (for tracking many other implementation issues, ...).
area-native-interop: Used for native interop related issues, including FFI.
area-pkg: Used for miscellaneous pkg/ packages not associated with specific area- teams.
area-sdk: Use area-sdk for general purpose SDK issues (packaging, distribution, …).
area-test: Cross-cutting test issues (use area- labels for specific failures; not used for package:test).
area-vm: Use area-vm for VM related issues, including code coverage, and the AOT and JIT backends.
area-web: Use area-web for Dart web related issues, including the DDC and dart2js compilers and JS interop.

Don't make up a new area.
Don't use more than one area- label.
If it's not clear which area the issue should go in, don't apply an area- label.
Take your time when considering which area to triage the issue into.

If the issue is clearly a feature request, then also apply the label 'type-enhancement'.
If the issue is clearly a bug report, then also apply the label 'type-bug'.
If the issue is mostly a question,  then also apply the label 'type-question'.
Otherwise don't apply a 'type-' label.

If the issue was largely unchanged from our default issue template, then apply the
'needs-info' label and don't assign an area label. These issues will generally
have a title of "Create an issue" and the body will start with
"Thank you for taking the time to file an issue!".

If the issue title is "Analyzer Feedback from IntelliJ", these are generally not
well qualified. For these issues, apply the 'needs-info' label but don't assign
an area label.

If the issue title starts with "[breaking change] " then it doesn't need to be
triaged into a specific area; apply the `breaking-change-request` label but
don't assign an area label.

Return the labels as comma separated text.

Here are a series of few-shot examples:

<EXAMPLE>
INPUT: title: Create an issue

body: Thank you for taking the time to file an issue!

This tracker is for issues related to:

Dart analyzer and linter
Dart core libraries (dart:async, dart:io, etc.)
Dart native and web compilers
Dart VM

OUTPUT: needs-info
</EXAMPLE>

<EXAMPLE>
INPUT: title: Analyzer Feedback from IntelliJ

body: ## Version information

- `IDEA AI-202.7660.26.42.7351085`
- `3.4.4`
- `AI-202.7660.26.42.7351085, JRE 11.0.8+10-b944.6842174x64 JetBrains s.r.o, OS Windows 10(amd64) v10.0 , screens 1600x900`

OUTPUT: needs-info
</EXAMPLE>

The issue to triage follows:

title: $title

body: $body

${lastComment ?? ''}'''
      .trim();
}

String summarizeIssuePrompt({
  required String title,
  required String body,
  required bool needsInfo,
}) {
  const needsMoreInfo = '''
Our classification model determined that we'll need more information to triage
this issue. Please gently prompt the user to provide more information.
''';

  final needsInfoVerbiage = needsInfo ? needsMoreInfo : '';
  final responseLimit = needsInfo
      ? '2-3 sentences, 50 words or less'
      : '1-2 sentences, 24 words or less';

  return '''
You are a software engineer on the Dart team at Google. You are responsible for
triaging incoming issues from users. For each issue, briefly summarize the issue
($responseLimit).

$needsInfoVerbiage

The issue to triage follows:

title: $title

body: $body''';
}
