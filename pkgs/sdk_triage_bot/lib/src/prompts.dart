// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(devoncarew): Add additional prompt instructions for `area-pkg` issues.

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

If the issue title starts with "[breaking change]" it was likely created using
existing issue template; do not assign an area label. IMPORTANT: only do this if
the issue title starts with "[breaking change]".

If the issue was largely unchanged from our default issue template, then apply
the 'needs-info' label and don't assign an area label. These issues will
generally have a title of "Create an issue" and the body will start with "Thank
you for taking the time to file an issue!".

If the issue title is "Analyzer Feedback from IntelliJ", these are generally not
well qualified. For these issues, apply the 'needs-info' label but don't assign
an area label.

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

<EXAMPLE>
INPUT: title: Support likely() and unlikely() hints for AOT code optimization

body: ```dart
// Tell the compiler which branches are going to be taken most of the time.

if (unlikely(n == 0)) {
  // This branch is known to be taken rarely.
} else {
  // This branch is expected to be in the hot path.
}

final result = likely(s == null) ? commonPath() : notTakenOften();
```

Please add support for the `likely()` and `unlikely()` optimization hints within branching conditions. The AOT compiler can use these hints to generate faster code in a hot path that contains multiple branches.

OUTPUT: area-vm, type-enhancement, type-performance
</EXAMPLE>

<EXAMPLE>
INPUT: title: Analyzer doesn't notice incorrect return type of generic method

body: dart analyze gives no errors on the follow code:

```dart
void main() {
  method(getB());
}

void method(String b) => print(b);

B getB<B extends A>() {
  return A() as B;
}

class A {}
```
I would have suspected it to say something along the line of **The argument type 'A' can't be assigned to the parameter type 'String'.**

OUTPUT: area-analyzer, type-enhancement
</EXAMPLE>

<EXAMPLE>
INPUT: title: DDC async function stepping improvements

body: Tracking issue to monitor progress on improving debugger stepping through async function bodies.

The new DDC async semantics expand async function bodies into complex state machines. The normal JS stepping semantics don't map cleanly to steps through Dart code given this lowering. There are a couple potential approaches to fix this:
1) Add more logic to the Dart debugger to perform custom stepping behavior when stepping through async code.
2) Modify the async lowering in such a way that stepping more closely resembles stepping through Dart. For example, rather than returning multiple times, the state machine function might be able to yield. Stepping over a yield might allow the debugger to stay within the function body.

OUTPUT: area-web
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
this issue. Thank them for their contribution and gently prompt them to provide
more information.
''';

  final responseLimit = needsInfo ? '' : ' (1-2 sentences, 24 words or less)';

  return '''
You are a software engineer on the Dart team at Google.
You are responsible for triaging incoming issues from users.
For each issue, briefly summarize the issue $responseLimit.

${needsInfo ? needsMoreInfo : ''}

The issue to triage follows:

title: $title

body: $body''';
}
