[![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose)
[![package publisher](https://img.shields.io/pub/publisher/firehose.svg)](https://pub.dev/packages/firehose/publisher)

# package:firehose

`package:firehose` is a collection of tools and GitHub Actions workflows designed to automate package publishing and check PR health in Dart and Flutter repositories.

The package provides two primary workflows:
1. **[Publishing (`publish`)](#publishing)**: Validates and automates publishing packages to pub.dev.
2. **[PR Health (`health`)](#pr-health)**: Runs health and quality checks on pull requests.

---

## Publishing

### What's this?

This is a tool and GitHub Actions workflow (`publish.yaml`) to automate publishing of pub packages from GitHub Actions.

### Conventions and setup

When run from a PR, this tool will validate the package pubspecs and
changelogs and indicate whether the criteria for publishing has been met.
Generally, each PR should add a new entry to the changelog, rev the pubspec
version, and the changelog version and pubspec version should agree.

When run in response to a git tag event (a tag with a pattern like `v1.2.3` or
`name_v1.2.3` for monorepos), this tool will publish the indicated package.

### Pre-release versions

Pre-release versions (aka, `'1.2.3-dev'`) are handled specially; this tool will
validate the package but will not auto-publish it. This can be used to
accumulate several changes and later publish them as a group.

### Disabling auto-publishing

In order to disable package validation and auto-publishing, add the
`publish_to: none` key to your pubspec.

### PR branch actions

For PRs, this tool:

- determines repo packages
- validates that the changelog version equals the pubspec version
- performs a `dart pub publish --dry-run`

### Git tag actions

In response to a git tag event, this tool:

- validates the tag is well-formed
- determines the indicated package
- attempts to publish that package (`dart pub publish --force`)

### Mono-repos

This tool can work with either single package repos or with mono-repos (repos
containing several packages). It will scan for and detect packages in a mono
repo; to omit packages from validation and auto-publishing, add a
`publish_to: none` key to its pubspec.

For single package repos, the tag pattern should be `v1.2.3`. For mono-repos,
the tag pattern must be prefixed with the package name, e.g. `foo-v1.2.3`.

### Integrating this tool into a repo

- copy the yaml below into a `.github/workflows/publish.yaml` file in your repo
- update the target branch below if necessary (currently, `main`)
- if publishing from a mono-repo, adjust the 'tags' line below to
  `tags: [ '[0-9A-z]+-v[0-9]+.[0-9]+.[0-9]+' ]`
- from the pub.dev admin page of your package, enable publishing from GitHub
  Actions

```yaml
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  pull_request:
    branches: [ main ]
    types: [opened, synchronize, reopened, labeled, unlabeled]
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+' ]

jobs:
  publish:
    uses: dart-lang/ecosystem/.github/workflows/publish.yaml@main
    permissions:
      id-token: write
      pull-requests: write
```

#### Enabling comments on forks

- add the following to your `publish.yaml`:
```yaml
    with:
       write-comments: false
``` 
- copy the yaml below into a `.github/workflows/post_summaries.yaml` file in your repo

```yaml
# A CI configuration to write comments on PRs.

name: Comment on the pull request

on:
  workflow_run:
    workflows: 
      - Publish
    types:
      - completed

jobs:
  upload:
    uses: dart-lang/ecosystem/.github/workflows/post_summaries.yaml@main
    permissions:
      pull-requests: write
```

### Options

The `publish` workflow supports the following input parameters under the `with` key:

| Name | Type | Description | Default / Example |
| ------------- | ------------- | ------------- | ------------- |
| `sdk` | string | The channel, or a specific version from a channel, of the Dart SDK to install. | `"stable"` / `"beta"`, `"3.0.0"` |
| `environment` | string | If specified, publishes will be performed from this GitHub environment, which can require additional approvals. | `""` / `"pub.dev"` |
| `use-flutter` | boolean | Whether to setup Flutter in this workflow. Required if any packages in the repository depend on Flutter. | `false` / `true` |
| `write-comments` | boolean | Whether to write validation comments on PRs. Set to `false` if enabling PR comments from forks via `post_summaries.yaml`. | `true` / `false` |
| `checkout_submodules` | boolean | Whether to checkout git submodules. | `false` / `true` |
| `ignore-packages` | string | A comma-separated list of package paths or glob patterns to ignore. | `""` / `"pkgs/helper_package,pkgs/non-published-package*"` |

### Workflow docs

The description of the common workflow for repos using this tool can be found at
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.

<br/>

## PR Health

### What's this?

This is a Github workflow to check PR health.

### Conventions and setup

When run from a PR, this tool will check a configurable subset of the following

* The package versioning is correct and consistent, see [Publishing](#publishing) description above.
* A changelog entry has been added.
* All `.dart` files have a license header.
* How the test coverage is affected by the PR.
* The package versioning takes into account any breaking changes in the PR.
* The PR contains `DO_NOT_SUBMIT` strings in the files or the description.
* Any symbols are visible in the public API, but not exported.

This tool can work with either single package repos or with mono-repos (repos
containing several packages).

### Integrating this tool into a repo

1. Copy the yaml below into a `.github/workflows/health.yaml` file in your repo
2. Update the target branch below if necessary (currently, `main`)

```yaml
name: Health
on:
  pull_request:
    branches: [ main ]
    types: [opened, synchronize, reopened, labeled, unlabeled]
jobs:
  health:
    uses: dart-lang/ecosystem/.github/workflows/health.yaml@main
#   with:
#     sdk: beta
#     checks: "version,changelog,license,coverage,breaking,do-not-submit,leaking"
#     fail_on: "version,changelog,do-not-submit"
#     warn_on: "license,coverage,breaking,leaking"
#     coverage_web: false
#     upload_coverage: false
#     use-flutter: true
#     ignore_license: "**.g.dart"
#     ignore_coverage: "**.mock.dart,**.g.dart"
#     ignore_breaking: "pkgs/helper_package/**"
#     ignore_packages: "pkgs/helper_package2"
#     checkout_submodules: false
#     experiments: "native-assets"
    permissions:
      pull-requests: write
```

3. Copy the yaml below into a `.github/workflows/post_summaries.yaml` file in your repo. This is a [necessary](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/) workaround to get PR Health comments on PRs from forks.

```yaml
name: Comment on the pull request

on:
  # Trigger this workflow after the Health workflow completes. This workflow will have permissions to
  # do things like create comments on the PR, even if the original workflow couldn't.
  workflow_run:
    workflows: 
      - Health
      # - Publish
    types:
      - completed

jobs:
  upload:
    uses: dart-lang/ecosystem/.github/workflows/post_summaries.yaml@main
    permissions:
      pull-requests: write
```

### Checks
| Check | Description |
| :--- | :--- |
| **`license`** | Scans all `.dart` files in the PR to ensure they contain the required license header (e.g., the BSD 3-Clause header used by Dart ecosystem packages). |
| **`coverage`** | Runs tests and calculates code coverage. It compares the coverage of the PR branch against the base branch to report whether coverage has increased, decreased, or stayed the same. |
| **`breaking`** | Analyzes public API changes using `package:dart_apitool`. If breaking changes are detected (e.g., removing a class or changing a method signature), it ensures the version bump reflects a major/breaking change. |
| **`do-not-submit`** | Scans the file contents and the PR description for the string `DO_NOT_SUBMIT`. This prevents developers from accidentally merging debug code, "TODO" shortcuts, or sensitive local configurations. |
| **`leaking`** | Checks for "leaked" symbols—types or classes that are visible in your public API (e.g., used as a return type in a public method) but are not actually exported in your package's main library entry point. |
| **`unused-dependencies`** | Analyzes the imports in your source code against the dependencies listed in `pubspec.yaml` to identify packages that are declared but never actually used, using `package:dependency_validator`. |


### Options

| Name | Type | Description | Example |
| ------------- | ------------- | ------------- | ------------- |
| `checks`  | List of strings  | What to check for in the PR health check | `"changelog,license,coverage,breaking,do-not-submit,leaking,unused-dependencies"` |
| `fail_on`  | List of strings  | Which checks should lead to failure | `"changelog,do-not-submit"` |
| `warn_on`  | List of strings  | Which checks should not fail, but only warn | `"license,coverage,breaking,leaking"` |
| `upload_coverage`  | boolean  | Whether to upload the coverage to [coveralls](https://coveralls.io/) | `true` |
| `coverage_web`  | boolean  | Whether to run `dart test -p chrome` for coverage | `false` |
| `flutter_packages`  | List of strings  | List of packages depending on Flutter | `"pkgs/intl_flutter"` |
| `ignore_*`  | List of globs | Files to ignore, where `*` can be `license`, `changelog`, `coverage`, `breaking`, `leaking`, `donotsubmit`, or `unuseddependencies`. For the `breaking` and `unuseddependencies` checks, the glob should be all files of the package. | `"**.g.dart"` |
| `ignore_packages`  | List of globs  | Which packages to ignore completely | `"pkgs/helper_package"` |
| `checkout_submodules`  | boolean  | Whether to checkout submodules of git repositories | `false` |
| `experiments`  | List of strings  | Which experiments should be enabled for Dart | `"native-assets"` |
| `license`  | String  | The license string to insert if missing. %YEAR% will be replaced with the current year | `"// Copyright %YEAR% ..."` |
| `license_test_string`  | String  | A file containing this string will be considered having a license. | `"// Copyright (c)"` |

### Workflow docs

The description of the common workflow for repos using this tool can be found at
https://github.com/dart-lang/ecosystem/wiki/Pull-Request-Health.

### Running locally

To run the health workflow locally, simply run
```
dart pub global activate --source git https://github.com/dart-lang/ecosystem --git-path pkgs/firehose/
dart pub global run firehose:health
```

or configure it further, for example
```
dart pub global run firehose:health --check unused-dependencies,license --comment test.md
```