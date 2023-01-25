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
