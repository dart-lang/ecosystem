[![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose)
[![package publisher](https://img.shields.io/pub/publisher/firehose.svg)](https://pub.dev/packages/firehose/publisher)

# package:firehose

`package:firehose` is a collection of tools and GitHub Actions workflows designed to check PR health and validate package publishing readiness in Dart and Flutter repositories.

The package works with two primary workflows:
1. **[Publishing](#publishing)**: Validates package publishing readiness on pull requests (via the `publish` check in `health.yaml`) and automates publishing to pub.dev on git tags via [`dart-lang/setup-dart`'s `publish.yml`](https://github.com/dart-lang/setup-dart/blob/main/.github/workflows/publish.yml).
2. **[PR Health (`health`)](#pr-health)**: Runs health, quality, and publish-readiness checks on pull requests.

---

## Publishing

### What's this?

Publishing automation splits responsibilities across two workflows:
- **Pull request validation**: Runs via the `publish` check in `dart-lang/ecosystem/.github/workflows/health.yaml` (included in `checks` by default).
- **Tag-triggered publishing**: Runs via `dart-lang/setup-dart/.github/workflows/publish.yml` when a release tag is pushed.

### Conventions and setup

When run from a PR (via the `publish` check in `health.yaml`), `firehose` validates package pubspecs and changelogs and indicates whether the criteria for publishing have been met. Generally, each PR should add a new entry to the changelog, rev the pubspec version, and ensure the changelog version and pubspec version agree.

When a git tag matching the repo's release tag pattern (`v1.2.3` for single-package repos, or `name-v1.2.3` for monorepos) is pushed, `dart-lang/setup-dart/.github/workflows/publish.yml` validates the tag and publishes the package to pub.dev using [automated publishing](https://dart.dev/tools/pub/automated-publishing).

### Pre-release and WIP versions

Work-in-progress versions with a `-wip` pre-release suffix (e.g., `1.2.3-wip`) are validated on PRs without offering a release tag link. This can be used to accumulate several changes and later publish them as a group by removing the `-wip` suffix.

### Disabling auto-publishing

In order to omit a package from publish validation and auto-publishing, add `publish_to: none` to its `pubspec.yaml`.

### PR branch actions (`health.yaml` `publish` check)

For PRs, the `publish` check in `health.yaml`:

- determines repo packages
- validates that the changelog version equals the pubspec version (and that modified packages do not reuse an already-published version)
- performs a `dart pub publish --dry-run`
- posts a summary table with post-merge GitHub release creation links (via `post_summaries.yaml`)

### Mono-repos

`firehose` works with both single-package repos and mono-repos (repos containing several packages). For single-package repos, the default tag pattern is `v1.2.3` (configurable on PRs via `tag_prefix`). For mono-repos, tags are prefixed with the package name, e.g. `foo-v1.2.3`.

### Integrating publishing into a repo

1. Enable PR validation via `.github/workflows/health.yaml` and `.github/workflows/post_summaries.yaml` (see [PR Health](#pr-health) below; `publish` is enabled in `checks` by default).
2. From the pub.dev admin page of your package, enable automated publishing from GitHub Actions.
3. Add a tag-triggered publishing workflow into `.github/workflows/` (pinning `@v1` to a commit SHA if required by your org's security policy, and setting `use-flutter: true` if your package requires the Flutter SDK):

#### Single-package repo (`.github/workflows/publish.yaml`)

```yaml
# A CI configuration to auto-publish pub packages.

name: Publish

on:
  push:
    tags: [ 'v[0-9]+.[0-9]+.[0-9]+*' ]

jobs:
  publish:
    if: ${{ github.repository_owner == 'dart-lang' }}
    permissions:
      id-token: write
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@v1
    with:
      use-flutter: false
```

#### Mono-repo (`.github/workflows/publish_<package>.yaml`, one workflow per package)

```yaml
# A CI configuration to publish package:foo to pub.dev.

name: Publish package:foo

on:
  push:
    tags:
      - 'foo-v[0-9]+.[0-9]+.[0-9]+*'

jobs:
  publish:
    if: ${{ github.repository_owner == 'dart-lang' }}
    permissions:
      id-token: write
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@v1
    with:
      working-directory: pkgs/foo
      use-flutter: false
```

### Workflow docs

The description of the common workflow for repos using this tool can be found at
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.

<br/>

## PR Health

### What's this?

This is a Github workflow to check PR health.

### Conventions and setup

When run from a PR, this tool will check a configurable subset of the following

* Package publishing readiness and version consistency (`publish`), see [Publishing](#publishing) above.
* A changelog entry has been added (`changelog`).
* All `.dart` files have a license header (`license`).
* How the test coverage is affected by the PR (`coverage`).
* The package versioning takes into account any breaking changes in the PR (`breaking`).
* The PR contains `DO_NOT_SUBMIT` strings in the files or the description (`do-not-submit`).
* Any symbols are visible in the public API, but not exported (`leaking`).
* Unused dependencies in `pubspec.yaml` (`unused-dependencies`).

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
#     checks: "changelog,license,coverage,breaking,do-not-submit,leaking,unused-dependencies,publish"
#     fail_on: "changelog,do-not-submit,publish"
#     warn_on: "license,coverage,breaking,leaking,unused-dependencies"
#     coverage_web: false
#     flutter_packages: "pkgs/my_flutter_pkg"
#     ignore_license: "**.g.dart"
#     ignore_coverage: "**.mock.dart,**.g.dart"
#     ignore_breaking: "pkgs/helper_package/**"
#     ignore_publish: "pkgs/helper_package/**"
#     ignore_packages: "pkgs/helper_package2"
#     checkout_submodules: false
#     experiments: "native-assets"
#     tag_prefix: "v"
    permissions:
      pull-requests: write
```

3. Copy the yaml below into a `.github/workflows/post_summaries.yaml` file in your repo. This is a [necessary](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/) workaround to get PR Health comments on PRs from forks.

```yaml
name: Comment on the pull request

on:
  # Trigger this workflow after the Health workflow completes. This workflow will have permissions to
  # do things like create comments on the PR, even if the original workflow couldn't.
  workflow_run: # zizmor: ignore[dangerous-triggers]
    workflows:
      - Health
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
| **`changelog`** | Verifies that modified packages update `CHANGELOG.md` and match the version in `pubspec.yaml`. |
| **`license`** | Scans all `.dart` files in the PR to ensure they contain the required license header (e.g., the BSD 3-Clause header used by Dart ecosystem packages). |
| **`coverage`** | Runs tests and calculates code coverage. It compares the coverage of the PR branch against the base branch to report whether coverage has increased, decreased, or stayed the same. |
| **`breaking`** | Analyzes public API changes using `package:dart_apitool`. If breaking changes are detected (e.g., removing a class or changing a method signature), it ensures the version bump reflects a major/breaking change. |
| **`do-not-submit`** | Scans the file contents and the PR description for the string `DO_NOT_SUBMIT`. This prevents developers from accidentally merging debug code, "TODO" shortcuts, or sensitive local configurations. |
| **`leaking`** | Checks for "leaked" symbols—types or classes that are visible in your public API (e.g., used as a return type in a public method) but are not actually exported in your package's main library entry point. |
| **`unused-dependencies`** | Analyzes the imports in your source code against the dependencies listed in `pubspec.yaml` to identify packages that are declared but never actually used, using `package:dependency_validator`. |
| **`publish`** | Validates publishable packages on the PR (version/changelog consistency, unpublished version check, and `dart pub publish --dry-run`) and generates post-merge GitHub release links. |


### Options

| Name | Type | Description | Example |
| ------------- | ------------- | ------------- | ------------- |
| `checks`  | List of strings  | What to check for in the PR health check | `"changelog,license,coverage,breaking,do-not-submit,leaking,unused-dependencies,publish"` |
| `fail_on`  | List of strings  | Which checks should lead to failure | `"changelog,do-not-submit,publish"` |
| `warn_on`  | List of strings  | Which checks should not fail, but only warn | `"license,coverage,breaking,leaking,unused-dependencies"` |
| `coverage_web`  | boolean  | Whether to run `dart test -p chrome` for coverage | `false` |
| `flutter_packages`  | List of strings  | List of packages depending on Flutter | `"pkgs/intl_flutter"` |
| `ignore_*`  | List of globs | Files to ignore, where `*` can be `license`, `changelog`, `coverage`, `breaking`, `leaking`, `donotsubmit`, `unuseddependencies`, or `publish`. For the `breaking` and `unuseddependencies` checks, the glob should be all files of the package. | `"**.g.dart"` |
| `ignore_packages`  | List of globs  | Which packages to ignore completely | `"pkgs/helper_package"` |
| `checkout_submodules`  | boolean  | Whether to checkout submodules of git repositories | `false` |
| `experiments`  | List of strings  | Which experiments should be enabled for Dart | `"native-assets"` |
| `license`  | String  | The license string to insert if missing. %YEAR% will be replaced with the current year | `"// Copyright %YEAR% ..."` |
| `license_test_string`  | String  | A file containing this string will be considered having a license. | `"// Copyright (c)"` |
| `tag_prefix`  | String  | Prefix before the version in single-package release tags for the `publish` check (defaults to `"v"`). Set to `""` for bare version tags. | `"v"` |

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

## Zizmor compatibility

The `post_summaries` workflow uses a `workflow_run` trigger which is
flagged by zizmor as a risk (`dangerous-triggers`). The risk in this case is
mitigated by not using `actions/checkout` to bring in code from the PR branch,
and by strictly validating the target PR and comment IDs before acting on them.
The elevated `pull-requests: write` permission is used to allow posting the
results of PR health checks and publishing validations as a comment on the PR.
Use a `# zizmor: ignore[dangerous-triggers]` comment to ignore.
