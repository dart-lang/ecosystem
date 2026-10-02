// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

export 'src/combinators.dart'
    show
        StreamContractResult,
        captureStreamZoneErrors,
        fuzzBoundaryHexStrings,
        fuzzBoundaryInts,
        verifyChunkSplitEquivalence,
        verifyNoUnescapedCrlf;
export 'src/coverage_report.dart'
    show
        FileCoverageStat,
        PackageCoverageReport,
        computeCoverageReport,
        coverageReportToJson,
        formatCoverageTable;
export 'src/fuzz_runtime.dart'
    show
        $fuzzEdge,
        $fuzzEq,
        $fuzzGe,
        $fuzzGt,
        $fuzzLe,
        $fuzzLt,
        $fuzzNe,
        $fuzzSwitch,
        $fuzzXor,
        FuzzMode,
        FuzzRuntime;
export 'src/instrument_ast.dart'
    show
        AstInstrumentor,
        FuzzSiteEntry,
        OverlayResult,
        PackageOverlayInstrumentor;
export 'src/native_builder.dart'
    show NativeFuzzerBuilder, ToolchainMissingException;
