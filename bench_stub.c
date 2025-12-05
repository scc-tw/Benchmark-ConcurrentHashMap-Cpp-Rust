/*
bench_stub.c
- Pthreads skeleton demonstrating:
  - clock_gettime(CLOCK_MONOTONIC_RAW) for timing
  - pthread_setaffinity_np to pin threads
  - simple xorshift64* PRNG
  - sampling per-operation latencies every k ops
This is a skeleton: integrate actual map operations (libcuckoo / phmap calls) in the worker loop.
*/
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <time.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

typedef unsigned long long u64;

static inline u64 xorshift64star(u64 *state) {
    // state must be non-zero
    u64 x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static inline long timespec_to_ns(struct timespec *t) {
    return (long)t->tv_sec * 1000000000L + t->tv_nsec;
}

struct worker_args {
    int thread_id;
    int cpu; // core to pin to
    u64 rng_state;
    uint64_t ops_to_do;
    uint64_t sample_every;
    // pointer to map instance, other params...
};

void pin_thread_to_cpu(int cpu) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);
    int rc = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
    if (rc != 0) {
        fprintf(stderr, "pthread_setaffinity_np failed: %s\n", strerror(rc));
    }
}

void *worker_fn(void *arg) {
    struct worker_args *a = (struct_worker_args *) arg; // fix type name
    // pin thread
    pin_thread_to_cpu(a->cpu);

    // barrier: omitted in this skeleton; caller should sync threads prior to start

    struct timespec t0, t1, op0, op1;
    clock_gettime(CLOCK_MONOTONIC_RAW, &t0);

    uint64_t sample_count = 0;
    // For latency sampling - simple reservoir: write to file or in-memory vector (not implemented)
    for (uint64_t i = 0; i < a->ops_to_do; ++i) {
        u64 r = xorshift64star(&a->rng_state);
        uint64_t key = r; // map to key range as needed

        if (a->sample_every && (i % a->sample_every == 0)) {
            // sample this operation
            clock_gettime(CLOCK_MONOTONIC_RAW, &op0);
            // perform operation (lookup/insert) here...
            clock_gettime(CLOCK_MONOTONIC_RAW, &op1);
            long lat_ns = timespec_to_ns(&op1) - timespec_to_ns(&op0);
            // record sample: thread id, sample_index, lat_ns
            sample_count++;
        } else {
            // perform operation without sampling (fast path)
            // e.g., map.find(key) or map.insert(...)
        }
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &t1);
    long dur_ns = timespec_to_ns(&t1) - timespec_to_ns(&t0);

    // Return or write per-thread results to shared collector (omitted here)
    pthread_exit((void*)(uintptr_t)dur_ns);
    return NULL;
}

int main(int argc, char **argv) {
    // parse arguments, setup map, pre-populate if needed
    // create pthreads, set args, allocate sample buffers
    // barrier + start workers
    // gather per-thread durations, compute aggregate ops/sec and write CSV

    printf("This is a skeleton. Integrate proper map calls and result collection.\n");
    return 0;
}