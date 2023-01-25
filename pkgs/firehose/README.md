[![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose)

## What's this?

This is a tool to automate publishing of pub packages from GitHub actions.

## Conventions and setup

When run from a PR, this tool will validate the package pubspecs and and
changelogs and indicate whether the criteria for publishing has been met.
Generally, each PR should add a new entry to the changelog, rev the pubspec
version, and the changelog version and pubspec version should agree.

When run in response to a git tag event (a tag with a pattern like `v1.2.3` or
`name_v1.2.3` for monorepos), this tool will publish the indicated package.

## Pre-release versions

Pre-release versions (aka, `'1.2.3-dev'`) are handled specially; this tool will
validate the package but will not auto-publish it. This can be used to
accumulate several changes and later publish them as a group.

## Disabling auto-publishing

In order to disable package validation and auto-publishing, add the
`publish_to: none` key to your pubspec.

## PR branch actions

For PRs, this tool:

- determines repo packages
- validates that the changelog version equals the pubspec version
- performs a `dart pub publish --dry-run`

## Git tag actions

In reponse to a git tag event, this tool:

- validates the tag is well-formed
- determines the indicated package
- attempts to publish that package (`dart pub publish --force`)

## Mono-repos

This tool can work with either single package repos or with mono-repos (repos
containing several packages). It will scan for and detect packages in a mono
repo; to omit packages from validation and auto-publishing, add a
`publish_to: none` key to its pubspec.

For single package repos, the tag pattern should be `v1.2.3`. For mono-repos,
the tag pattern must be prefixed with the package name, e.g. `foo-v1.2.3`.

## Integrating this tool into a repo

- copy the yaml below into a `.github/workflows/publish.yaml` file in your repo
- update the target branch below if necessary (currently, `main`)
- if publishing from a mono-repo, adjust the 'tags' line below to
  `tags: [ '[A-z]+-v[0-9]+.[0-9]+.[0-9]+*' ]`
- from the pub.dev admin page of your package, enable publishing from GitHub
  Actions

```yaml
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  pull_request:
    branches: [ main ]
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  publish:
    uses: dart-lang/ecosystem/.github/workflows/publish.yml@main
```
