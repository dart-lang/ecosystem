## What's this?

This is a tool to move existing packages into monorepos.

## Running this tool

```bash
dart run bin/trebuchet.dart --input-name coverage --branch-name master --input-path ~/projects/coverage/ --target-path ~/projects/tools/ --git-filter-repo ~/tools/git-filter-repo 
```

This basically executes the instructions at https://github.com/dart-lang/ecosystem/wiki/Merging-existing-repos-into-a-monorepo