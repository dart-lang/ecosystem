// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'combinators.dart';

typedef _AllocateCountersC = Pointer<Uint8> Function(Size size);
typedef _AllocateCountersDart = Pointer<Uint8> Function(int size);

/// C signature for the per-input callback invoked by `LLVMFuzzerTestOneInput`.
typedef DartFuzzCallbackC = Int32 Function(Pointer<Uint8> data, Size size);

typedef _StartFuzzerWithArgsC = Int32 Function(
  Pointer<NativeFunction<DartFuzzCallbackC>> callback,
  Int32 argc,
  Pointer<Pointer<Uint8>> argv,
);
typedef _StartFuzzerWithArgsDart = int Function(
  Pointer<NativeFunction<DartFuzzCallbackC>> callback,
  int argc,
  Pointer<Pointer<Uint8>> argv,
);

typedef _RegisterDartCountersC = Void Function(Pointer<Uint8> start, Size size);
typedef _RegisterDartCountersDart = void Function(
  Pointer<Uint8> start,
  int size,
);

typedef _TraceCmp8WithPcC = Void Function(
  Uint64 arg1,
  Uint64 arg2,
  Uint64 fakePc,
);
typedef _TraceCmp8WithPcDart = void Function(int arg1, int arg2, int fakePc);

typedef _TraceMemcmpC = Void Function(
  Uint64 callerPc,
  Pointer<Uint8> s1,
  Pointer<Uint8> s2,
  Size n,
  Int32 result,
);
typedef _TraceMemcmpDart = void Function(
  int callerPc,
  Pointer<Uint8> s1,
  Pointer<Uint8> s2,
  int n,
  int result,
);

/// Execution mode for [FuzzRuntime.runDriver].
enum FuzzMode {
  /// Coverage-guided fuzzing backed by native LLVM `libFuzzer` via `dart:ffi`.
  cgf,

  /// Pure-Dart coverage- and comparison-guided evolutionary mutator (no native
  /// shared library required).
  pureDart,
}

/// Global coverage and value-profile state for AST-instrumented Dart code.
class FuzzRuntime {
  static const int numCounters = 65536;
  static const int _counterMask = numCounters - 1;

  static Uint8List covMap = Uint8List(numCounters);

  /// Direct per-site hit bitmask indexed by bijective AST site ID (`0..65535`).
  ///
  /// Bit 0 (`0x1`) indicates an edge or comparison `true` branch was reached;
  /// bit 1 (`0x2`) indicates a comparison `false` branch was reached.
  static Uint8List siteHits = Uint8List(numCounters);

  static _TraceCmp8WithPcDart? _traceCmp8WithPc;
  static _TraceMemcmpDart? _traceMemcmp;
  static _StartFuzzerWithArgsDart? _startFuzzerWithArgs;
  static _AllocateCountersDart? _allocate;

  static const int _numSlots = 16;
  static const int _slotStride = 16;
  static const int _scratchBytesLen = (_numSlots + 1) * _slotStride;

  static Pointer<Uint8>? _covPtr;
  static Pointer<Uint8>? _siteHitsPtr;
  static Pointer<Uint8>? _s1Ptr;
  static Pointer<Uint8>? _s2Ptr;
  static Uint8List _s1View = Uint8List(_scratchBytesLen);
  static Uint8List _s2View = Uint8List(_scratchBytesLen);
  static final Int32List _slotIds = Int32List(_numSlots);
  static final Int32List _slotLens = Int32List(_numSlots);
  static final Uint8List _slotPrefixMatched = Uint8List(_numSlots);
  static final Int32List _callerCtxForLoop = Int32List(_numSlots);

  // Pure-Dart TORC (Table of Recent Compares) ring buffers for pureDart mode.
  static const int _torcSize = 64;
  static final Int64List _torcIntsA = Int64List(_torcSize);
  static final Int64List _torcIntsB = Int64List(_torcSize);
  static int _torcIntCursor = 0;
  static final List<Uint8List> _torcBytes = List<Uint8List>.filled(
    _torcSize,
    Uint8List(0),
  );
  static int _torcBytesCursor = 0;

  static int prevLoc = 0;
  static int _prevEdge = 0;
  static int _prevPrevEdge = 0;
  static int _lastLoopId = 0;
  static int _loopContextId = 0;
  static FuzzMode? _initializedMode;

  /// Initializes the runtime for [mode] (`FuzzMode.cgf` by default, or read
  /// from `DASH_FUZZ_MODE=pure-dart`).
  static void init({FuzzMode? mode, String? libraryPath}) {
    final targetMode = mode ?? _resolveModeFromEnv();
    if (_initializedMode == targetMode) return;

    if (targetMode == FuzzMode.pureDart) {
      covMap = Uint8List(numCounters);
      if (_siteHitsPtr == null) {
        siteHits = Uint8List(numCounters);
      }
      _s1View = Uint8List(_scratchBytesLen);
      _s2View = Uint8List(_scratchBytesLen);
      _traceCmp8WithPc = null;
      _traceMemcmp = null;
      _initializedMode = FuzzMode.pureDart;
      return;
    }

    final lib = _loadLibrary(libraryPath: libraryPath);
    final allocate = lib
        .lookupFunction<_AllocateCountersC, _AllocateCountersDart>(
          'AllocateCounters',
          isLeaf: true,
        );
    _allocate = allocate;
    final registerDartCounters = lib
        .lookupFunction<_RegisterDartCountersC, _RegisterDartCountersDart>(
          'RegisterDartCounters',
        );
    final registerSiteHits = lib
        .lookupFunction<_RegisterDartCountersC, _RegisterDartCountersDart>(
          'RegisterSiteHits',
        );
    _traceCmp8WithPc = lib
        .lookupFunction<_TraceCmp8WithPcC, _TraceCmp8WithPcDart>(
          'TraceCmp8WithPc',
          isLeaf: true,
        );
    _traceMemcmp = lib.lookupFunction<_TraceMemcmpC, _TraceMemcmpDart>(
      'TraceMemcmp',
      isLeaf: true,
    );
    _startFuzzerWithArgs = lib
        .lookupFunction<_StartFuzzerWithArgsC, _StartFuzzerWithArgsDart>(
          'StartFuzzerWithArgs',
        );

    var covPtr = _covPtr;
    if (covPtr == null) {
      covPtr = allocate(numCounters);
      _covPtr = covPtr;
      registerDartCounters(covPtr, numCounters);
    }
    covMap = covPtr.asTypedList(numCounters);

    var siteHitsPtr = _siteHitsPtr;
    if (siteHitsPtr == null) {
      siteHitsPtr = allocate(numCounters);
      _siteHitsPtr = siteHitsPtr;
      final nativeSiteHits = siteHitsPtr.asTypedList(numCounters);
      // Preserve any hits recorded before init() completed.
      for (var i = 0; i < numCounters; i++) {
        nativeSiteHits[i] = siteHits[i];
      }
      siteHits = nativeSiteHits;
      registerSiteHits(siteHitsPtr, numCounters);
    }

    final s1Ptr = _s1Ptr ??= allocate(_scratchBytesLen);
    final s2Ptr = _s2Ptr ??= allocate(_scratchBytesLen);
    _s1View = s1Ptr.asTypedList(_scratchBytesLen);
    _s2View = s2Ptr.asTypedList(_scratchBytesLen);
    _initializedMode = FuzzMode.cgf;
  }

  static FuzzMode _resolveModeFromEnv() {
    final envMode = Platform.environment['DASH_FUZZ_MODE'];
    if (envMode == 'pure-dart') return FuzzMode.pureDart;
    return FuzzMode.cgf;
  }

  static DynamicLibrary _loadLibrary({String? libraryPath}) {
    final ext = Platform.isMacOS ? 'dylib' : 'so';
    final envPath = Platform.environment['DASH_FUZZ_LIB_PATH'];
    final paths = <String>[
      if (libraryPath != null && libraryPath.isNotEmpty) libraryPath,
      if (envPath != null && envPath.isNotEmpty) envPath,
      '.dart_tool/dash_fuzz/libfuzzer_poc.$ext',
      Platform.script.resolve('libfuzzer_poc.$ext').toFilePath(),
      'libfuzzer_poc.$ext',
    ];
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      try {
        return DynamicLibrary.open(path);
      } on Object {
        // Try next candidate path.
      }
    }
    throw StateError(
      'Failed to load libfuzzer_poc.$ext from candidate paths: $paths.\n'
      'Run via `dart run dash_fuzz run` to compile fuzzer.cc with clang++, '
      'or set DASH_FUZZ_MODE=pure-dart for pure-Dart execution.',
    );
  }

  static void _resetPerInputState() {
    prevLoc = 0;
    _prevEdge = 0;
    _prevPrevEdge = 0;
    _lastLoopId = 0;
    _loopContextId = 0;
    for (var i = 0; i < _numSlots; i++) {
      _slotIds[i] = -1;
      _slotLens[i] = 0;
      _slotPrefixMatched[i] = 1;
      _callerCtxForLoop[i] = 0;
    }
  }

  /// Writes [siteHits] to [outputPath] (or `DASH_FUZZ_SITE_HITS_PATH` if set).
  static void flushSiteHits([String? outputPath]) {
    final targetPath =
        outputPath ?? Platform.environment['DASH_FUZZ_SITE_HITS_PATH'];
    if (targetPath == null || targetPath.isEmpty) return;
    File(targetPath).writeAsBytesSync(siteHits);
  }

  /// Drives [target] using either native `libFuzzer` ([FuzzMode.cgf]) or the
  /// pure-Dart coverage-guided mutator ([FuzzMode.pureDart]).
  static int runDriver(
    int Function(Uint8List data) target, {
    List<String> fuzzerArgs = const ['-runs=100000'],
    FuzzMode? mode,
    String? libraryPath,
  }) {
    final resolvedMode = mode ?? _resolveModeFromEnv();
    init(mode: resolvedMode, libraryPath: libraryPath);
    try {
      if (resolvedMode == FuzzMode.pureDart) {
        return _runPureDartDriver(target, fuzzerArgs: fuzzerArgs);
      }
      return _runNativeDriver(target, fuzzerArgs: fuzzerArgs);
    } finally {
      flushSiteHits();
    }
  }

  static int _runNativeDriver(
    int Function(Uint8List data) target, {
    required List<String> fuzzerArgs,
  }) {
    final allocate = _allocate!;
    final startFuzzer = _startFuzzerWithArgs!;

    int callbackImpl(Pointer<Uint8> data, int size) {
      _resetPerInputState();
      // Copy input bytes out of libFuzzer's scratch buffer so retained slices
      // never point to freed or overwritten native memory.
      final copy = Uint8List.fromList(data.asTypedList(size));
      try {
        return target(copy);
      } on Object catch (e, st) {
        flushSiteHits();
        _reportUnhandledCrash(copy, e, st);
      }
    }

    final callable = NativeCallable<DartFuzzCallbackC>.isolateLocal(
      callbackImpl,
      exceptionalReturn: 0,
    );
    try {
      final allArgs = <String>['dart_fuzzer', ...fuzzerArgs];
      final argvPtr = allocate((allArgs.length + 1) * sizeOf<Pointer<Uint8>>())
          .cast<Pointer<Uint8>>();
      for (var i = 0; i < allArgs.length; i++) {
        final bytes = utf8.encode(allArgs[i]);
        final strPtr = allocate(bytes.length + 1);
        strPtr.asTypedList(bytes.length).setAll(0, bytes);
        strPtr[bytes.length] = 0;
        argvPtr[i] = strPtr;
      }
      return startFuzzer(callable.nativeFunction, allArgs.length, argvPtr);
    } finally {
      callable.close();
    }
  }

  static Never _reportUnhandledCrash(
    Uint8List data,
    Object error,
    StackTrace st,
  ) {
    final hex = data
        .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
        .join(', ');
    final printable = String.fromCharCodes(
      data.map((b) => (b >= 32 && b < 127) ? b : 0x2E),
    );
    stderr
      ..writeln('\n========================================================')
      ..writeln('UNHANDLED EXCEPTION IN FUZZ TARGET!')
      ..writeln('Input (${data.length} bytes): [$hex]')
      ..writeln('ASCII preview: "$printable"')
      ..writeln('Exception (${error.runtimeType}): $error')
      ..writeln(
        'Stack trace (top 8 frames):\n'
        '${st.toString().split('\n').take(8).join('\n')}',
      )
      ..writeln('========================================================\n');
    exit(77);
  }

  static int _runPureDartDriver(
    int Function(Uint8List data) target, {
    required List<String> fuzzerArgs,
  }) {
    final (:runs, :maxLen, :maxTotalTime, :corpusPaths) = _parsePureDartFlags(
      fuzzerArgs,
    );
    final rng = Random(1337);
    final globalMaxMap = Uint8List(numCounters);
    final corpus = <Uint8List>[
      Uint8List(0),
      ..._loadSeedCorpusFiles(corpusPaths),
      for (final hex in fuzzBoundaryHexStrings)
        Uint8List.fromList(ascii.encode('$hex\r\n')),
    ];
    final initialCorpusLen = corpus.length;
    final stopwatch = maxTotalTime > 0 ? (Stopwatch()..start()) : null;

    for (var i = 0; i < runs; i++) {
      if (stopwatch != null &&
          stopwatch.elapsedMilliseconds >= maxTotalTime * 1000) {
        break;
      }
      final isInitialSeed = i < initialCorpusLen;
      final mutated = isInitialSeed
          ? corpus[i]
          : _mutatePureDartInput(
              corpus[rng.nextInt(corpus.length)],
              rng,
              maxLen,
            );
      covMap.fillRange(0, numCounters, 0);
      _resetPerInputState();
      final copy = Uint8List.fromList(mutated);
      try {
        target(copy);
      } on Object catch (e, st) {
        flushSiteHits();
        _reportUnhandledCrash(copy, e, st);
      }
      if (_mergeCoverage(covMap, globalMaxMap) && !isInitialSeed) {
        corpus.add(mutated);
      }
    }
    return 0;
  }

  static List<Uint8List> _loadSeedCorpusFiles(List<String> paths) {
    final seeds = <Uint8List>[];
    for (final rawPath in paths) {
      final type = FileSystemEntity.typeSync(rawPath);
      if (type == FileSystemEntityType.file) {
        seeds.add(File(rawPath).readAsBytesSync());
      } else if (type == FileSystemEntityType.directory) {
        final files = Directory(rawPath).listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          seeds.add(file.readAsBytesSync());
        }
      }
    }
    return seeds;
  }

  static ({int runs, int maxLen, int maxTotalTime, List<String> corpusPaths})
  _parsePureDartFlags(List<String> args) {
    var runs = 50000;
    var maxLen = 64;
    var maxTotalTime = 0;
    final corpusPaths = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-runs=')) {
        runs = int.tryParse(arg.substring('-runs='.length)) ?? runs;
      } else if (arg.startsWith('-max_len=')) {
        maxLen = int.tryParse(arg.substring('-max_len='.length)) ?? maxLen;
      } else if (arg.startsWith('-max_total_time=')) {
        maxTotalTime =
            int.tryParse(arg.substring('-max_total_time='.length)) ??
            maxTotalTime;
      } else if (!arg.startsWith('-')) {
        corpusPaths.add(arg);
      }
    }
    return (
      runs: runs,
      maxLen: maxLen,
      maxTotalTime: maxTotalTime,
      corpusPaths: corpusPaths,
    );
  }

  static bool _mergeCoverage(Uint8List current, Uint8List globalMax) {
    var foundNew = false;
    for (var i = 0; i < numCounters; i++) {
      final c = current[i];
      if (c > globalMax[i]) {
        globalMax[i] = c;
        foundNew = true;
      }
    }
    return foundNew;
  }

  static Uint8List _mutatePureDartInput(
    Uint8List base,
    Random rng,
    int maxLen,
  ) {
    final list = base.toList();
    final op = rng.nextInt(5);
    if (op == 0 && list.length < maxLen) {
      final pos = list.isEmpty ? 0 : rng.nextInt(list.length + 1);
      list.insert(pos, rng.nextInt(256));
    } else if (op == 1 && list.isNotEmpty) {
      list.removeAt(rng.nextInt(list.length));
    } else if (op == 2 && list.isNotEmpty) {
      list[rng.nextInt(list.length)] ^= 1 << rng.nextInt(8);
    } else if (op == 3) {
      final seq = _torcBytes[rng.nextInt(_torcSize)];
      if (seq.isNotEmpty) {
        final pos = list.isEmpty ? 0 : rng.nextInt(list.length);
        final end = min(pos + seq.length, maxLen);
        for (var i = pos; i < end; i++) {
          final byte = seq[i - pos];
          if (i < list.length) {
            list[i] = byte;
          } else {
            list.add(byte);
          }
        }
      }
    } else {
      final idx = rng.nextInt(_torcSize);
      final val = rng.nextBool() ? _torcIntsA[idx] : _torcIntsB[idx];
      final bd = ByteData(8)..setInt64(0, val, Endian.little);
      final bytes = bd.buffer.asUint8List();
      final pos = list.isEmpty ? 0 : rng.nextInt(list.length);
      for (var i = 0; i < 8 && pos + i < maxLen; i++) {
        if (pos + i < list.length) {
          list[pos + i] = bytes[i];
        } else {
          list.add(bytes[i]);
        }
      }
    }
    return Uint8List.fromList(list);
  }

  static void _recordCompare8(int a, int b, int dynamicPc) {
    final nativeTrace = _traceCmp8WithPc;
    if (nativeTrace != null) {
      nativeTrace(a, b, dynamicPc);
      return;
    }
    final slot = (_torcIntCursor++) & (_torcSize - 1);
    _torcIntsA[slot] = a;
    _torcIntsB[slot] = b;
  }

  static void _recordMemcmp(
    int id,
    Pointer<Uint8>? s1Ptr,
    Pointer<Uint8>? s2Ptr,
    int s2Offset,
    int n,
    int cmpResult,
  ) {
    final nativeMemcmp = _traceMemcmp;
    if (nativeMemcmp != null && s1Ptr != null && s2Ptr != null) {
      nativeMemcmp(id, s1Ptr, s2Ptr, n, cmpResult);
      return;
    }
    final slot1 = (_torcBytesCursor++) & (_torcSize - 1);
    _torcBytes[slot1] = Uint8List.fromList(
      _s1View.sublist(s2Offset, s2Offset + n),
    );
    final slot2 = (_torcBytesCursor++) & (_torcSize - 1);
    _torcBytes[slot2] = Uint8List.fromList(
      _s2View.sublist(s2Offset, s2Offset + n),
    );
  }
}

/// Records an AST basic-block or branch edge transition.
@pragma('vm:prefer-inline')
void $fuzzEdge(int edgeId) {
  FuzzRuntime.siteHits[edgeId & 0xFFFF] |= 1;
  _fuzzTransition(edgeId);
}

@pragma('vm:prefer-inline')
void _fuzzTransition(int edgeId) {
  FuzzRuntime._prevPrevEdge = FuzzRuntime._prevEdge;
  FuzzRuntime._prevEdge = edgeId;
  final ctxEdge = (edgeId ^ FuzzRuntime._loopContextId) & 0xFFFF;
  final idx = (FuzzRuntime.prevLoc ^ ctxEdge) & FuzzRuntime._counterMask;
  FuzzRuntime.covMap[idx] = (FuzzRuntime.covMap[idx] + 1) & 0xFF;
  FuzzRuntime.prevLoc = ctxEdge >> 1;
}

void _traceByteLoop(int a, int b, int id) {
  if ((a & ~0xFF) != 0 || (b & ~0xFF) != 0) return;
  if (a == 0 || b == 0) return;
  final ctxId = (id ^ FuzzRuntime._loopContextId) & 0xFFFF;
  final slot = ctxId & (FuzzRuntime._numSlots - 1);
  if (FuzzRuntime._slotIds[slot] != ctxId ||
      FuzzRuntime._slotLens[slot] >= FuzzRuntime._slotStride) {
    FuzzRuntime._slotIds[slot] = ctxId;
    FuzzRuntime._slotLens[slot] = 0;
    FuzzRuntime._slotPrefixMatched[slot] = 1;
  }
  final idx = FuzzRuntime._slotLens[slot]++;
  final base = slot * FuzzRuntime._slotStride;
  FuzzRuntime._s1View[base + idx] = a;
  FuzzRuntime._s2View[base + idx] = b;
  final matched =
      (a == b) || ((a ^ b) == 0x20 && (a | 0x20) >= 0x61 && (a | 0x20) <= 0x7a);
  if (matched && FuzzRuntime._slotPrefixMatched[slot] == 1) {
    _fuzzTransition((id + (idx + 1) * 257) & 0xFFFF);
  } else {
    FuzzRuntime._slotPrefixMatched[slot] = 0;
  }
  final len = idx + 1;
  if (len >= 2) {
    final s1Ptr = FuzzRuntime._s1Ptr;
    final s2Ptr = FuzzRuntime._s2Ptr;
    FuzzRuntime._recordMemcmp(
      ctxId,
      s1Ptr != null ? s1Ptr + base : null,
      s2Ptr != null ? s2Ptr + base : null,
      base,
      len,
      FuzzRuntime._slotPrefixMatched[slot] == 1 ? 0 : 1,
    );
  }
}

void _traceIntCompare(
  int a,
  int b,
  int dynamicPc, {
  required bool isRelational,
}) {
  if (a == 0 || b == 0) return;
  if (isRelational && a <= 64 && b <= 64) return;
  FuzzRuntime._recordCompare8(a, b, dynamicPc);
}

void _traceByteSequence(
  int len1,
  int len2,
  int Function(int) byteAt1,
  int Function(int) byteAt2,
  int id, {
  int? knownDiff,
}) {
  if (len1 != len2) {
    FuzzRuntime._recordCompare8(len1, len2, id ^ 0x100);
  }
  final maxLen = len1 > len2 ? len1 : len2;
  if (maxLen <= 1) return;
  final n = maxLen > 16 ? 16 : maxLen;
  const base = FuzzRuntime._numSlots * FuzzRuntime._slotStride;
  var diff = len1 != len2 ? 1 : 0;
  for (var i = 0; i < n; i++) {
    final b1 = i < len1 ? (byteAt1(i) & 0xFF) : 0;
    final b2 = i < len2 ? (byteAt2(i) & 0xFF) : 0;
    if (b1 != b2) diff = 1;
    FuzzRuntime._s1View[base + i] = b1;
    FuzzRuntime._s2View[base + i] = b2;
  }
  final s1Ptr = FuzzRuntime._s1Ptr;
  final s2Ptr = FuzzRuntime._s2Ptr;
  FuzzRuntime._recordMemcmp(
    id,
    s1Ptr != null ? s1Ptr + base : null,
    s2Ptr != null ? s2Ptr + base : null,
    base,
    n,
    knownDiff ?? diff,
  );
}

void _traceCompareValues(
  Object? a,
  Object? b,
  int id, {
  bool isRelational = false,
}) {
  final dynamicPc = (id ^ (FuzzRuntime._loopContextId >> 3)) & 0x1FF;
  if (a is int && b is int) {
    _traceIntCompare(a, b, dynamicPc, isRelational: isRelational);
    return;
  }
  if (a is String && b is String) {
    _traceByteSequence(
      a.length,
      b.length,
      a.codeUnitAt,
      b.codeUnitAt,
      id,
      knownDiff: a == b ? 0 : 1,
    );
    return;
  }
  if (a is List<int> && b is List<int>) {
    _traceByteSequence(a.length, b.length, (i) => a[i], (i) => b[i], id);
  }
}

@pragma('vm:prefer-inline')
bool _finishEqCompare(Object? a, Object? b, int id, {required bool res}) {
  FuzzRuntime.siteHits[id & 0xFFFF] |= res ? 1 : 2;
  _fuzzTransition(res ? id : ((id ^ 0x5555) & 0xFFFF));
  _traceCompareValues(a, b, id);
  if (a is int && b is int) _traceByteLoop(a, b, id);
  return res;
}

@pragma('vm:prefer-inline')
bool _finishRelCompare(Object? a, Object? b, int id, {required bool res}) {
  FuzzRuntime.siteHits[id & 0xFFFF] |= res ? 1 : 2;
  _fuzzTransition(res ? id : ((id ^ 0x5555) & 0xFFFF));
  _traceCompareValues(a, b, id, isRelational: true);
  return res;
}

/// Instrumented `==` helper.
@pragma('vm:prefer-inline')
bool $fuzzEq(Object? a, Object? b, int id) =>
    _finishEqCompare(a, b, id, res: a == b);

/// Instrumented `!=` helper.
@pragma('vm:prefer-inline')
bool $fuzzNe(Object? a, Object? b, int id) =>
    _finishEqCompare(a, b, id, res: a != b);

/// Instrumented `<` helper.
@pragma('vm:prefer-inline')
bool $fuzzLt(dynamic a, dynamic b, int id) {
  final slot = id & (FuzzRuntime._numSlots - 1);
  if (a == 0) {
    final parentCtx = (FuzzRuntime._lastLoopId != id)
        ? FuzzRuntime._loopContextId
        : 0;
    FuzzRuntime._callerCtxForLoop[slot] =
        ((id ^ FuzzRuntime._prevPrevEdge ^ parentCtx) & 0xFFFF) | 1;
    for (var i = 0; i < FuzzRuntime._numSlots; i++) {
      FuzzRuntime._slotLens[i] = 0;
      FuzzRuntime._slotPrefixMatched[i] = 1;
    }
  }
  final ctx = FuzzRuntime._callerCtxForLoop[slot];
  if (ctx != 0) {
    FuzzRuntime._loopContextId = ctx;
    FuzzRuntime._lastLoopId = id;
  }
  // ignore: avoid_dynamic_calls
  return _finishRelCompare(a, b, id, res: (a < b) as bool);
}

/// Instrumented `<=` helper.
@pragma('vm:prefer-inline')
bool $fuzzLe(dynamic a, dynamic b, int id) =>
    // ignore: avoid_dynamic_calls
    _finishRelCompare(a, b, id, res: (a <= b) as bool);

/// Instrumented `>` helper.
@pragma('vm:prefer-inline')
bool $fuzzGt(dynamic a, dynamic b, int id) =>
    // ignore: avoid_dynamic_calls
    _finishRelCompare(a, b, id, res: (a > b) as bool);

/// Instrumented `>=` helper.
@pragma('vm:prefer-inline')
bool $fuzzGe(dynamic a, dynamic b, int id) =>
    // ignore: avoid_dynamic_calls
    _finishRelCompare(a, b, id, res: (a >= b) as bool);

/// Instrumented `^` helper.
@pragma('vm:prefer-inline')
T $fuzzXor<T>(T a, T b, int id) {
  // ignore: avoid_dynamic_calls
  final res = (a as dynamic) ^ b;
  if (res is int) {
    final isZero = res == 0;
    FuzzRuntime.siteHits[id & 0xFFFF] |= isZero ? 1 : 2;
    _fuzzTransition(isZero ? id : ((id ^ 0x5555) & 0xFFFF));
  } else if (res is bool) {
    FuzzRuntime.siteHits[id & 0xFFFF] |= res ? 1 : 2;
    _fuzzTransition(res ? id : ((id ^ 0x5555) & 0xFFFF));
  } else {
    FuzzRuntime.siteHits[id & 0xFFFF] |= 1;
    _fuzzTransition(id);
  }
  _traceCompareValues(a, b, id);
  if (a is int && b is int) _traceByteLoop(a, b, id);
  return res as T;
}

/// Instrumented `switch` expression wrapper.
@pragma('vm:prefer-inline')
T $fuzzSwitch<T>(T value, List<Object?> cases, int id) {
  $fuzzEdge(id);
  for (var i = 0; i < cases.length; i++) {
    _traceCompareValues(value, cases[i], (id + i) & 0xFFFF);
  }
  return value;
}

/// Records an AST expression branch edge and returns [val].
@pragma('vm:prefer-inline')
T $fuzzExpr<T>(int id, T val) {
  $fuzzEdge(id);
  return val;
}

/// Instrumented boolean condition helper that tracks `TrueOnly` vs `FalseOnly`.
@pragma('vm:prefer-inline')
bool $fuzzBool(bool val, int id) {
  FuzzRuntime.siteHits[id & 0xFFFF] |= val ? 1 : 2;
  _fuzzTransition(val ? id : ((id ^ 0x5555) & 0xFFFF));
  return val;
}
