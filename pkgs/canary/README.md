# Canary: Ecosystem Testing for Dart Packages
Before publishing, send a canary out to test a package against a suite of applications. This helps identify potential breaking changes introduced by package updates, ensuring seamless integration across the ecosystem.

## What does it do?
It checks if your package upgrade would result in failures in the ecosystem. This is achieved by running the following pseudocode:
```dart
for (final app in applicationSuite) {
  if (app.dependencies.contains(package)) {
    pubGet(app);
    analyze(app);
    test(app);

    upgradePackage(app);

    pubGet(app);
    analyze(app);
    test(app);
  }
}
```

## How do I use it?
1. Create a suite of repositories to test against at `.github/test_repos/repos.json`. Follow the schema specified [here](schema.json).
```json
{
    "https://github.com/mosuem/my_app_old_web": {
        "level": "analyze"
    },
    "https://github.com/mosuem/my_app_new_web": {
        "level": "test",
        "packages": {
            "exclude": "intl4x"
        }
    }
}
```

2. Add a workflow file `canary.yaml` with the following contents:
```yaml
name: Canary

on:
  pull_request:
    branches: [ main ]
    types: [opened, synchronize, reopened, labeled, unlabeled]
        
jobs:
  test_ecosystem:
    uses: dart-lang/ecosystem/.github/workflows/canary.yaml@main
    with:
      repos_file: .github/test_repos/repos.json
```

3. To show the markdown result as a comment, also add a workflow file `post_summaries.yaml`
```yaml
name: Comment on the pull request

on:
  # Trigger this workflow after the Health workflow completes. This workflow will have permissions to
  # do things like create comments on the PR, even if the original workflow couldn't.
  workflow_run:
    workflows: 
      - Canary
    types:
      - completed

jobs:
  upload:
    uses: dart-lang/ecosystem/.github/workflows/post_summaries.yaml@main
    permissions:
      pull-requests: write
```

4. Profit!

# Contributing
Contributions are welcome! Please see the [contribution guidelines](../../CONTRIBUTING.md).
