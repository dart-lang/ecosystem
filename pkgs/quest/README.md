# Quest: Automated Ecosystem Testing for Dart Packages
Embark your package on a quest of testing against a suite of applications. This helps identify potential breaking changes introduced by package updates, ensuring seamless integration across the ecosystem.

## What does it do?
It checks if your package upgrade would result in failures in the ecosystem. This is achieved by running the following pseudocode:
```dart
for(final app in applicationSuite) {
  if(app.dependencies.contains(package)){
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

2. Add a workflow file with the following contents:
```yaml
name: Ecosystem test

on:
  pull_request:
    branches: [ main ]
    types: [opened, synchronize, reopened, labeled, unlabeled]
        
jobs:
  test_ecosystem:
    uses: dart-lang/ecosystem/.github/workflows/ecosystem_test.yaml@main
    with:
      repos_file: .github/test_repos/repos.json
```

3. To show the markdown result as a comment, also add a workflow file
```yaml
name: Comment on the pull request

on:
  # Trigger this workflow after the Health workflow completes. This workflow will have permissions to
  # do things like create comments on the PR, even if the original workflow couldn't.
  workflow_run:
    workflows: 
      - Health
      - Publish
      - Ecosystem test
    types:
      - completed

jobs:
  upload:
    uses: mosuem/ecosystem/.github/workflows/post_summaries.yaml@main
    permissions:
      pull-requests: write
```

4. Profit!



Automated Testing: Automates the process of testing a Dart package against multiple Flutter applications.
Version Switching: Dynamically updates dependencies to test against specific package versions.
Comprehensive Reporting: Generates a detailed Markdown report summarizing test results, including logs for debugging.
GitHub Integration: Designed for use within GitHub Actions workflows.
Usage
Quest requires four command-line arguments:

repositoriesFile: Path to a JSON file listing the Flutter applications to test against. This file should specify the repository URL, application name, and the testing level for each application.
gitUri: The Git SSH URL of the package being tested.
branch: The branch of the package being tested.
labels: A multi-line string containing GitHub labels used to identify the package under test (e.g., ecosystem-test-{package_name}).
dart bin/quest.dart <repositoriesFile> <gitUri> <branch> <labels>
Example repositoriesFile (applications.json):

{
  "https://github.com/example/app1": {
    "name": "App 1",
    "level": "test"
  },
  "https://github.com/example/app2": {
    "name": "App 2",
    "level": "analyze"
  }
}
The level field specifies the extent of testing:

solve: Run flutter pub get.
analyze: Run flutter analyze (in addition to flutter pub get).
test: Run flutter test (in addition to flutter pub get and flutter analyze).
Workflow
Package Identification: Quest identifies the target package based on the provided labels.
Version Resolution: Constructs a version string for the package being tested, including the Git URL, branch, and path.
Application Iteration: Iterates through the applications defined in the repositoriesFile.
Dependency Check: Checks if each application depends on the target package.
Testing: If a dependency exists, Quest runs tests against the application with the current package version and then with the new version, recording the results.
Reporting: Generates a Markdown comment summarizing the test results for each application and each testing level. The comment includes details about success/failure and logs for debugging.

# Contributing
Contributions are welcome! Please see the contribution guidelines (if available).
