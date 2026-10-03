// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <utility>

using DartFuzzCallback = int (*)(const uint8_t* Data, size_t Size);
static DartFuzzCallback g_dart_callback = nullptr;
static const uint8_t* g_site_hits = nullptr;
static size_t g_site_hits_size = 0;
static bool g_atexit_registered = false;

static void FlushSiteHitsAtExit() {
  if (g_site_hits == nullptr || g_site_hits_size == 0) return;
  const char* path = std::getenv("DASH_FUZZ_SITE_HITS_PATH");
  if (path == nullptr || path[0] == '\0') return;
  FILE* fp = std::fopen(path, "wb");
  if (fp == nullptr) return;
  std::fwrite(g_site_hits, 1, g_site_hits_size, fp);
  std::fclose(fp);
}

extern "C" {

// Provided by libFuzzer (LLVM compiler-rt).
extern void __sanitizer_cov_8bit_counters_init(uint8_t* Start, uint8_t* Stop);
extern void __sanitizer_cov_trace_cmp8(uint64_t Arg1, uint64_t Arg2);
extern void __sanitizer_weak_hook_memcmp(void* caller_pc, const void* s1,
                                         const void* s2, size_t n, int result);
extern int LLVMFuzzerRunDriver(int* argc, char*** argv,
                               int (*UserCb)(const uint8_t* Data, size_t Size));

}  // extern "C"

namespace {

volatile uint32_t g_pc_sink = 0;

template <size_t I>
__attribute__((noinline)) void TraceCmp8Slot(uint64_t arg1, uint64_t arg2) {
  __sanitizer_cov_trace_cmp8(arg1, arg2);
  // Post-call volatile write of distinct immediate `I`:
  // 1. Prevents tail-call optimization (`jmp`), ensuring `call` pushes a
  //    return address onto the stack for `__builtin_return_address(0)`.
  // 2. Makes each instantiation's machine code unique so linker Identical Code
  //    Folding (--icf) cannot collapse the 512 slots into one function.
  g_pc_sink = static_cast<uint32_t>(I);
}

template <size_t... Is>
constexpr std::array<void (*)(uint64_t, uint64_t), sizeof...(Is)>
MakeTraceCmp8Table(std::index_sequence<Is...>) {
  return {&TraceCmp8Slot<Is>...};
}

constexpr auto kTraceCmp8Table =
    MakeTraceCmp8Table(std::make_index_sequence<512>{});

}  // namespace

extern "C" {

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
  if (g_dart_callback != nullptr) {
    return g_dart_callback(Data, Size);
  }
  return 0;
}

uint8_t* AllocateCounters(size_t size) {
  return static_cast<uint8_t*>(calloc(1, size));
}

void RegisterDartCounters(uint8_t* Start, size_t Size) {
  __sanitizer_cov_8bit_counters_init(Start, Start + Size);
}

void RegisterSiteHits(const uint8_t* Start, size_t Size) {
  g_site_hits = Start;
  g_site_hits_size = Size;
  if (!g_atexit_registered) {
    std::atexit(FlushSiteHitsAtExit);
    g_atexit_registered = true;
  }
}

void TraceCmp8(uint64_t Arg1, uint64_t Arg2) {
  __sanitizer_cov_trace_cmp8(Arg1, Arg2);
}

// Disambiguates caller PC across up to 512 comparison sites for libFuzzer's
// ValueProfileMap while also feeding TORC8 (Table of Recent Compares).
void TraceCmp8WithPc(uint64_t Arg1, uint64_t Arg2, uint64_t FakePc) {
  kTraceCmp8Table[FakePc & 0x1FFu](Arg1, Arg2);
}

void TraceMemcmp(uint64_t CallerPc, const uint8_t* S1, const uint8_t* S2,
                 size_t N, int Result) {
  __sanitizer_weak_hook_memcmp(reinterpret_cast<void*>(CallerPc), S1, S2, N,
                               Result);
}

int StartFuzzerWithArgs(DartFuzzCallback callback, int argc, char** argv) {
  g_dart_callback = callback;
  return LLVMFuzzerRunDriver(&argc, &argv, LLVMFuzzerTestOneInput);
}

}  // extern "C"
