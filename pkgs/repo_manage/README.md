Various and miscellaneous commands to query dart-lang github repos.

## Usage

```
Run various reports on Dart and Flutter related repositories.

Usage: report <command> [arguments]

Global options:
-h, --help    Print this usage information.

Available commands:
  branches          Show the default branch names of Dart and Flutter repos.
  labels            Report on the various labels in use by dart-lang repos.
  labels-update     Audit and update the labels used by dart-lang repos.
  transfer-issues   Bulk transfer issues from one repo to another.
  weekly            Run a week-based report on repo status and activity.

Run "report help <command>" for more information about a command.
```

## Useful dart-lang GitHub searches

dart-lang P0 issues:

- https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+label%3AP0

dart-lang P1 issues:
- https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+label%3AP1

dart-lang PRs with no review:
- https://github.com/pulls?q=is%3Aopen+is%3Apr+archived%3Afalse+org%3Adart-lang+review%3Anone

dart-lang issues with more than 75 reactions:
- https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+reactions%3A%3E75+sort%3Areactions-%2B1-desc+

dart-lang issues with no label:
- https://github.com/issues?q=is%3Aopen+is%3Aissue+archived%3Afalse+org%3Adart-lang+no%3Alabel
