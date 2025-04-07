[![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose)
[![package publisher](https://img.shields.io/pub/publisher/firehose.svg)](https://pub.dev/packages/firehose/publisher)

## firehose
### What's this?

This is a tool to automate publishing of pub packages from GitHub actions.

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

### Publishing from a specific version of the SDK

Callers may optionally specify the version of the SDK to use when publishing a
package. This can be useful if your package has a very recent minimum SDK
constraint. This is done via the `sdk` input parameter. Note that this parameter
is not required; it defaults to `stable` - using the most recent stable release
of the Dart SDK. To pass this value:

```yaml
jobs:
  publish:
    uses: dart-lang/ecosystem/.github/workflows/publish.yml@main
    with:
      sdk: beta
```

### Publishing from a protected Github environment

Callers may optionally specify the name of a github environment for the publish
job to use. This is useful if you want to require approvals for the publish job
to run. To pass this value:

```yaml
jobs:
  publish:
    uses: dart-lang/ecosystem/.github/workflows/publish.yml@main
    with:
      environment: pub.dev # Can be any name, this is the convention though.
```

Make sure to also require this environment to be present in your package admin
settings. See the [pub.dev documentation][github_environments] on this.


[github_environments]: https://dart.dev/tools/pub/automated-publishing#hardening-security-with-github-deployment-environments

### Workflow docs

The description of the common workflow for repos using this tool can be found at
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.

<br/>

## health

### What's this?

This is a Github workflow to check PR health.

### Conventions and setup

When run from a PR, this tool will check a configurable subset of the following

* The package versioning is correct and consistent, see `firehose` description above.
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
#     ignore_packages: "pkgs/helper_package"
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


### Options

| Name | Type | Description | Example |
| ------------- | ------------- | ------------- | ------------- |
| `checks`  | List of strings  | What to check for in the PR health check | `"version,changelog,license,coverage,breaking,do-not-submit,leaking"` |
| `fail_on`  | List of strings  | Which checks should lead to failure | `"version,changelog,do-not-submit"` |
| `warn_on`  | List of strings  | Which checks should not fail, but only warn | `"license,coverage,breaking,leaking"` |
| `upload_coverage`  | boolean  | Whether to upload the coverage to [coveralls](https://coveralls.io/) | `true` |
| `coverage_web`  | boolean  | Whether to run `dart test -p chrome` for coverage | `false` |
| `flutter_packages`  | List of strings  | List of packages depending on Flutter | `"pkgs/intl_flutter"` |
| `ignore_*`  | List of globs | Files to ignore, where `*` can be `license`, `changelog`, `coverage`, `breaking`, `leaking`, or `donotsubmit` | `"**.g.dart"` |
| `ignore_packages`  | List of globs  | Which packages to ignore completely | `"pkgs/helper_package"` |
| `checkout_submodules`  | boolean  | Whether to checkout submodules of git repositories | `false` |
| `experiments`  | List of strings  | Which experiments should be enabled for Dart | `"native-assets"` |

### Workflow docs

The description of the common workflow for repos using this tool can be found at
https://github.com/dart-lang/ecosystem/wiki/Pull-Request-Health.
