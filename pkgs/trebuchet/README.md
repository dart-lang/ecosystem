## What's this?

This is a tool to move existing packages into monorepos.

## Running the tool

```bash
dart run bin/trebuchet.dart \
  --input-name coverage \
  --branch-name main \
  --input-path ~/projects/coverage/ \
  --target labs \
  --target-path ~/projects/tools/ \
  --git-filter-repo ~/tools/git-filter-repo \
  --dry-run
```

This basically executes the instructions at https://github.com/dart-lang/ecosystem/wiki/Merging-existing-repos-into-a-monorepo
