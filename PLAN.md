# Benchmark Implementation Plan

## Overview

Implementation plan for comparing DashMap (Rust), parallel-hashmap (C++), and libcuckoo (C++) concurrent hash maps with statistically rigorous methodology.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Common Infrastructure                       │
│  prng.h (xorshift64*)  │  timing.h  │  hasher.h  │  config.h   │
└─────────────────────────────────────────────────────────────────┘
         │                      │                      │
         ▼                      ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐
│  bench-phmap    │  │ bench-libcuckoo │  │    bench-dashmap    │
│  (C++/pthread)  │  │  (C++/pthread)  │  │   (Rust/libc FFI)   │
└─────────────────┘  └─────────────────┘  └─────────────────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │    CSV Output (RAW)   │
                    └───────────────────────┘
                                │
         ┌──────────────────────┼──────────────────────┐
         ▼                      ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ run-experiments │  │   aggregate     │  │   gnuplot       │
│     .sh         │  │  -results.py    │  │   scripts       │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Build Strategy

### C++ Dependencies (Local CMake Build)

All C++ dependencies are built locally with CMake to enable maximum optimizations:

```
deps/
├── parallel-hashmap/     # git submodule or fetched
│   └── CMakeLists.txt
├── libcuckoo/            # git submodule or fetched
│   └── CMakeLists.txt
└── CMakeLists.txt        # superbuild
```

**CMake Configuration:**
```cmake
# Global optimization flags
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto -DNDEBUG")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)

# Build dependencies as part of project
add_subdirectory(deps/parallel-hashmap)
add_subdirectory(deps/libcuckoo)
```

**Rationale:**
- Header-only libraries (phmap, libcuckoo) benefit from `-march=native` when compiled with benchmark code
- LTO (Link Time Optimization) enables cross-module inlining
- Local build ensures identical compiler flags across all code
- No system library version mismatches

### Rust Build

```toml
# Cargo.toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"

# .cargo/config.toml
[build]
rustflags = ["-C", "target-cpu=native"]
```

## Project Structure

```
.
├── BENCHMARK_DESIGN.md       # Methodology specification
├── PLAN.md                   # This implementation plan
├── README.md                 # Project documentation
├── CMakeLists.txt            # Root CMake configuration
│
├── deps/                     # C++ dependencies (local build)
│   ├── CMakeLists.txt        # Dependency superbuild
│   ├── parallel-hashmap/     # greg7mdp/parallel-hashmap
│   └── libcuckoo/            # efficient/libcuckoo
│
├── common/                   # Shared C++ headers
│   ├── prng.h                # xorshift64* implementation
│   ├── timing.h              # clock_gettime wrappers
│   ├── hasher.h              # Custom fast hasher
│   ├── zipf.h                # Zipfian distribution
│   ├── config.h              # Constants and configuration
│   ├── worker.h              # Thread worker infrastructure
│   ├── memory.h              # RSS measurement utilities
│   └── numa.h                # NUMA topology detection
│
├── cpp-impl/                 # C++ benchmark implementations
│   ├── CMakeLists.txt
│   ├── bench-phmap.cpp       # parallel-hashmap benchmark
│   └── bench-libcuckoo.cpp   # libcuckoo benchmark
│
├── rust-impl/                # Rust benchmark implementation
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs           # Entry point and CLI
│       ├── prng.rs           # xorshift64* (must match C++)
│       ├── hasher.rs         # Custom hasher (must match C++)
│       ├── scenarios.rs      # Workload implementations
│       ├── affinity.rs       # Thread pinning via libc
│       └── memory.rs         # RSS measurement utilities
│
├── scripts/                  # Automation scripts
│   ├── run-experiments.sh    # Main experiment driver
│   ├── aggregate-results.py  # Statistical analysis
│   └── generate-plots.sh     # gnuplot wrapper
│
├── plots/                    # Gnuplot scripts
│   ├── plot-throughput.gnu
│   ├── plot-latency-cdf.gnu
│   └── plot-scalability.gnu
│
└── results/                  # Output directory (generated)
    ├── raw/                  # Per-trial CSV files
    ├── aggregated/           # Statistical summaries
    └── plots/                # Generated images
```

## Fairness Requirements

### Identical PRNG Implementation

**C++ (common/prng.h):**
```cpp
static inline uint64_t xorshift64star(uint64_t* state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}
```

**Rust (rust-impl/src/prng.rs):**
```rust
pub fn xorshift64star(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545F4914F6CDD1Du64)
}
```

**Verification:** Both implementations must produce identical sequences for same seed.

### Identical Hash Function

**C++ (common/hasher.h):**
```cpp
struct FastHasher {
    size_t operator()(uint64_t key) const noexcept {
        // FxHash-style mixing
        return key * 0x517cc1b727220a95ULL;
    }
};
```

**Rust (rust-impl/src/hasher.rs):**
```rust
pub struct FastHasher;

impl Hasher for FastHasher {
    fn write_u64(&mut self, key: u64) {
        self.hash = key.wrapping_mul(0x517cc1b727220a95u64);
    }
    // ...
}
```

### Map Configuration

| Map | Custom Hasher | Initial Capacity |
|-----|---------------|------------------|
| parallel-hashmap | `phmap::flat_hash_map<K,V,FastHasher>` | `reserve(map_size)` |
| libcuckoo | `cuckoohash_map<K,V,FastHasher>` | `reserve(map_size)` |
| DashMap | `DashMap<K,V,BuildHasherDefault<FastHasher>>` | `with_capacity(map_size)` |

## Workload Scenarios

| ID | Scenario | Start State | Key Generation | R/W Ratio |
|----|----------|-------------|----------------|-----------|
| 1 | insert_only | Empty | `base + tid*n + i` | 0/100 |
| 2 | read_only | M items | Uniform [0,M) | 100/0 |
| 3a | read_majority_99 | M items | Uniform [0,M) | 99/1 |
| 3b | read_majority_95 | M items | Uniform [0,M) | 95/5 |
| 4 | balanced | M items | R:[0,M), W:[M,2M) | 50/50 |
| 5 | zipfian | M items | Zipf(s=1.0) | 90/10 |
| 6 | resize_stress | cap=1024 | Sequential | 0/100 |
| 7a | sequential_keys | Empty | Sequential | 0/100 |
| 7b | random_keys | Empty | Random | 0/100 |

## Timing Infrastructure

```cpp
// common/timing.h
struct timespec get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts;
}

int64_t diff_ns(struct timespec start, struct timespec end) {
    return (end.tv_sec - start.tv_sec) * 1000000000LL
         + (end.tv_nsec - start.tv_nsec);
}
```

### Latency Sampling

- Sample rate: 0.1% (every 1000th operation)
- ~1000 samples per trial (1M ops / 1000)
- Deterministic sampling avoids RNG overhead in hot path

```cpp
for (uint64_t i = 0; i < ops_per_thread; i++) {
    bool sample = (i % SAMPLE_INTERVAL == 0);

    if (sample) t0 = get_time();

    perform_operation(map, key, value);

    if (sample) {
        t1 = get_time();
        latencies[sample_idx++] = diff_ns(t0, t1);
    }
}
```

## Thread Affinity

**C++ (pthread_setaffinity_np):**
```cpp
void pin_thread(int core_id) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
}
```

**Rust (via libc):**
```rust
pub fn pin_thread(core_id: usize) {
    unsafe {
        let mut cpuset: libc::cpu_set_t = std::mem::zeroed();
        libc::CPU_SET(core_id, &mut cpuset);
        libc::pthread_setaffinity_np(
            libc::pthread_self(),
            std::mem::size_of::<libc::cpu_set_t>(),
            &cpuset,
        );
    }
}
```

**Pinning Strategies:**
- **Compact:** Threads on consecutive cores (same socket)
- **Spread:** Threads distributed across sockets

## Statistical Methodology

### Parameters
- **Repetitions:** R = 40 (enables CLT-based CI)
- **Operations per trial:** 1,000,000
- **Warm-up:** 100,000 ops (discarded)

### Confidence Interval Calculation
```python
# aggregate-results.py
import numpy as np

def compute_ci95(samples):
    n = len(samples)
    mean = np.mean(samples)
    std = np.std(samples, ddof=1)
    se = std / np.sqrt(n)
    ci95 = 1.96 * se
    return mean, std, ci95
```

## Memory Efficiency Measurement

### Methodology

Memory efficiency is measured at three levels:

1. **Peak RSS (Resident Set Size)**: Captured via `/proc/<pid>/status` at end of each trial
2. **Memory per Entry**: `peak_rss_kb / map_size` normalized metric
3. **Memory Overhead Ratio**: `actual_memory / theoretical_minimum` where theoretical = `map_size * 16` bytes (key + value)

### Measurement Points

| Map Size | Theoretical Min | Measurement |
|----------|-----------------|-------------|
| 100K | 1.6 MB | After full population |
| 1M | 16 MB | After full population |
| 10M | 160 MB | After full population |

### Implementation

```cpp
// common/memory.h
#include <fstream>
#include <string>

inline int64_t get_peak_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmHWM:", 0) == 0) {  // High Water Mark
            return std::stoll(line.substr(6));
        }
    }
    return -1;
}

inline int64_t get_current_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmRSS:", 0) == 0) {
            return std::stoll(line.substr(6));
        }
    }
    return -1;
}
```

```rust
// rust-impl/src/memory.rs
use std::fs;

pub fn get_peak_rss_kb() -> i64 {
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("VmHWM:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse().ok())
        })
        .unwrap_or(-1)
}
```

### Memory Efficiency Metrics in CSV

Additional columns in output:
```
peak_rss_kb,current_rss_kb,bytes_per_entry,overhead_ratio
```

## NUMA Topology Benchmarking

### Objective

Quantify NUMA effects on concurrent hash map performance by measuring throughput under different thread-to-core mappings.

### NUMA Detection

```cpp
// common/numa.h
#include <numa.h>

struct NumaTopology {
    int num_nodes;
    int cores_per_node;
    std::vector<std::vector<int>> node_cores;  // node_cores[node] = {core_ids}
};

NumaTopology detect_numa() {
    NumaTopology topo;
    topo.num_nodes = numa_num_configured_nodes();
    // ... populate node_cores from /sys/devices/system/node/
    return topo;
}
```

### Pinning Strategies (Experimental Variable)

| Strategy | Description | Expected Effect |
|----------|-------------|-----------------|
| `compact` | All threads on node 0, consecutive cores | Maximum cache sharing, limited memory bandwidth |
| `spread` | Round-robin across nodes | Higher aggregate memory bandwidth, increased remote access latency |
| `node-local` | Threads pinned to same node as allocation | Baseline NUMA-aware configuration |

### Experimental Matrix Extension

Each (map, scenario, threads, size) combination runs with:
- `pinning=compact` (default)
- `pinning=spread` (if numa_nodes > 1)

This adds NUMA topology as an **independent variable** rather than uncontrolled confound.

### NUMA Metadata in CSV

```
numa_nodes,pinning_strategy,allocation_node
```

## Cache Hierarchy Analysis

### Objective

Distinguish cache-bound vs memory-bound performance characteristics.

### Working Set Size Classification

| Map Size | Working Set | Expected Behavior |
|----------|-------------|-------------------|
| 100K | ~1.6 MB | L3-resident (cache-bound) |
| 1M | ~16 MB | Partial L3, some misses |
| 10M | ~160 MB | Memory-bound |

### Cache-Aware Analysis

The benchmark reports **normalized throughput**:
- `throughput_per_cache_miss`: ops/sec normalized by LLC miss rate (if perf counters available)
- `cache_efficiency`: ratio of L3-resident (100K) to memory-bound (10M) throughput

### Hardware Counter Collection (Optional)

```bash
# Run with perf stat for cache analysis
perf stat -e LLC-load-misses,LLC-loads ./bench-phmap --scenario read_only --threads 8 --mapsize 1000000
```

### Analysis Approach

1. **Cache-bound regime (100K)**: Measures hash computation + lock overhead
2. **Memory-bound regime (10M)**: Measures memory access patterns + prefetching effectiveness
3. **Transition regime (1M)**: Mixed behavior, implementation-dependent

Results should be interpreted with cache hierarchy in mind:
- High throughput at 100K but low at 10M → indicates cache-unfriendly memory access patterns
- Consistent scaling across sizes → indicates cache-oblivious implementation

### Output Format

**Per-trial CSV:**
```
run_id,map_name,map_version,scenario,thread_count,map_size,ops_per_trial,
repeat_index,seed,core_mapping,duration_ns,ops_per_sec,mean_sample_latency_ns,
p50_latency_ns,p90_latency_ns,p95_latency_ns,p99_latency_ns,max_sample_latency_ns,
sampled_ops_count,peak_rss_kb,notes
```

**Latency samples CSV:**
```
op_index,thread_id,latency_ns
```

## Implementation Phases

### Phase 1: Build Infrastructure

**Tasks:**
- [ ] Create root `CMakeLists.txt`
- [ ] Set up `deps/` with FetchContent or submodules
- [ ] Configure optimization flags (`-O3 -march=native -flto`)
- [ ] Verify parallel-hashmap and libcuckoo build correctly

**CMakeLists.txt (root):**
```cmake
cmake_minimum_required(VERSION 3.16)
project(concurrent_hashmap_bench CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Release by default
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Optimization flags
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto -DNDEBUG")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)

# Fetch dependencies
include(FetchContent)

FetchContent_Declare(
    parallel-hashmap
    GIT_REPOSITORY https://github.com/greg7mdp/parallel-hashmap.git
    GIT_TAG        v2.0.0
)

FetchContent_Declare(
    libcuckoo
    GIT_REPOSITORY https://github.com/efficient/libcuckoo.git
    GIT_TAG        master
)

FetchContent_MakeAvailable(parallel-hashmap libcuckoo)

# Add benchmark implementations
add_subdirectory(cpp-impl)
```

### Phase 2: Common Headers

**Tasks:**
- [ ] `common/config.h` - Constants (OPS_PER_TRIAL, SAMPLE_INTERVAL, etc.)
- [ ] `common/prng.h` - xorshift64* implementation
- [ ] `common/timing.h` - clock_gettime wrappers
- [ ] `common/hasher.h` - Custom fast hasher
- [ ] `common/zipf.h` - Zipfian distribution generator
- [ ] `common/worker.h` - Thread worker infrastructure with barriers
- [ ] `common/memory.h` - RSS measurement utilities
- [ ] `common/numa.h` - NUMA topology detection and pinning strategies

### Phase 3: C++ Benchmarks

**Tasks:**
- [ ] `cpp-impl/bench-phmap.cpp`
  - Command-line argument parsing
  - All 7+ scenarios
  - CSV output
  - Memory measurement

- [ ] `cpp-impl/bench-libcuckoo.cpp`
  - Adapt from phmap (different API patterns)
  - Handle `update_fn()` for updates
  - Match output format exactly

**cpp-impl/CMakeLists.txt:**
```cmake
# bench-phmap
add_executable(bench-phmap bench-phmap.cpp)
target_include_directories(bench-phmap PRIVATE
    ${CMAKE_SOURCE_DIR}/common
    ${parallel-hashmap_SOURCE_DIR}
)
target_link_libraries(bench-phmap pthread)

# bench-libcuckoo
add_executable(bench-libcuckoo bench-libcuckoo.cpp)
target_include_directories(bench-libcuckoo PRIVATE
    ${CMAKE_SOURCE_DIR}/common
    ${libcuckoo_SOURCE_DIR}
)
target_link_libraries(bench-libcuckoo pthread)
```

### Phase 4: Rust Benchmark

**Tasks:**
- [ ] Create `rust-impl/Cargo.toml`
- [ ] Implement `prng.rs` - verify sequence matches C++
- [ ] Implement `hasher.rs` - verify hash matches C++
- [ ] Implement `affinity.rs` - thread pinning via libc
- [ ] Implement `scenarios.rs` - all workload scenarios
- [ ] Implement `memory.rs` - RSS measurement utilities
- [ ] Implement `main.rs` - CLI and orchestration

**Cargo.toml:**
```toml
[package]
name = "bench-dashmap"
version = "0.1.0"
edition = "2024"

[dependencies]
dashmap = "6"
libc = "0.2"
clap = { version = "4", features = ["derive"] }

[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
```

### Phase 5: Validation

**Tasks:**
- [ ] Write PRNG verification test (C++ and Rust produce same sequence)
- [ ] Write hash verification test (same inputs → same outputs)
- [ ] Verify CSV output format consistency
- [ ] Run correctness tests for each scenario

**Verification approach:**
```bash
# Generate 1000 PRNG outputs from seed 42
./bench-phmap --verify-prng --seed 42 > cpp_prng.txt
./bench-dashmap --verify-prng --seed 42 > rust_prng.txt
diff cpp_prng.txt rust_prng.txt
```

### Phase 6: Orchestration Scripts

**Tasks:**
- [ ] `scripts/run-experiments.sh`
  - Generate experiment matrix
  - Randomize order (avoid systematic bias)
  - Execute with proper isolation
  - Save metadata JSON

- [ ] `scripts/aggregate-results.py`
  - Read raw CSV files
  - Compute mean, std, 95% CI
  - Output aggregated results

- [ ] `scripts/generate-plots.sh`
  - Invoke gnuplot scripts
  - Generate PNG/PDF outputs

## Experiment Matrix

| Dimension | Values | Count |
|-----------|--------|-------|
| Maps | phmap, libcuckoo, dashmap | 3 |
| Scenarios | 1-7 (with sub-variants) | ~10 |
| Map sizes | 100K, 1M, 10M | 3 |
| Thread counts | 1, 2, 4, 8, 16, 32, N_cores | ~6 |
| Pinning strategies | compact, spread | 2 |
| Repetitions | 40 | 40 |

**Total trials:** 3 × 10 × 3 × 6 × 2 × 40 = **43,200**

**Estimated runtime:** ~2-3 seconds/trial → **24-36 hours**

**Note:** On single-socket systems, pinning strategy dimension collapses to 1, reducing to ~21,600 trials.

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| PRNG sequence mismatch | Invalid comparison | Explicit verification test before benchmarking |
| Hash function variance | Unfair comparison | Integer-only operations, verify outputs match |
| Memory allocator differences | Performance variance | Use jemalloc for both OR document system allocator |
| Thread scheduling noise | High variance | 40 repetitions + isolated machine |
| libcuckoo API differences | Implementation bugs | Careful API adaptation, correctness tests |
| Compiler version differences | Irreproducible | Document exact versions in metadata |

## Success Criteria

- [ ] All three implementations produce identical key sequences for same seed
- [ ] CSV output format matches specification exactly
- [ ] Statistical analysis produces valid 95% CI
- [ ] Plots render correctly with error bars
- [ ] Full experiment suite completes without errors
- [ ] Results are reproducible (re-run yields similar statistics)

## Platform Requirements Checklist

Before running experiments:

- [ ] CPU governor set to `performance`
- [ ] Hyperthreading disabled (or documented)
- [ ] No competing processes running
- [ ] Sufficient disk space for results (~1GB)
- [ ] System metadata captured (CPU, kernel, memory, compiler versions)

## Limitations & Scope

### Scope Boundaries

This benchmark measures **throughput and latency under controlled synthetic workloads**. The following are explicitly out of scope:

| Out of Scope | Rationale |
|--------------|-----------|
| Memory pressure / OOM behavior | Controlled environment, sufficient RAM assumed |
| Long-running stability (>1 hour) | Focus on steady-state performance, not degradation |
| Application-specific workloads | Synthetic workloads enable controlled comparison |

### Methodological Limitations

1. **Cache Hierarchy Dependence**
   - 100K entries (~1.6 MB) fits entirely in L3 cache on most modern CPUs
   - Results at this size primarily reflect cache hit performance
   - Analysis must distinguish cache-bound (100K) from memory-bound (10M) regimes
   - **Mitigation**: Report results by map size category with explicit cache analysis

2. **Synthetic Workload Generalization**
   - Real workloads have complex access patterns not captured by uniform/Zipfian distributions
   - Results apply to workloads with similar statistical properties
   - **Mitigation**: Multiple scenarios (7+) covering diverse access patterns

3. **Platform Specificity**
   - Results are specific to x86_64 Linux with tested CPU microarchitecture
   - ARM, other OSes, or different CPU generations may show different characteristics
   - **Mitigation**: Document exact hardware/software configuration in metadata

4. **Statistical Assumptions**
   - CLT-based 95% CI assumes approximately normal distribution of sample means
   - Valid for throughput (aggregated over 1M ops); latency distributions may be heavy-tailed
   - **Mitigation**: R=40 repetitions provides robust estimation; report full latency CDFs

### Controlled Variables

The following are held constant to enable fair comparison:

| Variable | Value | Notes |
|----------|-------|-------|
| PRNG | xorshift64* | Identical implementation verified |
| Hash function | FxHash-style multiply | Identical constant verified |
| Key/Value types | uint64_t / u64 | 16 bytes per entry |
| Operations per trial | 1,000,000 | Fixed workload size |
| Warm-up operations | 100,000 | Discarded from measurement |
| Memory allocator | System default | Documented in metadata |

### Interpretation Guidelines

- Compare implementations **within** the same (scenario, map_size, thread_count, pinning) configuration
- Cache-bound (100K) and memory-bound (10M) results measure different aspects of implementation quality
- NUMA effects visible by comparing `compact` vs `spread` pinning strategies
- Memory efficiency (bytes/entry) is independent of throughput and should be reported separately
