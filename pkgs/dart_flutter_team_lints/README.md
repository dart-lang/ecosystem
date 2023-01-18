![pub package](https://img.shields.io/pub/v/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints)

## What is this?

This is a set of lints used by the Dart and Flutter teams to analyze their
packages and repositories; it's built on top of
`package:lints/recommended.yaml`.

This package is not meant to be a recommendation for analysis settings for the
wider ecosystem. For our community recommendations, see `package:lints` and
`package:flutter_lints`.

For documentation about customizing static analysis for your project, see
https://dart.dev/guides/language/analysis-options.

## Using the Lints

To use the lints, add a dependency in your `pubspec.yaml` file:

```yaml
dev_dependencies:
  dart_flutter_team_lints: ^0.1.0
```

then, add an `analysis_options.yaml` file to your project:

```yaml
include: package:dart_flutter_team_lints/analysis_options.yaml
```
