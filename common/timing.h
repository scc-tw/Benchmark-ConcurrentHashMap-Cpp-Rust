#pragma once

#include <cstdint>
#include <time.h>

namespace bench {

// Get current time with nanosecond precision
// Uses CLOCK_MONOTONIC_RAW to avoid NTP adjustments
[[nodiscard]]
inline struct timespec get_time() noexcept {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts;
}

// Compute difference in nanoseconds
[[nodiscard]]
inline int64_t diff_ns(struct timespec start, struct timespec end) noexcept {
    return (end.tv_sec - start.tv_sec) * 1'000'000'000LL
         + (end.tv_nsec - start.tv_nsec);
}

// Convert nanoseconds to ops/sec
[[nodiscard]]
inline double ns_to_ops_per_sec(int64_t ns, uint64_t ops) noexcept {
    if (ns == 0) return 0.0;
    return static_cast<double>(ops) * 1'000'000'000.0 / static_cast<double>(ns);
}

} // namespace bench
