## What's this?

This is a tool to move existing packages into monorepos.

## Running the tool

```bash
dart run bin/trebuchet.dart \
  --input-name coverage \
  --input-branch-name main \
  --target-branch-name main \
  --input-path ~/projects/coverage/ \
  --target tools \
  --target-path ~/projects/tools/ \
  --git-filter-repo ~/tools/git-filter-repo \
  --dry-run
```

This script automates portions of the instructions at
https://github.com/dart-lang/ecosystem/wiki/Merging-existing-repos-into-a-monorepo.
