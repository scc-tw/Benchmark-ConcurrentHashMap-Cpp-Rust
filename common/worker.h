#pragma once

#include "config.h"
#include "prng.h"
#include "timing.h"

#include <pthread.h>
#include <sched.h>
#include <vector>
#include <cstdint>

namespace bench {

// Latency sample from a single operation
struct LatencySample {
    uint64_t op_index;
    int thread_id;
    int64_t latency_ns;
};

// Context passed to each worker thread
struct WorkerContext {
    // Thread identity
    int thread_id;
    int core_id;

    // Workload parameters
    uint64_t ops_per_thread;
    uint64_t prng_state;

    // Map pointer (type-erased, cast in benchmark)
    void* map;

    // Barrier for synchronized start
    pthread_barrier_t* barrier;

    // Output: latency samples
    std::vector<LatencySample> latencies;

    // Output: timing
    int64_t duration_ns;
};

// Pin current thread to specific core
inline void pin_thread(int core_id) noexcept {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
}

// Compute per-thread operation count
[[nodiscard]]
constexpr inline uint64_t ops_per_thread(int num_threads) noexcept {
    if (num_threads <= 0) return 0;
    return OPS_PER_TRIAL / static_cast<uint64_t>(num_threads);
}

// Compute per-thread warmup operation count
[[nodiscard]]
constexpr inline uint64_t warmup_per_thread(int num_threads) noexcept {
    if (num_threads <= 0) return 0;
    return WARMUP_OPS / static_cast<uint64_t>(num_threads);
}

// Initialize worker contexts for a benchmark run
[[nodiscard]]
inline std::vector<WorkerContext> create_workers(
    int num_threads,
    const std::vector<int>& core_ids,
    uint64_t base_seed,
    void* map,
    pthread_barrier_t* barrier
) {
    std::vector<WorkerContext> workers(num_threads);

    for (int i = 0; i < num_threads; ++i) {
        workers[i].thread_id = i;
        workers[i].core_id = core_ids[i];
        workers[i].ops_per_thread = ops_per_thread(num_threads);
        workers[i].prng_state = base_seed + static_cast<uint64_t>(i);
        workers[i].map = map;
        workers[i].barrier = barrier;
        workers[i].duration_ns = 0;

        // Pre-allocate latency samples
        uint64_t expected_samples = workers[i].ops_per_thread / SAMPLE_INTERVAL + 1;
        workers[i].latencies.reserve(expected_samples);
    }

    return workers;
}

} // namespace bench
