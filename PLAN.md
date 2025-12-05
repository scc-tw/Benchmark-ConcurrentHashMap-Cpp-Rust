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
│   └── worker.h              # Thread worker infrastructure
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
│       └── affinity.rs       # Thread pinning via libc
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
| Repetitions | 40 | 40 |

**Total trials:** 3 × 10 × 3 × 6 × 40 = **21,600**

**Estimated runtime:** ~2-3 seconds/trial → **12-18 hours**

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
