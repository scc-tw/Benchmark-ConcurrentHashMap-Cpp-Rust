# Phase 2: Common Headers

## Objective

Implement 9 shared C++ headers that provide common infrastructure for all benchmark implementations: constants, PRNG, timing, hashing, locking, distributions, worker threads, memory measurement, and NUMA detection.

## Prerequisites

- Phase 1 complete (CMake builds successfully)
- `common/` directory exists
- C++17 compiler available

## Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                    Tier 1: No Dependencies                   │
├─────────┬─────────┬─────────┬─────────┬─────────┬──────────┤
│config.h │ prng.h  │timing.h │hasher.h │spinlock │ memory.h │
│         │         │         │         │   .h    │          │
└────┬────┴────┬────┴────┬────┴─────────┴─────────┴──────────┘
     │         │         │
     │         │         │         ┌─────────┐
     │         └─────────┼────────►│ numa.h  │
     │                   │         └─────────┘
     │                   │
     ▼                   ▼
┌─────────┐       ┌─────────────┐
│ zipf.h  │       │  worker.h   │
│(prng.h) │       │(config,prng,│
└─────────┘       │   timing)   │
                  └─────────────┘
```

## Steps

---

### Step 2.1: Create config.h

**File:** `common/config.h`

**Tasks:**
- [ ] Create config.h with include guards
- [ ] Define OPS_PER_TRIAL = 1,000,000
- [ ] Define WARMUP_OPS = 100,000
- [ ] Define SAMPLE_INTERVAL = 1000
- [ ] Define REPEATS = 40
- [ ] Define map size constants

**Implementation:**
```cpp
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
```

---

### Step 2.2: Create prng.h

**File:** `common/prng.h`

**Purpose:** xorshift64* PRNG - MUST match Rust implementation exactly for fairness.

**Tasks:**
- [ ] Create prng.h with include guards
- [ ] Implement xorshift64star() inline function
- [ ] Use exact bit shift values: 12, 25, 27
- [ ] Use multiplier 0x2545F4914F6CDD1DULL

**Implementation:**
```cpp
#pragma once

#include <cstdint>

namespace bench {

// xorshift64* PRNG
// CRITICAL: Must produce identical sequence to Rust implementation
// Reference: https://en.wikipedia.org/wiki/Xorshift#xorshift*
inline uint64_t xorshift64star(uint64_t* state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

// Generate random number in range [0, max)
inline uint64_t rand_range(uint64_t* state, uint64_t max) {
    return xorshift64star(state) % max;
}

} // namespace bench
```

---

### Step 2.3: Create timing.h

**File:** `common/timing.h`

**Purpose:** High-precision timing using clock_gettime(CLOCK_MONOTONIC_RAW).

**Tasks:**
- [ ] Create timing.h with include guards
- [ ] Include <time.h>
- [ ] Implement get_time() returning timespec
- [ ] Implement diff_ns() returning int64_t nanoseconds

**Implementation:**
```cpp
#pragma once

#include <cstdint>
#include <time.h>

namespace bench {

// Get current time with nanosecond precision
// Uses CLOCK_MONOTONIC_RAW to avoid NTP adjustments
inline struct timespec get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts;
}

// Compute difference in nanoseconds
inline int64_t diff_ns(struct timespec start, struct timespec end) {
    return (end.tv_sec - start.tv_sec) * 1'000'000'000LL
         + (end.tv_nsec - start.tv_nsec);
}

// Convert nanoseconds to ops/sec
inline double ns_to_ops_per_sec(int64_t ns, uint64_t ops) {
    return static_cast<double>(ops) * 1'000'000'000.0 / static_cast<double>(ns);
}

} // namespace bench
```

---

### Step 2.4: Create hasher.h

**File:** `common/hasher.h`

**Purpose:** Custom fast hash function - MUST match Rust implementation exactly.

**Tasks:**
- [ ] Create hasher.h with include guards
- [ ] Define FastHasher struct with operator()
- [ ] Use multiplier 0x517cc1b727220a95ULL

**Implementation:**
```cpp
#pragma once

#include <cstdint>
#include <cstddef>

namespace bench {

// Fast hash function for uint64_t keys
// CRITICAL: Must produce identical hashes to Rust implementation
// Uses FxHash-style multiplication
struct FastHasher {
    size_t operator()(uint64_t key) const noexcept {
        return static_cast<size_t>(key * 0x517cc1b727220a95ULL);
    }
};

} // namespace bench
```

---

### Step 2.5: Create spinlock.h

**File:** `common/spinlock.h`

**Purpose:** Lightweight spinlock using atomic_flag, avoiding syscall overhead of std::mutex.

**Tasks:**
- [ ] Create spinlock.h with include guards
- [ ] Include <atomic>
- [ ] Define SpinLock class with atomic_flag
- [ ] Implement lock() with pause/yield instruction
- [ ] Implement unlock() with memory_order_release

**Implementation:**
```cpp
#pragma once

#include <atomic>

namespace bench {

// Lightweight spinlock for short critical sections
// Avoids syscall overhead of std::mutex (~10x faster uncontended)
// Reference: WebKit WTF::Lock, Cosmopolitan nsync
class SpinLock {
    std::atomic_flag flag_ = ATOMIC_FLAG_INIT;

public:
    void lock() noexcept {
        while (flag_.test_and_set(std::memory_order_acquire)) {
            // Reduce power consumption and improve HT performance
            #if defined(__x86_64__) || defined(_M_X64)
            __builtin_ia32_pause();
            #elif defined(__aarch64__)
            __asm__ volatile("yield");
            #endif
        }
    }

    void unlock() noexcept {
        flag_.clear(std::memory_order_release);
    }

    // RAII guard
    class Guard {
        SpinLock& lock_;
    public:
        explicit Guard(SpinLock& lock) : lock_(lock) { lock_.lock(); }
        ~Guard() { lock_.unlock(); }
        Guard(const Guard&) = delete;
        Guard& operator=(const Guard&) = delete;
    };
};

} // namespace bench
```

---

### Step 2.6: Create memory.h

**File:** `common/memory.h`

**Purpose:** RSS (Resident Set Size) measurement from /proc/self/status.

**Tasks:**
- [ ] Create memory.h with include guards
- [ ] Include <fstream>, <string>
- [ ] Implement get_peak_rss_kb() reading VmHWM
- [ ] Implement get_current_rss_kb() reading VmRSS
- [ ] Return -1 on error

**Implementation:**
```cpp
#pragma once

#include <fstream>
#include <string>
#include <cstdint>

namespace bench {

// Get peak resident set size in KB (VmHWM = High Water Mark)
inline int64_t get_peak_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmHWM:", 0) == 0) {
            // Format: "VmHWM:    12345 kB"
            size_t pos = 6;
            while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t')) {
                ++pos;
            }
            return std::stoll(line.substr(pos));
        }
    }
    return -1;
}

// Get current resident set size in KB
inline int64_t get_current_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmRSS:", 0) == 0) {
            size_t pos = 6;
            while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t')) {
                ++pos;
            }
            return std::stoll(line.substr(pos));
        }
    }
    return -1;
}

// Compute bytes per entry
inline double bytes_per_entry(int64_t rss_kb, uint64_t num_entries) {
    return (static_cast<double>(rss_kb) * 1024.0) / static_cast<double>(num_entries);
}

// Compute overhead ratio (actual / theoretical minimum)
// Theoretical minimum for uint64_t key + uint64_t value = 16 bytes
inline double overhead_ratio(int64_t rss_kb, uint64_t num_entries) {
    double actual = bytes_per_entry(rss_kb, num_entries);
    return actual / 16.0;
}

} // namespace bench
```

---

### Step 2.7: Create numa.h

**File:** `common/numa.h`

**Purpose:** NUMA topology detection and thread pinning strategies.

**Tasks:**
- [ ] Create numa.h with include guards
- [ ] Define NumaTopology struct
- [ ] Define PinningStrategy enum (COMPACT, SPREAD)
- [ ] Implement detect_numa() from /sys filesystem
- [ ] Implement get_cores() for each strategy

**Implementation:**
```cpp
#pragma once

#include <vector>
#include <string>
#include <fstream>
#include <sstream>
#include <dirent.h>
#include <cstdint>

namespace bench {

enum class PinningStrategy {
    COMPACT,  // All threads on consecutive cores (same socket)
    SPREAD    // Threads distributed across NUMA nodes
};

struct NumaTopology {
    int num_nodes = 1;
    std::vector<std::vector<int>> node_cores;  // node_cores[node] = {core_ids}

    int total_cores() const {
        int total = 0;
        for (const auto& cores : node_cores) {
            total += static_cast<int>(cores.size());
        }
        return total;
    }
};

// Parse CPU list format "0-3,8-11" into vector of core IDs
inline std::vector<int> parse_cpulist(const std::string& cpulist) {
    std::vector<int> cores;
    std::stringstream ss(cpulist);
    std::string token;

    while (std::getline(ss, token, ',')) {
        size_t dash = token.find('-');
        if (dash != std::string::npos) {
            int start = std::stoi(token.substr(0, dash));
            int end = std::stoi(token.substr(dash + 1));
            for (int i = start; i <= end; ++i) {
                cores.push_back(i);
            }
        } else {
            cores.push_back(std::stoi(token));
        }
    }
    return cores;
}

// Detect NUMA topology from /sys filesystem
inline NumaTopology detect_numa() {
    NumaTopology topo;
    const std::string base = "/sys/devices/system/node/";

    DIR* dir = opendir(base.c_str());
    if (!dir) {
        // Fallback: single node with all cores
        topo.num_nodes = 1;
        // Read from /sys/devices/system/cpu/online
        std::ifstream online("/sys/devices/system/cpu/online");
        std::string cpulist;
        if (std::getline(online, cpulist)) {
            topo.node_cores.push_back(parse_cpulist(cpulist));
        }
        return topo;
    }

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        if (name.rfind("node", 0) == 0 && name.size() > 4) {
            int node_id = std::stoi(name.substr(4));

            std::string cpulist_path = base + name + "/cpulist";
            std::ifstream cpulist_file(cpulist_path);
            std::string cpulist;
            if (std::getline(cpulist_file, cpulist)) {
                // Ensure vector is large enough
                if (static_cast<size_t>(node_id) >= topo.node_cores.size()) {
                    topo.node_cores.resize(node_id + 1);
                }
                topo.node_cores[node_id] = parse_cpulist(cpulist);
            }
        }
    }
    closedir(dir);

    topo.num_nodes = static_cast<int>(topo.node_cores.size());
    return topo;
}

// Get core IDs for given strategy and thread count
inline std::vector<int> get_cores(const NumaTopology& topo,
                                   PinningStrategy strategy,
                                   int num_threads) {
    std::vector<int> cores;

    if (strategy == PinningStrategy::COMPACT) {
        // Take consecutive cores from first node(s)
        for (const auto& node_cores : topo.node_cores) {
            for (int core : node_cores) {
                cores.push_back(core);
                if (static_cast<int>(cores.size()) >= num_threads) {
                    return cores;
                }
            }
        }
    } else {  // SPREAD
        // Round-robin across nodes
        size_t max_per_node = 0;
        for (const auto& node_cores : topo.node_cores) {
            max_per_node = std::max(max_per_node, node_cores.size());
        }

        for (size_t i = 0; i < max_per_node; ++i) {
            for (const auto& node_cores : topo.node_cores) {
                if (i < node_cores.size()) {
                    cores.push_back(node_cores[i]);
                    if (static_cast<int>(cores.size()) >= num_threads) {
                        return cores;
                    }
                }
            }
        }
    }

    return cores;
}

// Convert strategy to string for CSV output
inline const char* strategy_to_string(PinningStrategy strategy) {
    switch (strategy) {
        case PinningStrategy::COMPACT: return "compact";
        case PinningStrategy::SPREAD:  return "spread";
        default: return "unknown";
    }
}

} // namespace bench
```

---

### Step 2.8: Create zipf.h

**File:** `common/zipf.h`

**Dependencies:** `prng.h`

**Purpose:** Zipfian distribution generator for hotspot workloads.

**Tasks:**
- [ ] Create zipf.h with include guards
- [ ] Include "prng.h"
- [ ] Define ZipfGenerator class
- [ ] Pre-compute harmonic numbers
- [ ] Implement next() using rejection sampling

**Implementation:**
```cpp
#pragma once

#include "prng.h"
#include <cmath>
#include <vector>
#include <cstdint>

namespace bench {

// Zipfian distribution generator
// Generates values in [0, n) with Zipf(s) distribution
// s = 1.0 is standard Zipf's law
class ZipfGenerator {
    uint64_t n_;
    double s_;
    uint64_t prng_state_;

    // Pre-computed values for fast sampling
    double h_integral_x1_;
    double h_integral_n_;
    double s_minus_1_;

    // Compute H(x) = integral of x^(-s) from 1 to x
    double h_integral(double x) const {
        if (s_ == 1.0) {
            return std::log(x);
        }
        return (std::pow(x, 1.0 - s_) - 1.0) / (1.0 - s_);
    }

    // Inverse of h_integral
    double h_integral_inv(double y) const {
        if (s_ == 1.0) {
            return std::exp(y);
        }
        return std::pow(y * (1.0 - s_) + 1.0, 1.0 / (1.0 - s_));
    }

public:
    ZipfGenerator(uint64_t n, double s, uint64_t seed)
        : n_(n), s_(s), prng_state_(seed) {
        s_minus_1_ = s - 1.0;
        h_integral_x1_ = h_integral(1.5) - 1.0;
        h_integral_n_ = h_integral(static_cast<double>(n) + 0.5);
    }

    // Generate next Zipfian-distributed value in [0, n)
    uint64_t next() {
        while (true) {
            // Generate uniform random in [0, 1)
            double u = static_cast<double>(xorshift64star(&prng_state_))
                     / static_cast<double>(UINT64_MAX);

            // Map to [h_integral_x1_, h_integral_n_]
            double h_inv = h_integral_inv(
                h_integral_x1_ + u * (h_integral_n_ - h_integral_x1_)
            );

            uint64_t k = static_cast<uint64_t>(h_inv + 0.5);

            // Clamp to valid range
            if (k < 1) k = 1;
            if (k > n_) k = n_;

            // Acceptance test
            double h_k = h_integral(static_cast<double>(k) + 0.5)
                       - h_integral(static_cast<double>(k) - 0.5);

            double prob = std::pow(static_cast<double>(k), -s_) / h_k;

            double u2 = static_cast<double>(xorshift64star(&prng_state_))
                      / static_cast<double>(UINT64_MAX);

            if (u2 < prob) {
                return k - 1;  // Return 0-indexed
            }
        }
    }
};

} // namespace bench
```

---

### Step 2.9: Create worker.h

**File:** `common/worker.h`

**Dependencies:** `config.h`, `prng.h`, `timing.h`

**Purpose:** Thread worker infrastructure with affinity and barrier synchronization.

**Tasks:**
- [ ] Create worker.h with include guards
- [ ] Include config.h, prng.h, timing.h, pthread.h
- [ ] Define WorkerContext struct
- [ ] Implement pin_thread() using pthread_setaffinity_np
- [ ] Define LatencySample struct

**Implementation:**
```cpp
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
inline void pin_thread(int core_id) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
}

// Compute per-thread operation count
inline uint64_t ops_per_thread(int num_threads) {
    return OPS_PER_TRIAL / static_cast<uint64_t>(num_threads);
}

// Compute per-thread warmup operation count
inline uint64_t warmup_per_thread(int num_threads) {
    return WARMUP_OPS / static_cast<uint64_t>(num_threads);
}

// Initialize worker contexts for a benchmark run
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
```

---

### Step 2.10: Header Compilation Test

**File:** `common/test_headers.cpp`

**Purpose:** Verify all headers compile without errors.

**Tasks:**
- [ ] Create test file including all 9 headers
- [ ] Add minimal usage of each header
- [ ] Compile with -Wall -Wextra -Werror

**Implementation:**
```cpp
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
```

**Compile command:**
```bash
g++ -std=c++17 -Wall -Wextra -Werror -I. -o test_headers test_headers.cpp -lpthread
./test_headers
```

---

### Step 2.11: PRNG Verification Test

**File:** `common/test_prng.cpp`

**Purpose:** Generate PRNG sequence for comparison with Rust implementation.

**Tasks:**
- [ ] Create test file
- [ ] Generate first 10 values from seed 42
- [ ] Output in format for diff with Rust

**Implementation:**
```cpp
#include "prng.h"
#include <cstdio>

int main() {
    uint64_t state = 42;

    printf("PRNG verification (seed=42):\n");
    for (int i = 0; i < 10; ++i) {
        uint64_t val = bench::xorshift64star(&state);
        printf("%d: %lu\n", i, val);
    }

    return 0;
}
```

**Expected output (save for comparison with Rust):**
```
PRNG verification (seed=42):
0: <value>
1: <value>
...
```

**Compile and run:**
```bash
g++ -std=c++17 -I. -o test_prng test_prng.cpp
./test_prng > cpp_prng.txt
```

---

### Step 2.12: Hasher Verification Test

**File:** `common/test_hasher.cpp`

**Purpose:** Generate hash values for comparison with Rust implementation.

**Tasks:**
- [ ] Create test file
- [ ] Hash known keys: 0, 1, 42, 1000000, UINT64_MAX
- [ ] Output for comparison with Rust

**Implementation:**
```cpp
#include "hasher.h"
#include <cstdio>
#include <cstdint>

int main() {
    bench::FastHasher hasher;

    printf("Hasher verification:\n");
    printf("hash(0) = %zu\n", hasher(0));
    printf("hash(1) = %zu\n", hasher(1));
    printf("hash(42) = %zu\n", hasher(42));
    printf("hash(1000000) = %zu\n", hasher(1000000));
    printf("hash(UINT64_MAX) = %zu\n", hasher(UINT64_MAX));

    return 0;
}
```

**Compile and run:**
```bash
g++ -std=c++17 -I. -o test_hasher test_hasher.cpp
./test_hasher > cpp_hasher.txt
```

---

## Verification Checklist

- [ ] All 9 headers created in `common/`
- [ ] `test_headers.cpp` compiles without warnings
- [ ] `test_headers` runs and prints expected output
- [ ] `test_prng` generates reproducible sequence
- [ ] `test_hasher` generates consistent hash values
- [ ] No `-Wall -Wextra` warnings

## Files Created

| File | Purpose | Dependencies |
|------|---------|--------------|
| `common/config.h` | Constants | None |
| `common/prng.h` | xorshift64* PRNG | None |
| `common/timing.h` | clock_gettime wrappers | None |
| `common/hasher.h` | Fast hash function | None |
| `common/spinlock.h` | Lightweight lock | None |
| `common/memory.h` | RSS measurement | None |
| `common/numa.h` | NUMA topology | None |
| `common/zipf.h` | Zipfian distribution | prng.h |
| `common/worker.h` | Thread infrastructure | config.h, prng.h, timing.h |
| `common/test_headers.cpp` | Compilation test | All headers |
| `common/test_prng.cpp` | PRNG verification | prng.h |
| `common/test_hasher.cpp` | Hasher verification | hasher.h |

## Next Phase

After verification, proceed to **Phase 3: C++ Benchmarks** to implement `bench-phmap.cpp` and `bench-libcuckoo.cpp`.
