// Test that all headers compile correctly
#include "config.h"
#include "prng.h"
#include "timing.h"
#include "hasher.h"
#include "spinlock.h"
#include "memory.h"
#include "numa.h"
#include "zipf.h"
#include "worker.h"

#include <cstdio>

int main() {
    // Test config.h
    printf("OPS_PER_TRIAL = %lu\n", bench::OPS_PER_TRIAL);

    // Test prng.h
    uint64_t state = 42;
    printf("xorshift64star(42) = %lu\n", bench::xorshift64star(&state));

    // Test timing.h
    auto t0 = bench::get_time();
    auto t1 = bench::get_time();
    printf("diff_ns = %ld\n", bench::diff_ns(t0, t1));

    // Test hasher.h
    bench::FastHasher hasher;
    printf("hash(42) = %zu\n", hasher(42));

    // Test spinlock.h
    bench::SpinLock lock;
    lock.lock();
    lock.unlock();
    printf("spinlock works\n");

    // Test memory.h
    printf("current_rss_kb = %ld\n", bench::get_current_rss_kb());

    // Test numa.h
    auto topo = bench::detect_numa();
    printf("numa_nodes = %d\n", topo.num_nodes);

    // Test zipf.h
    bench::ZipfGenerator zipf(1000, 1.0, 42);
    printf("zipf.next() = %lu\n", zipf.next());

    // Test worker.h
    printf("ops_per_thread(4) = %lu\n", bench::ops_per_thread(4));

    printf("\nAll headers compile and work correctly!\n");
    return 0;
}
