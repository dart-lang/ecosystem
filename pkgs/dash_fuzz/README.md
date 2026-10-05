Coverage-guided `libFuzzer` + `dart:ffi` AST instrumentor and pure-Dart parser
fuzzing combinators for Dart packages.

`package:dash_fuzz` provides two complementary fuzzing modes:

1. **Coverage-Guided AST Fuzzing (`dash_fuzz run`, `--mode=cgf` default)**:
   Automatically rewrites the target package's `lib/` directory into a
   non-destructive `.dart_tool/dash_fuzz/` AST overlay (leaving your working
   tree untouched), compiles a native LLVM `libFuzzer` bridge (`fuzzer.cc`) with
   `clang++`, and drives in-process `LLVMFuzzerRunDriver` callbacks over
   `dart:ffi` at **~60,000–105,000 executions/sec**—evolving inputs from an
   empty 0-byte seed.
2. **Pure-Dart Property Oracles & Fallback Engine (`--mode=pure-dart`)**:
   Provides zero-FFI test combinators for streaming chunk-split equivalence
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

# Run for 30 seconds in CI and emit coverage_report.json:
dart run dash_fuzz run --package-root=. --target=test/fuzz/my_fuzz.dart -- -max_total_time=30

# Run in pure-Dart mode (no clang++ required):
dart run dash_fuzz run --mode=pure-dart --package-root=. --target=test/fuzz/my_fuzz.dart
```

## Why Uniform Random Bytes Fail ("The Rejection Wall")

If you pass uniform random bytes (`Random.nextInt(256)`) to a real-world parser
in a loop, over 99.9% of inputs bounce off the very first `if` statement or
lexical check—such as a missing `--boundary` prefix in a MIME stream or a
16-digit hex length header in HTTP chunked encoding. Without feedback from
inside the parser, random inputs never reach the deep state-machine transitions
where real bugs hide.

To reach deep parser states, a fuzzer needs **Coverage-Guided Fuzzing (CGF)**:
it must observe which branches each input takes and what constants are compared
so it can evolve inputs that unlock new code paths.

## How Coverage-Guided Fuzzing Works End-to-End

### 1. Why Rewrite Dart Source Code Instead of Using VM Coverage?

In C, C++, and Rust, passing `-fsanitize=fuzzer` to Clang automatically inserts
inline basic-block counters and comparison hooks at compile time. In Dart, the
built-in VM Service coverage API (`getSourceReport(kCoverage)` used by
`dart test --coverage`) cannot drive an evolutionary fuzzer for three reasons:

1. **Cumulative, Not Per-Input**: The Dart VM records whether a token was _ever_
   hit across the isolate's lifetime and strips coverage probes once the JIT
   optimizes a function. Coverage-guided fuzzing requires resetting counters
   before _every single input_ to detect whether a mutation discovered a new
   branch or loop-iteration bucket.
2. **Out-of-Process RPC Overhead**: Querying VM Service coverage over WebSocket
   JSON-RPC or spawning a fresh isolate per input caps throughput at ~10–100
   executions/sec.
3. **Blind to Comparisons**: VM coverage reports line hits, but never tells the
   fuzzer _what values were compared_ in a failed `if (magic == 0xCAFEBABE)` or
   `switch (tag)` check. Without comparison feedback, the fuzzer cannot guess
   multi-byte magic headers or syntax keywords.

### 2. Non-Destructive AST Instrumentation (`.dart_tool/dash_fuzz/`)

To capture fast per-input coverage and comparison operands on a stock Dart VM,
`dash_fuzz run` uses `package:analyzer` to rewrite your package's `lib/` files
into `.dart_tool/dash_fuzz/instrumented/` and generates an overlay
`.dart_tool/dash_fuzz/package_config.json` that redirects `package:<target>/...`
imports to the instrumented copy:

```dart
// Original source (lib/parser.dart):
void checkHeader(int magic, String tag) {
  if (magic == 0xCAFEBABE) {
    if (tag == 'FUZZ') {
      throw StateError('Reached deep state!');
    }
  }
}

// Instrumented overlay (.dart_tool/dash_fuzz/instrumented/lib/parser.dart):
import 'package:dash_fuzz/dash_fuzz.dart';

void checkHeader(int magic, String tag) { $fuzzEdge(40503);
  if ($fuzzBool($fuzzEq(magic, 0xCAFEBABE, 56032), 15530)) { $fuzzEdge(31060);
    if ($fuzzBool($fuzzEq(tag, 'FUZZ', 46590), 6087)) { $fuzzEdge(21617);
      throw StateError('Reached deep state!');
    }
  }
}
```

### 3. The In-Process `libFuzzer` + `dart:ffi` Feedback Loop

When `dash_fuzz run` launches the target script in a child Dart VM,
`FuzzRuntime.runDriver` loads the compiled `fuzzer.cc` shared library and hands
control to `LLVMFuzzerRunDriver`:

- **8-Bit Edge Counters (`$fuzzEdge`)**: `fuzzer.cc` allocates a 64 KB native
  `uint8_t` counter array and registers it with `libFuzzer` via
  `__sanitizer_cov_8bit_counters_init`. Each `$fuzzEdge(id)` call updates the
  native byte directly from Dart (`covMap[(prevLoc ^ id) & 0xFFFF]++`), and
  `libFuzzer` zeroes and scans the buffer before and after every input.
- **Comparison Value Profiling (`$fuzzEq`, `$fuzzLt`, `$fuzzSwitch`)**: Each
  comparison helper calls an `isLeaf: true` FFI trampoline into `libFuzzer`'s
  Table of Recent Compares (TORC) via a 512-slot `TraceCmp8WithPc` trampoline
  table (`__sanitizer_cov_trace_cmp8`) and `TraceMemcmp` byte-loop coalescing
  (`__sanitizer_weak_hook_memcmp`). When your parser checks
  `magic == 0xCAFEBABE` or `tag == 'FUZZ'`, `libFuzzer` immediately learns the
  operands and splices them into subsequent mutations.

### 4. Closing the Loop: Uncovered-Line Audits (`coverage_report.json`)

During AST instrumentation, `dash_fuzz` writes a deterministic site manifest to
`.dart_tool/dash_fuzz/edge_manifest.json` mapping every instrumented branch,
loop, switch case, and comparison site back to its source file, 1-based line and
column, and syntax kind.

At the end of each `dash_fuzz run` invocation (including `-max_total_time` exits
and crash terminations), `dash_fuzz` prints a per-file ASCII coverage table and
writes `.dart_tool/dash_fuzz/coverage_report.json` listing exact
`uncoveredLines` (`line:column` positions of unreached branches) so you can see
where fuzzing plateaued and add targeted seeds or unit tests.

## The Four Parser Oracles (Catching Bugs Beyond Crashes)

In a memory-safe language like Dart, parser bugs rarely manifest as native
segmentation faults. Instead, harnesses combine `dash_fuzz` input generation
with four semantic contracts exported by `package:dash_fuzz/dash_fuzz.dart`:

1. **Strict Exception Contract**: A parser should only reject malformed input
   via its documented domain exception (such as `FormatException`). Catch
   expected syntax errors in your harness callback; any unhandled `RangeError`,
   `TypeError`, `StateError`, `ConcurrentModificationError`, or `AssertionError`
   terminates the run and prints a minimal crash reproducer.
2. **Streaming Chunk-Split Equivalence (`verifyChunkSplitEquivalence`)**: Slices
   an input buffer into deterministic random chunks (including 0-byte and 1-byte
   cuts across multi-byte tokens) and asserts that chunked conversion
   (`startChunkedConversion`) produces the exact same output as single-chunk
   `convert`.
3. **Async Stream Error Contract (`captureStreamZoneErrors`)**: Runs a
   `StreamTransformer` inside `runZonedGuarded` with a timeout to verify that
   parse failures are delivered through `stream.onError` and close cleanly
   rather than escaping as uncaught zone errors or hanging `await stream.toList()`.
4. **Round-Trip & CRLF Header Safety (`verifyNoUnescapedCrlf`,
   `fuzzBoundaryInts`, `fuzzBoundaryHexStrings`)**: Asserts that `toString()` on
   parsed header objects (`MediaType`, `Cookie`) never emits unescaped `\r`,
   `\n`, or `\x00` bytes (preventing HTTP header injection) and re-parses to the
   same value, paired with 64-bit integer overflow boundary seeds.

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
