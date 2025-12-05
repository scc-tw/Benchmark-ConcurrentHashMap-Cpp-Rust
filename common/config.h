#pragma once

#include <cstdint>

namespace bench {

// Operations per trial (1M)
constexpr uint64_t OPS_PER_TRIAL = 1'000'000;

// Warm-up operations (discarded)
constexpr uint64_t WARMUP_OPS = 100'000;

// Sample every Nth operation for latency (0.1% = every 1000th)
constexpr uint64_t SAMPLE_INTERVAL = 1000;

// Number of repetitions for CLT-based statistics
constexpr int REPEATS = 40;

// Map sizes
constexpr uint64_t SIZE_SMALL  = 100'000;      // ~1.6 MB (L3-resident)
constexpr uint64_t SIZE_MEDIUM = 1'000'000;    // ~16 MB (partial L3)
constexpr uint64_t SIZE_LARGE  = 10'000'000;   // ~160 MB (memory-bound)

// Thread counts to benchmark
constexpr int THREAD_COUNTS[] = {1, 2, 4, 8, 16, 32};
constexpr int NUM_THREAD_COUNTS = sizeof(THREAD_COUNTS) / sizeof(THREAD_COUNTS[0]);

} // namespace bench
