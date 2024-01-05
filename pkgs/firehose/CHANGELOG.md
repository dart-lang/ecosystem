## 0.5.0

- Split health checks in individual workflows.

## 0.4.2

- Get needed version from `dart_apitool` in PR health checks.

## 0.4.1

- Ensure that packages are listed in lexical order.
- Require the latest `package:http`.
- Delay Github requests by a small delay to avoid http errors.

## 0.4.0

- Switch to using `package:github`.
- Check for `DO_NOT${'_'}SUBMIT` strings in the PR description.

## 0.3.33

- Retry calls to pub.dev API.

## 0.3.32

- Fix an issue validating pre-release git publishing tags (#176).

## 0.3.31

- Add PR Health checks for breaking changes.
- Add PR Health checks for `DO_NOT${'_'}SUBMIT` strings.

## 0.3.30

- Improve support for `-dev` and `-wip` package versions.

## 0.3.29

- Fix an issue rendering longer changelogs (#170).

## 0.3.28

- Fix [#156](https://github.com/dart-lang/ecosystem/issues/156).

## 0.3.27

- Fix Flutter support.

## 0.3.26

- Add support for Flutter package auto-publishing, fixing [#154](https://github.com/dart-lang/ecosystem/issues/154).

## 0.3.25

- Switch to pub.dev API in `package:firehose`.

## 0.3.24

- Fix [#137](https://github.com/dart-lang/ecosystem/issues/137).

## 0.3.23

- Tweak PR health workflow.
- Shorten some text in the markdown summary table.

## 0.3.22

- Add docs for the new `environment` input to the publish action.
- Add coverage for web tests.

## 0.3.21

- Allow empty coverage in PR health checks.

## 0.3.20

- Cache file contents and parsed data in `ChangeLog` class.
- Add code coverage to checks.
- Fix [#125](https://github.com/dart-lang/ecosystem/issues/125).

## 0.3.19

- Clean-up and optimizations.
- Stop depending on `package:collection` now that SDK 3.0.0 has `firstOrNull`.

## 0.3.18

- Add Github workflow for PR health.
- Refactorings to health workflow.
- Require Dart `3.0.0`.

## 0.3.17

- Correctly parse pre-release versions from the CHANGELOG.

## 0.3.16

- More robust version checking, now more diverse changelog formats are accepted.

## 0.3.15

- Make publish tags link to the new release page for that tag, with
  pre-populated fields.

## 0.3.14

- Require Dart `2.19.0`.
- Adjust docs for the recommended tag format to use to trigger publishing
  (support semver release versions, not pre-release versions).
- Support using a `publish-ignore-warnings` label to ignore `dart pub publish`
  dry-run validation failures.
- Update the recommended publish.yaml file to listen for label changes on PRs
  (`types: ...`).

## 0.3.13

- Added the ability to specify the version of the SDK to use for publishing.

## 0.3.12

- Don't have issues creating PR comments fail the job.
- Write a github workflow summary of the publishing status.
- Handle un-publishable packages without a `version`.

## 0.3.11

- Add additional console logging when we encounter GitHub API errors.

## 0.3.10

- Fixed an exception that occurred when no CHANGELOG.md file was present.

## 0.3.9

- Update the 'publishable' PR comment to use a markdown table.

## 0.3.8

- Updated the pubspec `repository` field to reflect the new source location.

## 0.3.7+1

- Fix an issue in the `.github/workflows/publish.yaml` workflow file.

## 0.3.7

- Provide feedback about publishing status as PR comments.

## 0.3.6+1

- Fix an issue with mono-repo tag formats (we should be expecting
  `package_name-v1.2.3`).

## 0.3.6

- Introduce a reusable workflow (`.github/workflows/publish.yaml`).

## 0.3.5

- Improve pub dry run validation.
- Check if the package version is already published.

## 0.3.4

- Run `dart pub publish --dry-run` for non pre-release packages.

## 0.3.3

- Refactor changelog validation.
- No longer just validate packages with changed files.

## 0.3.2+1

- Update the documentation in the readme.

## 0.3.2

- Change the publishing logic to require git tags to publish (`v1.2.3` or for
  mono-repos, `foobar_v1.2.3`).

## 0.3.1

- Adjust the 'no changelog entry' message to indicate the label to apply to
  skip the check.

## 0.3.0+3

- Version rev to re-trigger publishing.

## 0.3.0+2

- Adjust the trigger criteria for publishes.

## 0.3.0+1

- Fixes to the publish workflow.

## 0.3.0

- Updates to the tool to support the new Pub features around publishing from
  GitHub Actions.

## 0.2.2

- Documentation fix.

## 0.2.1

- Update documentation text.

## 0.2.0

- Added a option to not publish pre-release packages; auto-publishing will only
  happen for stable (`'1.2.3'`) or build releases (`'1.2.3+foo'`).
- Add a pub executable - `firehose`.
- Update package documentation.

## 0.2.0-dev.1

- Adjusted how github labels are passing into the script.
- Added additional tests.

## 0.2.0-dev.0

- Added support for publishing packages from GitHub Actions.
- Create a git tag after a successful publish.

## 0.1.0

- Added support for verifying packages from PR branches.
