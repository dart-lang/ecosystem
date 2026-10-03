Coverage-guided `libFuzzer` + `dart:ffi` AST instrumentor and pure-Dart parser
fuzzing combinators for Dart packages.

`package:dash_fuzz` provides two complementary fuzzing modes:

1. **Coverage-Guided Fuzzing (`--mode=cgf`, default)**: Rewrites the target
   package's `lib/` directory into a non-destructive `.dart_tool/dash_fuzz/`
   AST overlay (leaving the git working tree untouched), compiles the native
   LLVM `libFuzzer` bridge (`fuzzer.cc`) with `clang++`, and drives
   in-process `LLVMFuzzerRunDriver` callbacks at ~60k–105k executions/sec with
   8-bit edge counters, a 512-slot `TraceCmp8WithPc` trampoline table, and
   `TraceMemcmp` byte-loop coalescing.
2. **Pure-Dart Combinators & Fallback Engine (`--mode=pure-dart`)**: Provides
   zero-native streaming chunk-split equivalence oracles
   (`verifyChunkSplitEquivalence`), guarded `StreamTransformer` error-contract
   checkers (`captureStreamZoneErrors`), CRLF injection validators
   (`verifyNoUnescapedCrlf`), 64-bit integer boundary corpora
   (`fuzzBoundaryInts`, `fuzzBoundaryHexStrings`), and an in-process pure-Dart
   coverage-guided mutator when `clang++` is unavailable.

## Usage

### Writing a Fuzz Target

```dart
import 'dart:typed_data';
import 'package:dash_fuzz/dash_fuzz.dart';
import 'package:my_pkg/my_pkg.dart';

void main(List<String> args) {
  FuzzRuntime.runDriver(
    (Uint8List data) {
      try {
        parseMyFormat(data);
      } on FormatException {
        // Expected rejection on malformed input.
      }
      return 0;
    },
    fuzzerArgs: args,
  );
}
```

### Running the Fuzzer CLI

```bash
# Run coverage-guided libFuzzer (requires clang++ with compiler-rt):
dart run dash_fuzz run --package-root=. --target=test/fuzz/my_fuzz.dart

# Run in pure-Dart mode (no clang++ required):
dart run dash_fuzz run --mode=pure-dart --package-root=. --target=test/fuzz/my_fuzz.dart
```

## Memory and Execution Bounds

- **Stateless Harness Callbacks**: Keep the `FuzzRuntime.runDriver` callback
  stateless across invocations (instantiate parser state inside the callback
  rather than appending results to top-level globals).
- **Defensive Input Copying**: `FuzzRuntime` copies each input buffer into the
  Dart heap (`Uint8List.fromList`) before invoking the target callback so
  retained sublist views never reference mutated C scratch memory.
- **Automatic Heap, RSS, and Timeout Ceilings**: `dash_fuzz run` spawns the
  target Dart VM with `--old_gen_heap_size=1024` (1 GB) and passes
  `-rss_limit_mb=2048 -timeout=5` to `libFuzzer`, turning unbounded parser
  allocations or infinite loops into deterministic crash reproducers.

## Per-File AST Coverage Reporting

During AST instrumentation, `dash_fuzz` writes a deterministic site manifest to
`.dart_tool/dash_fuzz/edge_manifest.json` mapping every instrumented branch,
loop, switch case, and comparison site back to its source file, 1-based line
and column, and syntax kind. At the end of each `dash_fuzz run` invocation
(including `-max_total_time` exits and crash terminations), `dash_fuzz` prints
a per-file AST site coverage table and writes
`.dart_tool/dash_fuzz/coverage_report.json` listing exact uncovered line and
column positions to guide corpus seeding and harness expansion.
