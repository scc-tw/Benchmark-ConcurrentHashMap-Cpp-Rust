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

### Validation

Run validation suite to verify cross-implementation consistency:

```bash
# Run all validations
./scripts/validation/run_all_validations.sh

# Individual validations
./scripts/validation/validate_prng.sh      # PRNG sequence match
./scripts/validation/validate_hash.sh      # Hash function match
./scripts/validation/validate_csv.sh       # CSV format consistency
./scripts/validation/validate_scenarios.sh # All scenarios execute
./scripts/validation/validate_memory.sh    # Memory measurements valid
```

### Running Individual Benchmarks

```bash
# parallel-hashmap benchmark
./build/cpp-impl/bench-phmap --scenario read_only --threads 8 --mapsize 1000000 --repeats 40 --pinning compact

# libcuckoo benchmark
./build/cpp-impl/bench-libcuckoo --scenario read_only --threads 8 --mapsize 1000000 --repeats 40 --pinning compact

# DashMap benchmark
./rust-impl/target/release/bench-dashmap --scenario read_only --threads 8 --mapsize 1000000 --repeats 40 --pinning compact

# Verify PRNG consistency
./build/cpp-impl/bench-phmap --verify-prng --seed 42
./rust-impl/target/release/bench-dashmap --verify-prng --seed 42

# Verify hash consistency
./build/cpp-impl/bench-phmap --verify-hash
./rust-impl/target/release/bench-dashmap --verify-hash
```

### Running Full Experiment Suite

```bash
# Full benchmark (estimated 24-36 hours)
./scripts/run-experiments.sh

# Quick test run (reduced matrix, ~30 minutes)
./scripts/run-experiments.sh --quick

# Dry run (show experiment matrix without executing)
./scripts/run-experiments.sh --dry-run

# Single implementation only
./scripts/run-experiments.sh --single-impl dashmap

# Single scenario only
./scripts/run-experiments.sh --single-scenario read_only

# Resume interrupted run
./scripts/run-experiments.sh --resume

# Full pipeline (validation + experiments + aggregation + plots)
./scripts/run-full-pipeline.sh --quick
```

### Output Format

**Per-trial CSV (27 columns):**
```
run_id,map_name,map_version,scenario,thread_count,map_size,ops_per_trial,
repeat_index,seed,core_mapping,duration_ns,ops_per_sec,mean_sample_latency_ns,
p50_latency_ns,p90_latency_ns,p95_latency_ns,p99_latency_ns,max_sample_latency_ns,
sampled_ops_count,peak_rss_kb,current_rss_kb,bytes_per_entry,overhead_ratio,
numa_nodes,pinning_strategy,allocation_node,notes
```

**System metadata JSON:**
```json
{
  "timestamp": "...",
  "hostname": "...",
  "kernel": "...",
  "cpu_model": "...",
  "cpu_cores": 16,
  "numa_nodes": 1,
  "gcc_version": "...",
  "rustc_version": "...",
  "experiment_config": {...}
}
```

## Analysis

### Aggregating Results

```bash
# Aggregate raw trials into summary statistics
python3 scripts/aggregate-results.py

# With verbose output
python3 scripts/aggregate-results.py -v

# Custom input/output
python3 scripts/aggregate-results.py --input results/raw --output results/aggregated/summary.csv
```

### Quick Analysis

```bash
# Generate summary report
python3 scripts/quick-analysis.py
```

### Plotting

Requires gnuplot 5.0+:

```bash
# Generate all plots
./scripts/generate-plots.sh

# Individual plots with parameters
gnuplot -e "scenario='read_only'; mapsize=1000000; pinning='compact'" plots/plot-throughput.gnu
gnuplot -e "scenario='insert_only'; mapsize=1000000; pinning='compact'" plots/plot-scalability.gnu
gnuplot -e "scenario='read_only'; threads=8; mapsize=1000000; pinning='compact'" plots/plot-latency.gnu
gnuplot -e "threads=1; pinning='compact'" plots/plot-memory.gnu
gnuplot -e "threads=8; mapsize=1000000; pinning='compact'" plots/plot-comparison.gnu
```

## Results

*Generated from 810 configurations with 40 repetitions each (32,400 data points). Full analysis available in `results/analysis/BENCHMARK_REPORT.md`.*

### Executive Summary

#### Performance Winners (16 threads, 1M entries, compact pinning)

| Workload Type | Winner | Throughput |
|---------------|--------|------------|
| **Read-heavy** (read_only, read_majority) | **libcuckoo** | 384M ops/s |
| **Write-heavy** (insert_only, sequential) | **libcuckoo** | 188M ops/s |
| **Mixed workloads** (balanced, zipfian) | **DashMap** | 126M ops/s |

**Win distribution:** libcuckoo: 5 scenarios, DashMap: 4 scenarios

### Scalability Analysis

*Primary finding: libcuckoo achieves the best scaling (up to 8.3x speedup), while parallel-hashmap shows negative scaling under contention.*

#### Speedup (1 → 16 threads, 1M entries)

| Scenario | DashMap | libcuckoo | parallel-hashmap | Best Scaler |
|----------|---------|-----------|------------------|-------------|
| read_only | 3.61x | **6.19x** | 0.42x | libcuckoo |
| read_majority_99 | 3.87x | **8.29x** | 0.40x | libcuckoo |
| read_majority_95 | 3.90x | **8.16x** | 0.62x | libcuckoo |
| insert_only | 2.57x | **6.85x** | 0.33x | libcuckoo |
| balanced | 3.76x | **4.00x** | 0.45x | libcuckoo |
| zipfian | **3.87x** | 1.44x | 1.12x | DashMap |

#### Scaling Efficiency (% of ideal linear scaling at 16 threads)

| Scenario | DashMap | libcuckoo | parallel-hashmap |
|----------|---------|-----------|------------------|
| read_only | 23% | **39%** | 3% |
| read_majority_99 | 24% | **52%** | 3% |
| insert_only | 16% | **43%** | 2% |
| balanced | 24% | **25%** | 3% |

#### Thread Scaling Progression (read_only, 1M entries)

| Threads | DashMap | libcuckoo | parallel-hashmap |
|---------|---------|-----------|------------------|
| 1 | 49.2M | 62.0M | **196.6M** |
| 2 | 61.4M | 75.2M | **192.2M** |
| 4 | 87.6M | **131.2M** | 129.4M |
| 8 | 142.6M | **226.9M** | 124.8M |
| 16 | 177.2M | **383.8M** | 82.9M |

*Note: parallel-hashmap shows excellent single-threaded performance but degrades under contention.*

### Throughput Comparison

#### Peak Throughput (16 threads, 1M entries, compact pinning)

| Scenario | DashMap | libcuckoo | parallel-hashmap | Winner |
|----------|---------|-----------|------------------|--------|
| read_only | 177.2M | **383.8M** | 82.9M | libcuckoo |
| read_majority_99 | 173.0M | **249.9M** | 68.9M | libcuckoo |
| read_majority_95 | 170.6M | **247.6M** | 79.6M | libcuckoo |
| insert_only | 121.4M | **188.1M** | 14.2M | libcuckoo |
| balanced | **125.5M** | 45.4M | 24.3M | DashMap |
| zipfian | **116.5M** | 31.1M | 38.4M | DashMap |
| resize_stress | **96.4M** | 30.0M | 2.4M | DashMap |
| random_keys | **130.3M** | 80.8M | 13.6M | DashMap |

### Memory Efficiency

*Theoretical minimum: 16 bytes (8-byte key + 8-byte value)*

| Implementation | 100K (bytes/entry) | 1M (bytes/entry) | 10M (bytes/entry) | Avg Overhead |
|----------------|-------------------|------------------|-------------------|--------------|
| DashMap | 42.0 | 38.8 | 288.4 | 7.69x |
| libcuckoo | 50.4 | **36.0** | 319.1 | 8.45x |
| parallel-hashmap | 47.4 | 39.6 | 289.1 | 7.84x |

| Implementation | 100K (RSS KB) | 1M (RSS KB) | 10M (RSS KB) |
|----------------|---------------|-------------|--------------|
| DashMap | 41,004 | 38,148 | 281,832 |
| libcuckoo | 49,208 | **35,108** | 311,592 |
| parallel-hashmap | 46,256 | 38,652 | 282,368 |

### Latency Analysis

#### Latency Percentiles (read_only, 8 threads, 1M entries)

| Implementation | Mean (ns) | p50 (ns) | p90 (ns) | p95 (ns) | p99 (ns) |
|----------------|-----------|----------|----------|----------|----------|
| DashMap | 112 | 101 | 158 | 182 | 256 |
| libcuckoo | **71** | **71** | **83** | **87** | **114** |
| parallel-hashmap | 84 | 64 | 149 | 189 | 324 |

*libcuckoo achieves the lowest and most consistent latency.*

### NUMA Effects

#### Compact vs Spread Pinning Impact (16 threads, 1M entries)

*Positive delta = compact is faster; Negative delta = spread is faster*

| Scenario | DashMap | libcuckoo | parallel-hashmap |
|----------|---------|-----------|------------------|
| read_only | -0.5% | -1.1% | -2.9% |
| balanced | **+6.6%** | +1.7% | -1.5% |
| zipfian | +1.0% | +0.3% | **-21.2%** |

**Key NUMA observations:**
- parallel-hashmap shows high NUMA sensitivity (up to 21% difference)
- DashMap benefits from compact pinning on balanced workloads (+6.6%)
- libcuckoo is NUMA-agnostic (<2% difference across all scenarios)

### Recommendations

| Use Case | Recommendation | Rationale |
|----------|----------------|-----------|
| Read-heavy workloads | **libcuckoo** | 2-4x higher throughput, lowest latency |
| Mixed read/write | **DashMap** | Best balanced performance, 126M ops/s |
| Memory-constrained | **libcuckoo** | Lowest bytes/entry at 1M scale |
| Rust projects | **DashMap** | Native Rust, excellent mixed-workload performance |
| Low contention | **parallel-hashmap** | Best single-threaded (196M ops/s) |

## Project Structure

```
.
├── README.md                 # This file
├── CMakeLists.txt            # Root CMake configuration
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
│   ├── bench-phmap.cpp       # parallel-hashmap benchmark
│   └── bench-libcuckoo.cpp   # libcuckoo benchmark
│
├── rust-impl/                # Rust benchmark implementation
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs           # Entry point and CLI
│       ├── prng.rs           # xorshift64* implementation
│       ├── hasher.rs         # Custom fast hasher
│       ├── scenarios.rs      # Benchmark scenarios
│       ├── affinity.rs       # Thread pinning
│       ├── memory.rs         # RSS measurement
│       └── numa.rs           # NUMA topology detection
│
├── scripts/                  # Automation scripts
│   ├── run-experiments.sh    # Experiment orchestration
│   ├── run-full-pipeline.sh  # End-to-end automation
│   ├── aggregate-results.py  # Statistical aggregation
│   ├── generate-plots.sh     # Plot generation wrapper
│   ├── quick-analysis.py     # Summary report generator
│   └── validation/           # Cross-implementation validation
│       ├── run_all_validations.sh
│       ├── validate_prng.sh
│       ├── validate_hash.sh
│       ├── validate_csv.sh
│       ├── validate_scenarios.sh
│       └── validate_memory.sh
│
├── plots/                    # Gnuplot scripts
│   ├── plot-throughput.gnu   # Throughput vs thread count
│   ├── plot-scalability.gnu  # Normalized speedup
│   ├── plot-latency.gnu      # Latency percentiles
│   ├── plot-memory.gnu       # Memory efficiency
│   └── plot-comparison.gnu   # Multi-scenario comparison
│
├── build/                    # Build output (generated)
│   └── cpp-impl/
│       ├── bench-phmap
│       └── bench-libcuckoo
│
└── results/                  # Benchmark output (generated)
    ├── raw/                  # Per-trial CSV files
    ├── aggregated/           # Summary statistics
    ├── plots/                # Generated PNG plots
    ├── logs/                 # Execution logs
    └── system_metadata.json  # System configuration
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
