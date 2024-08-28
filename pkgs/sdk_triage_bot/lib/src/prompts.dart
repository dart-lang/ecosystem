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

Return the labels as comma separated text.

Issue follows:

$title

$body

${lastComment ?? ''}'''
      .trim();
}

String summarizeIssuePrompt({
  required String title,
  required String body,
}) {
  return '''
You are a software engineer on the Dart team at Google. You are responsible for
triaging incoming issues from users. For each issue, briefly summarize the issue
(1-2 sentences, 24 words or less).

Issue follows:

$title

$body''';
}
