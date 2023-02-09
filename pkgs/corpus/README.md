Welcome! There are two tools in this repo - a `deps` tool and a `usage` tool. To
use them, clone this repo, cd to `pkgs/corpus`, and run one of the two tools
below.

## bin/deps.dart

This is a tool to calculate information about which packages depend on a target
package.

It queries pub.dev for the packages that use `<package-name>` and generates a
`.csv` file with the dependent information. This is useful for things like
understanding which packages might be impacted by version changes to the target
package. For an example of the dependency report, see
[matcher.csv](doc/matcher.csv).

### Usage

```
usage: dart bin/deps.dart [options] <package-name>

options:
-h, --help                     Print this usage information.
    --package-limit=<count>    Limit the number of packages to return data for.
    --include-old              Include packages that haven't been published in the last year.
    --include-dev-deps         Include usages from dev dependencies.
```

## bin/usage.dart

This is a tool to calculate the API usage for a package - what parts of a
package's API are typically used by other Dart packages and applications.

It queries pub.dev for the packages that use `<package-name>`, downloads the
referencing packages, analyzes them, and determines which portions of the target
package's API are used. For an example usage report, see
[collection.md](doc/collection.md).

### Usage

```
usage: dart bin/usage.dart [options] <package-name>

options:
-h, --help                     Print this usage information.
    --package-limit=<count>    Limit the number of packages usage data is collected from.
                               (defaults to "100")
    --show-src-references      Report specific references to src/ libraries.
```
