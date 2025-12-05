# Concurrent HashMap Benchmarks: Rust vs C++

A statistically rigorous performance comparison of three concurrent hash map implementations:

- **DashMap** (Rust)
- **parallel-hashmap** (C++ - greg7mdp/parallel-hashmap)
- **libcuckoo** (C++ - efficient/libcuckoo)

## Objectives

This benchmark framework produces statistically sound performance comparisons using:

- **Central Limit Theorem (CLT)** for confidence intervals on throughput measurements
- **High-precision timing** via `clock_gettime(CLOCK_MONOTONIC_RAW)` (nanosecond resolution)
- **Fair workload design** with identical PRNG sequences, hash functions, and key/value types across implementations
- **Memory efficiency measurement** via RSS tracking and bytes-per-entry metrics
- **NUMA topology** as an experimental variable with multiple pinning strategies

## Methodology

### Statistical Approach

Each experimental configuration is repeated **R = 40** times to enable CLT-based confidence intervals:

- Each trial runs exactly **1,000,000 operations**
- Warm-up phase: **100,000 operations** (discarded)
- Sample mean (x̄) and standard deviation (s) computed across repetitions
- 95% confidence intervals: `x̄ ± 1.96 × (s / √R)`
- Raw per-trial data saved in CSV format for reproducibility

### Fairness Controls

| Variable | Value | Verification |
|----------|-------|--------------|
| PRNG | xorshift64* | Identical sequence for same seed |
| Hash function | `key × 0x517cc1b727220a95` | Integer-only, outputs verified |
| Key/Value types | `uint64_t` / `u64` | 16 bytes per entry |
| Optimizations | `-O3 -march=native -flto` | Local CMake build for C++ |
| Thread pinning | `pthread_setaffinity_np` | Controlled core assignment |

### Implementation Configurations

| Map | Type | Shards | Lock Type |
|-----|------|--------|-----------|
| parallel-hashmap | `parallel_flat_hash_map<..., 4, SpinLock>` | 16 (2^4) | Spinlock (atomic) |
| libcuckoo | `cuckoohash_map` | Variable | Fine-grained spinlock |
| DashMap | `DashMap` | num_cpus×4 | RwLock (spin + park) |

**Note:** `phmap::flat_hash_map` is NOT thread-safe. This benchmark uses `parallel_flat_hash_map` with a custom `SpinLock` (atomic_flag based, no syscalls).

**Lock primitive rationale:**
- Hash map operations have short critical sections (~50-200ns)
- std::mutex involves futex syscalls (~10x overhead)
- All implementations use spin-based locking for short critical sections

**Architectural differences:**
- DashMap uses RwLock (read-read parallelism possible)
- parallel-hashmap uses exclusive spinlock (serializes all access per submap)
- These differences affect read-heavy scenario results

### Timing Infrastructure

- **Timing source**: `clock_gettime(CLOCK_MONOTONIC_RAW, ...)` for NTP-independent measurements
- **Precision**: Nanosecond-level timing
- **Sampling strategy**: Per-operation latencies sampled at 0.1% rate (every 1000th op)
- **Thread coordination**: Pthread barriers for synchronized start across all worker threads

### Workload Scenarios

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

### Map Sizes

| Size | Entries | Working Set | Cache Behavior |
|------|---------|-------------|----------------|
| Small | 100,000 | ~1.6 MB | L3-resident (cache-bound) |
| Medium | 1,000,000 | ~16 MB | Partial L3, some misses |
| Large | 10,000,000 | ~160 MB | Memory-bound |

### Thread Counts

Hardware-aware scaling: `[1, 2, 4, 8, 16, 32, N_physical_cores]`

### NUMA Pinning Strategies

| Strategy | Description | Expected Effect |
|----------|-------------|-----------------|
| `compact` | All threads on node 0, consecutive cores | Maximum cache sharing, limited memory bandwidth |
| `spread` | Round-robin across nodes | Higher aggregate memory bandwidth, increased remote access latency |

NUMA topology is treated as an **experimental variable**, not a confound.

## Experiment Matrix

| Dimension | Values | Count |
|-----------|--------|-------|
| Maps | phmap, libcuckoo, dashmap | 3 |
| Scenarios | 1-7 (with sub-variants) | ~10 |
| Map sizes | 100K, 1M, 10M | 3 |
| Thread counts | 1, 2, 4, 8, 16, 32, N_cores | ~6 |
| Pinning strategies | compact, spread | 2 |
| Repetitions | 40 | 40 |

**Total trials:** 3 × 10 × 3 × 6 × 2 × 40 = **43,200** (multi-socket systems)

**Note:** On single-socket systems, pinning strategy dimension collapses to 1, reducing to ~21,600 trials.

## Platform Requirements

### Hardware Configuration

- **CPU governor**: Set to `performance` mode
- **Hyperthreading**: Disabled (or documented)
- **Workload isolation**: Run benchmarks single-tenant with no competing processes
- **NUMA topology**: Recorded and used as experimental variable

**Required system information to record:**
- CPU model and frequency
- Physical vs logical core count
- NUMA node configuration
- Memory capacity
- Kernel version
- Compiler versions and flags

### Software Dependencies

**C++ implementations:**
- C++17 compiler (GCC/Clang)
- CMake 3.16+
- Pthreads library
- libnuma (optional, for NUMA detection)

**Rust implementation:**
- Rust 1.70+ (stable)
- DashMap 6.x
- libc crate

**Analysis and plotting:**
- Python 3.x with NumPy
- gnuplot 5.0+

### Build Configuration

**C++ (CMake with local dependency build):**
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

**Rust:**
```bash
cd rust-impl
cargo build --release
```

## Usage

### Building

```bash
# C++ implementations (with FetchContent for dependencies)
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)

# Rust implementation
cd rust-impl && cargo build --release
```

### Running Experiments

```bash
# Run full benchmark suite
./scripts/run-experiments.sh

# Run specific scenario
./build/bench-phmap --scenario read_only --threads 8 --mapsize 1000000 --repeats 40 --pinning compact

# Verify PRNG consistency
./build/bench-phmap --verify-prng --seed 42 > cpp_prng.txt
./rust-impl/target/release/bench-dashmap --verify-prng --seed 42 > rust_prng.txt
diff cpp_prng.txt rust_prng.txt
```

### Output Format

**Per-trial CSV:**
```
run_id,map_name,map_version,scenario,thread_count,map_size,ops_per_trial,
repeat_index,seed,core_mapping,duration_ns,ops_per_sec,mean_sample_latency_ns,
p50_latency_ns,p90_latency_ns,p95_latency_ns,p99_latency_ns,max_sample_latency_ns,
sampled_ops_count,peak_rss_kb,current_rss_kb,bytes_per_entry,overhead_ratio,
numa_nodes,pinning_strategy,allocation_node,notes
```

**Latency samples CSV:**
```
op_index,thread_id,latency_ns
```

**System metadata JSON:**
```json
{
  "cpu_model": "...",
  "numa_nodes": 2,
  "cores_per_node": 16,
  "kernel_version": "...",
  "compiler_versions": {...},
  "build_flags": {...}
}
```

## Analysis

### Aggregating Results

```bash
# Compute mean, std dev, and 95% CI from raw trials
python scripts/aggregate-results.py results/raw/*.csv > results/aggregated/summary.csv
```

### Plotting

```bash
# Generate all plots
./scripts/generate-plots.sh

# Individual plots
gnuplot plots/plot-throughput.gnu
gnuplot plots/plot-latency-cdf.gnu
gnuplot plots/plot-scalability.gnu
```

## Results

**[Placeholder - Results will be added after benchmark execution]**

### Throughput vs Thread Count

![Throughput comparison](results/plots/throughput-vs-threads.png)

*Figure: Mean throughput (ops/sec) vs thread count with 95% confidence intervals. Each point represents mean of 40 trials.*

### Latency Distributions

![Latency CDFs](results/plots/latency-cdf.png)

*Figure: Cumulative distribution functions of sampled operation latencies.*

### Scalability Analysis

![Normalized speedup](results/plots/scalability.png)

*Figure: Normalized speedup (throughput at N threads / throughput at 1 thread).*

### Memory Efficiency

**[Placeholder - Memory efficiency analysis]**

| Map Implementation | Small (100K) | Medium (1M) | Large (10M) | Bytes/Entry |
|-------------------|--------------|-------------|-------------|-------------|
| DashMap           | TBD MB       | TBD MB      | TBD MB      | TBD         |
| parallel-hashmap  | TBD MB       | TBD MB      | TBD MB      | TBD         |
| libcuckoo         | TBD MB       | TBD MB      | TBD MB      | TBD         |

*Table: Peak RSS and memory overhead ratio (theoretical minimum = 16 bytes/entry).*

### NUMA Effects

**[Placeholder - NUMA topology analysis]**

*Comparison of compact vs spread pinning strategies across thread counts.*

## Project Structure

```
.
├── BENCHMARK_DESIGN.md       # Detailed methodology and design rationale
├── PLAN.md                   # Implementation plan
├── README.md                 # This file
├── CMakeLists.txt            # Root CMake configuration
│
├── deps/                     # C++ dependencies (fetched by CMake)
│   ├── parallel-hashmap/
│   └── libcuckoo/
│
├── common/                   # Shared C++ headers
│   ├── config.h              # Constants and configuration
│   ├── prng.h                # xorshift64* implementation
│   ├── timing.h              # clock_gettime wrappers
│   ├── hasher.h              # Custom fast hasher
│   ├── spinlock.h            # Lightweight spinlock (atomic_flag)
│   ├── zipf.h                # Zipfian distribution
│   ├── worker.h              # Thread worker infrastructure
│   ├── memory.h              # RSS measurement utilities
│   └── numa.h                # NUMA topology detection
│
├── cpp-impl/                 # C++ benchmark implementations
│   ├── CMakeLists.txt
│   ├── bench-phmap.cpp
│   └── bench-libcuckoo.cpp
│
├── rust-impl/                # Rust benchmark implementation
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       ├── prng.rs
│       ├── hasher.rs
│       ├── scenarios.rs
│       ├── affinity.rs
│       └── memory.rs
│
├── scripts/                  # Automation scripts
│   ├── run-experiments.sh
│   ├── aggregate-results.py
│   └── generate-plots.sh
│
├── plots/                    # Gnuplot scripts
│   ├── plot-throughput.gnu
│   ├── plot-latency-cdf.gnu
│   └── plot-scalability.gnu
│
└── results/                  # Output directory (generated)
    ├── raw/
    ├── aggregated/
    └── plots/
```

## Limitations & Scope

### Scope Boundaries

This benchmark measures **throughput, latency, and memory efficiency under controlled synthetic workloads**.

| Out of Scope | Rationale |
|--------------|-----------|
| Memory pressure / OOM behavior | Controlled environment, sufficient RAM assumed |
| Long-running stability (>1 hour) | Focus on steady-state performance |
| Application-specific workloads | Synthetic workloads enable controlled comparison |

### Methodological Limitations

1. **Cache Hierarchy Dependence**: Results at 100K entries (L3-resident) measure different characteristics than 10M entries (memory-bound)

2. **Synthetic Workload Generalization**: Results apply to workloads with similar statistical properties to the tested scenarios

3. **Platform Specificity**: Results are specific to x86_64 Linux with tested CPU microarchitecture

### Interpretation Guidelines

- Compare implementations **within** the same (scenario, map_size, thread_count, pinning) configuration
- Cache-bound (100K) and memory-bound (10M) results measure different implementation characteristics
- NUMA effects visible by comparing `compact` vs `spread` pinning strategies
- Memory efficiency (bytes/entry) is independent of throughput

## Reproducibility

All artifacts saved for reproducibility:

- Source code and build scripts (git commit hash recorded)
- Exact compiler versions and flags
- Command-line invocations
- Raw per-trial CSV data
- Aggregated statistics
- Gnuplot scripts and generated plots
- System metadata JSON

## References

- [DashMap](https://github.com/xacrimon/dashmap) - Concurrent HashMap for Rust
- [parallel-hashmap](https://github.com/greg7mdp/parallel-hashmap) - Header-only hash maps for C++
- [libcuckoo](https://github.com/efficient/libcuckoo) - Concurrent hash table using cuckoo hashing

## License

[Specify license - TODO]

## Citation

If you use this benchmark framework in academic work, please cite:

```
[Citation format - TODO after publication]
```
