[![Dart CI](https://github.com/dart-lang/ecosystem/actions/workflows/dart.yml/badge.svg)](https://github.com/dart-lang/ecosystem/actions/workflows/dart.yml)

## Overview

This repository is home to general Dart Ecosystem tools and packages.

## Packages

| Package | Description | Version |
|---|---|---|
| [blast_repo](pkgs/blast_repo/) | A tool to bulk validate and fix GitHub repos. |  |
| [corpus](pkgs/corpus/) | A tool to calculate the API usage for a package. |  |
| [dart_flutter_team_lints](pkgs/dart_flutter_team_lints/) | An analysis rule set used by the Dart and Flutter teams. | [![pub package](https://img.shields.io/pub/v/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints) |

## Contributions, PRs, and publishing

When contributing to this repo:

- if the package version is a stable semver version (`x.y.z`), the latest
  changes have been published to pub. Please add a new changelog section for
  your change, rev the service portion of the version, append `-dev`, and update
  the pubspec version to agree with the new version
- if the package version ends in `-dev`, the latest changes are unpublished;
  please add a new changelog entry for your change in the most recent section.
  When we decide to publish the latest changes we'll drop the `-dev` suffix
  from the package version
- for PRs, the `Publish` bot will perform basic validation of the info in the
  pubspec.yaml and CHANGELOG.md files
- when the PR is merged into the main branch, if the change includes reving to
  a new stable version, a repo maintainer will tag that commit with the pubspec
  version (e.g., `v1.2.3`); that tag event will trigger the `Publish` bot to
  publish a new version of the package to pub.dev

For additional information about contributing, see our
[contributing](CONTRIBUTING.md) page.
