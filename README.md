# Concurrent HashMap Benchmarks: Rust vs C++

A statistically rigorous performance comparison of three high-performance concurrent hash map implementations:

- **DashMap** (Rust)
- **parallel-hashmap** (C++ - greg7mdp/parallel-hashmap)
- **libcuckoo** (C++ - efficient/libcuckoo)

## Objectives

This benchmark framework produces statistically sound performance comparisons using:

- **Central Limit Theorem (CLT)** for confidence intervals on throughput measurements
- **High-precision timing** via `clock_gettime(CLOCK_MONOTONIC_RAW)` (nanosecond resolution)
- **Fair workload design** with identical PRNG sequences, hash functions, and key/value types across implementations
- **Publication-quality plots** using gnuplot with error bars and latency distributions

## Methodology

### Statistical Approach

Each experimental configuration is repeated **R ≥ 30** times (recommended R = 40) to enable CLT-based confidence intervals:

- Each trial runs exactly **1,000,000 operations**
- Sample mean (x̄) and standard deviation (s) computed across repetitions
- 95% confidence intervals: `x̄ ± 1.96 × (s / √R)`
- Raw per-trial data saved in CSV format for reproducibility

### Fairness Controls

To ensure apples-to-apples comparison:

- **Identical PRNG**: xorshift64* implementation in both Rust and C++ with same seed
- **Same hash function**: Consistent lightweight hash (identity mix or custom hasher hook)
- **Same key/value types**: `uint64_t` (C++) and `u64` (Rust)
- **Equivalent optimizations**: `-O3 -march=native -flto` for C++, release mode for Rust
- **Thread pinning**: `pthread_setaffinity_np` used for controlled core assignment

### Timing Infrastructure

- **Timing source**: `clock_gettime(CLOCK_MONOTONIC_RAW, ...)` for NTP-independent measurements
- **Precision**: Nanosecond-level timing with minimal syscall overhead
- **Sampling strategy**: Per-operation latencies sampled at ~0.1% rate (every 1000th op) to avoid measurement distortion
- **Thread coordination**: Pthread barriers for synchronized start across all worker threads

### Workload Scenarios

1. **Insert-only (100% writes)** - Measures insertion path, allocation, and resizing behavior
2. **Read-only (100% reads)** - Pre-populated map with uniform random key lookups
3. **Read-majority** - 99%/1% and 95%/5% read/write mixes (cache-like workloads)
4. **Balanced (50/50)** - Equal read and write pressure with growing key space
5. **Hotspot (Zipfian)** - Skewed access patterns (s=1.0 or 1.2) for contention analysis
6. **Resizing stress** - Small initial capacity with many inserts to force rehashing
7. **Sequential vs random keys** - Locality and caching impact evaluation

### Map Sizes

- **Small**: 100,000 entries
- **Medium**: 1,000,000 entries
- **Large**: 10,000,000 entries

### Thread Counts

Hardware-aware scaling: `[1, 2, 4, 8, 16, 32, N_physical_cores]`

Thread counts selected to expose scaling characteristics and potential oversubscription effects.

## Platform Requirements

### Hardware Configuration

- **CPU**: Disable hyperthreading (or test both physical/logical core configurations)
- **CPU governor**: Set to `performance` mode
- **Thread affinity**: Pin threads to specific cores to avoid scheduler migration
- **Workload isolation**: Run benchmarks single-tenant with no competing processes
- **NUMA awareness**: Record topology and consider compact vs spread thread placement strategies

**Required system information to record:**
- CPU model and frequency
- Physical vs logical core count
- NUMA topology
- Memory capacity
- Kernel version
- Compiler versions and flags

### Software Dependencies

**C++ implementations:**
- C++17 or later compiler (GCC/Clang recommended)
- Pthreads library
- [parallel-hashmap](https://github.com/greg7mdp/parallel-hashmap)
- [libcuckoo](https://github.com/efficient/libcuckoo)

**Rust implementation:**
- Rust 1.70+ (or latest stable)
- [DashMap](https://github.com/xacrimon/dashmap)

**Analysis and plotting:**
- gnuplot 5.0+
- Standard Unix utilities (`awk`, `time`)

### Build Configuration

**C++ flags:**
```bash
-O3 -march=native -flto -pthread
```

**Rust flags:**
```bash
cargo build --release
RUSTFLAGS="-C target-cpu=native"
```

## Usage

### Building

```bash
# C++ implementations
make cpp-benchmarks  # TODO: Makefile/CMakeLists.txt

# Rust implementation
cd rust-bench && cargo build --release
```

### Running Experiments

```bash
# Run full benchmark suite
./run-experiments.sh

# Run specific scenario
./bench-phmap --scenario read_only --threads 8 --mapsize 1000000 --repeats 40

# Custom configuration
./bench-dashmap --scenario balanced --threads 16 --mapsize 10000000 --repeats 40 --seed 42
```

### Output Format

**Per-trial CSV** (`results/<map>-<scenario>-<threads>-<mapsize>.csv`):
```
run_id,map_name,map_version,scenario,thread_count,map_size,ops_per_trial,repeat_index,
seed,core_mapping,duration_ns,ops_per_sec,mean_sample_latency_ns,median_sample_latency_ns,
p50_latency_ns,p90_latency_ns,p95_latency_ns,p99_latency_ns,max_sample_latency_ns,
sampled_ops_count,peak_rss_kb,notes
```

**Latency samples** (`results/<map>-<scenario>-latencies-<repeat>.csv`):
```
op_index,thread_id,latency_ns
```

**System metadata** (`results/metadata.json`):
```json
{
  "cpu_model": "...",
  "kernel_version": "...",
  "compiler_versions": {...},
  "build_flags": {...}
}
```

## Analysis

### Aggregating Results

```bash
# Compute mean, std dev, and 95% CI from raw trials
./scripts/aggregate-results.py results/*.csv > agg_results.csv
```

### Plotting

```bash
# Generate throughput vs threads plots
gnuplot plot-throughput.gnu

# Generate latency CDF plots
gnuplot plot-latency-cdf.gnu
```

## Results

**[Placeholder - Results will be added after benchmark execution]**

### Throughput vs Thread Count

![Throughput comparison](plots/throughput-vs-threads.png)

*Figure: Mean throughput (ops/sec) vs thread count with 95% confidence intervals. Each point represents mean of 40 trials.*

### Latency Distributions

![Latency CDFs](plots/latency-cdf.png)

*Figure: Cumulative distribution functions of sampled operation latencies showing p50-p99 percentiles.*

### Scalability Analysis

![Normalized speedup](plots/scalability.png)

*Figure: Normalized speedup (throughput at N threads / throughput at 1 thread) showing parallel efficiency.*

### Memory Usage

**[Placeholder - Memory usage analysis]**

| Map Implementation | Small (100K) | Medium (1M) | Large (10M) |
|-------------------|--------------|-------------|-------------|
| DashMap           | TBD          | TBD         | TBD         |
| parallel-hashmap  | TBD          | TBD         | TBD         |
| libcuckoo         | TBD          | TBD         | TBD         |

*Table: Peak resident set size (RSS) in MB for different map sizes.*

## Implementation Notes

### Avoiding Common Pitfalls

1. **Latency measurement overhead**: Sample latencies at low rate (~0.1%) to avoid distorting throughput
2. **Hash function variance**: Use identical custom hasher across implementations
3. **Allocator differences**: Consider using same allocator (e.g., jemalloc) for both C++ and Rust
4. **Default tuning**: DashMap shard count may need adjustment to match C++ map characteristics
5. **Warm-up phase**: Perform warm-up operations (100K ops) before measurement to populate caches

### Thread Pinning Strategy

Two pinning approaches tested:

- **Compact**: Consecutive cores on same socket (good cache locality)
- **Spread**: Distribute across sockets (good memory bandwidth)

Core affinity set via `pthread_setaffinity_np()` in both C++ and Rust (via libc FFI).

## Reproducibility

All artifacts saved for reproducibility:

- Source code and build scripts (git commit hash recorded)
- Exact compiler versions and flags
- Command-line invocations
- Raw per-trial CSV data
- Aggregated statistics
- Gnuplot scripts and generated plots
- System metadata JSON

## Project Structure

```
.
├── BENCHMARK_DESIGN.md       # Detailed methodology and design rationale
├── README.md                 # This file
├── bench_stub.c              # C/pthreads skeleton with timing and affinity
├── csv_schema.txt            # CSV format specification
├── plot-throughput.gnu       # Gnuplot script for throughput plots
├── cpp-impl/                 # C++ benchmark implementations (TODO)
│   ├── bench-phmap.cpp
│   └── bench-libcuckoo.cpp
├── rust-impl/                # Rust benchmark implementation (TODO)
│   └── src/
│       └── main.rs
├── scripts/                  # Analysis and automation scripts (TODO)
│   ├── aggregate-results.py
│   └── run-experiments.sh
└── results/                  # Output directory (generated)
    ├── raw/
    ├── aggregated/
    └── plots/
```

## References

- [DashMap](https://github.com/xacrimon/dashmap) - Fast concurrent HashMap for Rust
- [parallel-hashmap](https://github.com/greg7mdp/parallel-hashmap) - Family of header-only, fast hash maps
- [libcuckoo](https://github.com/efficient/libcuckoo) - High-performance concurrent hash table

## License

[Specify license - TODO]

## Citation

If you use this benchmark framework in academic work, please cite:

```
[Citation format - TODO after publication]
```

## Contributing

[Contributing guidelines - TODO]

## Contact

[Contact information - TODO]
