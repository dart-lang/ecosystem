[![pub package](https://img.shields.io/pub/v/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints)
[![package publisher](https://img.shields.io/pub/publisher/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints/publisher)

## What is this?

This is a set of lints used by the Dart and Flutter teams to analyze their
packages and repositories; it's built on top of
`package:lints/recommended.yaml`.

This package is not meant to be a recommendation for analysis settings for the
wider ecosystem. For our community recommendations, see `package:lints` and
`package:flutter_lints`.

For documentation about customizing static analysis for your project, see
https://dart.dev/tools/analysis.

## Using the Lints

To use the lints, add the package as a dev dependency
in your `pubspec.yaml` file:

```bash
dart pub add dev:dart_flutter_team_lints
```

then, add an `analysis_options.yaml` file to your project:

```yaml
include: package:dart_flutter_team_lints/analysis_options.yaml
```

## Suggesting changes to the lint set

In order to suggest a change to the `package:dart_flutter_team_lints` lint set,
please [file an issue](https://github.com/dart-lang/ecosystem/issues/new/choose)
against the package. A representative group of Dart and Flutter team members,
along with interested parties, will then discuss the lint addition or removal.

Changes to the lint set may be batched up in order to minimize churn for
downstream codebases.

Lint additions may go out in new package major versions. `package:lints` only
ships lint additions in major versions as new lints are effectively breaking
changes for repo CI systems. The packages downstream from this lint set are
more scoped and better known however, so we have more room for flexibility for 
changes to `package:dart_flutter_team_lints`.
