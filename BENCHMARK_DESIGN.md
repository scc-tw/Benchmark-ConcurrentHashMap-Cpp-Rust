# Benchmark design: DashMap (Rust) vs parallel-hashmap (C++) vs libcuckoo (C++)

Goal
- Compare real-world performance of three concurrent hash maps:
  - DashMap (Rust)
  - greg7mdp/parallel-hashmap (C++)
  - efficient/libcuckoo (C++)
- Produce statistically sound conclusions (use CLT for confidence intervals), save raw data, and produce publication-quality plots (gnuplot).
- Use high-resolution timing via clock_gettime (not std::chrono), use pthreads for C++ threads and pthread affinity APIs, and ensure experiments are fair (same RNG, hash, key/value types, identical workloads).

Top-level decisions (rationale)
- Run each trial as a fixed number of operations: 1_000_000 (1M). Each run produces one trial sample.
- Repeat each trial R times (R >= 30, recommend R = 40) to permit CLT-based confidence intervals on sample mean.
- Use separate binaries per language (no FFI).
- Use identical PRNG/seed and identical hash function semantics across implementations where possible (or a fast custom hasher implemented in both).
- Use pthreads for C/C++ implementations and pin threads with pthread_setaffinity_np.
- Use CLOCK_MONOTONIC_RAW via clock_gettime for timing (nanosecond precision).
- Record both throughput and sampled per-operation latencies (sample uniformly at a tiny fraction to avoid measurement-induced distortion).
- Save raw per-trial data in CSV; include metadata per run.
- Provide gnuplot scripts to plot: mean throughput vs threads with error bars (95% CI), latency distributions (CDFs), and memory usage.

Hardware and environment
- Run on an isolated benchmark machine:
  - Disable hyperthreading or record physical cores vs logical cores and run both experiments.
  - Set CPU governor to "performance".
  - Pin processes and threads to CPU cores; avoid OS scheduler movement.
  - Run one benchmark at a time; ensure no other heavy processes.
  - Record CPU model, frequency, NUMA topology, memory size, kernel version.
- Use the same compiler options across C++ builds (e.g., -O3 -march=native -flto if appropriate) and supply Rust with equivalent optimizations (release build). Record exact compiler and flags.

Workload parameters (constants)
- Key type: uint64_t (or u64), identity-mapped keys (to avoid slow string hashing).
- Value type: uint64_t.
- Operations per trial: OPS_PER_TRIAL = 1_000_000.
- Repetitions per combination: REPEATS = 40 (≥30).
- PRNG: implement same small, fast PRNG (e.g., xorshift64* or PCG64) in both Rust and C++ and use identical seed per trial.
- Hash: implement a lightweight consistent hash (e.g., identity mix or wyhash/fxhash) in both languages; or use maps' custom hasher hooks to install same hasher so that you're measuring map behavior, not different hash functions.
- Sampling ratio for operation latency: SAMPLE_RATE = min(0.001, 1000/OPS_PER_TRIAL) — e.g., sample ~1000 operation latencies per trial (use deterministic sampling: sample every k = OPS_PER_TRIAL / 1000 operations).
- Map sizes:
  - Small: 100k (100_000)
  - Medium: 1M (1_000_000)
  - Large: 10M (10_000_000)
- Thread counts: hardware-aware list: [1, 2, 4, 8, 16, 32, Nphys] (stop at 2 × physical core count for oversubscription experiments). For each machine, derive the core list from /proc/cpuinfo and choose a set of thread counts that expose scaling.

Scenarios (each scenario is a workload profile; each run = OPS_PER_TRIAL operations total, divided across threads)
1. Insert-only (100% writes)
   - Start: empty map.
   - Keys: unique monotonic keys generated per-thread to avoid key collisions (e.g., base + thread_id*OPS_PER_THREAD + op_index) OR random keys if you want contention.
   - Purpose: measure insertion path, allocation/resizing impact, and write scalability.

2. Read-only (100% reads)
   - Start: pre-populate map with M items (M is map_size parameter).
   - Each operation: lookup key chosen uniformly from [0, M-1].
   - Purpose: read path throughput & read-only scaling.

3. Read-majority with occasional writes (R >> W)
   - Several mixes: 99% read / 1% write, 95% read / 5% write.
   - Start: pre-populate map with M items.
   - Keys drawn from same range; writes do either update existing keys or insert new keys (define policy).
   - Purpose: typical cache-like workloads.

4. Balanced (50% read / 50% write)
   - Start: pre-populate map with M items.
   - Writes insert new keys in extended range (e.g., [0..2*M)) to exercise growth and pressure.

5. Hotspot (Zipfian) reads, with writes to hotspot
   - Pre-populate with M items.
   - Read keys drawn from a Zipf distribution (skew parameter s = 1.0 or 1.2). Writes update hotspot keys.
   - Purpose: measure contention on small hot set and evaluate locking or per-bucket behavior.

6. Resizing stress: repeated inserts with small initial capacity
   - Start map with small capacity (e.g., capacity = 1024) and perform many inserts to force repeated rehash/resizing.
   - Purpose: measure resizing strategies.

7. Mixed key distribution: sequential vs random keys
   - Run variations where inserts use sequential keys vs totally random keys (impact on locality and caching).

Thread-placement and affinity policy
- Use pthreads and pthread_setaffinity_np. Avoid std::thread for C++ portion.
- Strategy:
  - Build an explicit core list from /sys/devices/system/cpu/cpu*/topology or /proc/cpuinfo.
  - Two pinning strategies to test:
    - Compact packing: threads occupy consecutive cores on the same socket (good locality).
    - Spread packing: threads spread across sockets (good for bandwidth-limited workloads).
- For each thread count t:
  - Determine core set = first t physical cores (or apply strategy chosen).
  - For oversubscription runs, map threads to logical sibling cores as needed, and record mapping.
- Also pin the main thread and any helper threads (e.g., I/O) to distinct cores.

Timing with clock_gettime (high-precision)
- Use clock_gettime(CLOCK_MONOTONIC_RAW, ...) for timing to avoid NTP adjustments. Use CLOCK_MONOTONIC if RAW not available.
- Measure:
  - Wall-clock duration of the whole trial: start_ts before first operation and end_ts after last operation.
  - Optional: per-thread micro-batches timing (e.g., time batches of 1024 ops) to reduce syscall overhead.
  - For sampled per-operation latencies: record start and end timestamps per sampled operation via clock_gettime; compute nanoseconds as:
    - ns = (end.tv_sec - start.tv_sec) * 1_000_000_000LL + (end.tv_nsec - start.tv_nsec).
- Example timing pattern: each thread runs its share of OPS_PER_TRIAL / num_threads ops.
  - Get t0 = clock_gettime()
  - Loop for n ops:
    - generate key
    - occasionally (sampling) t_op0 = clock_gettime()
    - perform operation
    - if sampled: t_op1 = clock_gettime(); record delta
  - At finish get t1 = clock_gettime(); record duration.

Pthreads implementation notes (C/C++):
- Create worker thread struct containing:
  - thread_id, core_id to pin to, rng state, pointers to map, start/stop synchronization primitives.
- Use pthread_barrier_t or two-phase barrier to synchronize start across threads:
  - Main thread constructs map (pre-fill if needed), sets up per-thread data, then barrier_wait().
  - After barrier, each thread starts and immediately calls clock_gettime for its local start (or main thread provides a shared start timestamp after barrier).
- Use memory fences where necessary if map requires explicit quiescing for pre-population.

Ensuring fairness between languages
- Use same key/value sizes and identical PRNG sequences (implement same PRNG in each).
- Use same hasher: either implement a fast mixing function in both or configure map libraries to use a custom hasher that calls an identical mixing routine.
- Pre-size maps with with_capacity / reserve to avoid differing cost of initial growth unless the scenario intentionally measures resizing.
- Use same workload parameters and seeds across runs.

Data to record (raw)
- Save one CSV file per experimental batch. Name pattern:
  results/<experiment-name>-<map>-<scenario>-<numthreads>-<mapsize>.csv
- CSV header (columns):
  run_id, map_name, map_version, scenario, thread_count, map_size, ops_per_trial, repeat_index, seed, core_mapping, duration_ns, ops_per_sec, mean_sample_latency_ns, median_sample_latency_ns, p50_latency_ns, p90_latency_ns, p95_latency_ns, p99_latency_ns, max_sample_latency_ns, sampled_ops_count, peak_rss_kb, notes
- Additional raw artifacts:
  - latencies per sampled operation saved separately as: results/<...>-latencies-<repeat>.csv with columns: op_index, thread_id, latency_ns.
  - System metadata JSON: cpu info, kernel, compiler versions, build flags.

Statistical analysis (CLT usage)
- For each (map, scenario, thread_count, mapsize) combination:
  - We have REPEATS independent trial samples (duration_ns or ops_per_sec).
  - Compute sample mean (x̄) and sample standard deviation (s).
  - By CLT, for R ≥ 30, x̄ ≈ Normal(mean, s/√R). Compute 95% CI using z = 1.96:
    - CI95 = x̄ ± 1.96 * s / sqrt(R).
  - Also compute standard error (SE = s / sqrt(R)).
  - Report mean ± CI95 and include s and R in plots / captions.
- For latency distributions, aggregate sampled latencies across repeats (or compute distribution per repeat and plot median CDFs with bands).
- If distributions are heavy-tailed, show medians and percentile bands rather than only mean.

Number of repeats (R)
- Use R = 40 by default to be conservative; R = 30 is minimum for CLT-based inference. The higher the better for tight CI.

Warm-up and measurement hygiene
- For each trial:
  - Warm-up stage: perform warmup_ops (e.g., 100k operations) and discard results to fill caches and JIT caches (if any).
  - For maps with lazy allocation, warm-up ensures buckets are allocated similarly across implementations.
  - After warm-up, synchronize and start measurement.
- Randomize the order of experiments to avoid systematic bias (e.g., alternate map implementations between repeats).
- Clear OS caches between runs if possible (careful: echo 3 > /proc/sys/vm/drop_caches requires root and affects other workloads). Instead, plan randomized order and include baseline warm-up.

Memory usage
- Capture peak resident set size via /usr/bin/time -v or read from /proc/<pid>/status at end.
- Save peak RSS in KB in the CSV.

Plotting with gnuplot
- Data: aggregated CSV containing for each combination the mean ops/sec and CI95.
- Primary plot: Throughput (ops/sec) vs thread_count, one curve per map, with error bars for CI95.
  - x-axis: thread_count (linear); y-axis: ops/sec (linear or log depending on range).
  - Use distinct colors and point styles.
- Secondary plots:
  - Latency CDFs: plot median CDF and shaded region for p50–p99.
  - Throughput vs map_size for fixed thread count.
  - Scalability plot: normalized speedup (ops/sec at t threads / ops/sec at 1 thread).
- Example gnuplot commands (script saved as `plot-throughput.gnu`):
  - read aggregated data file `agg_results.csv` with columns: map,scenario,thread_count,mean_ops,ci95
  - plot mean with errorbars and lines.

Saving raw data & reproducibility
- Save all artifacts:
  - source code and build scripts (commit hash)
  - binaries
  - command-line invocation string
  - raw CSVs per run and aggregated CSVs
  - gnuplot scripts and generated images
  - environment metadata JSON
- Publish as a small reproducibility package (tarball with README) or a Git repo.

Deliverables I would prepare for implementation (suggested files)
- BENCHMARK_DESIGN.md (this file)
- bench_stub.c (pthreads timing and affinity pattern)
- bench_rust_stub.rs (Rust skeleton showing PRNG and sampling)
- plot-throughput.gnu (gnuplot)
- csv_schema.txt (schema description)
- run-experiments.sh (driver script to iterate combinations, randomize order, save CSVs)

Example calculations for CLT (worked example)
- Suppose R = 40 samples for a combination with sample mean x̄ = 120M ops/s and sample standard deviation s = 6M.
- SE = s / sqrt(R) = 6M / sqrt(40) ≈ 948683
- CI95 half-width = 1.96 * SE ≈ 1.86M
- Report: 120.0 ± 1.86 M ops/s (95% CI).

Notes about pitfalls and how to avoid them
- Measuring latencies per operation with clock_gettime inside the hot path can distort throughput; use sampling (every k operations) to collect latency distributions without large overhead.
- Different default hashers will produce different CPU costs; enforce same hasher or implement the hash step in workload generation to produce pre-hashed keys (if libraries accept pre-hashed insertion).
- Memory allocator differences can matter. If you suspect allocator variance, run experiments with the same allocator (e.g., jemalloc) configured for both C++ and Rust binaries.
- For Rust, DashMap defaults and sharding characteristics may need tuning (number of shards) to match the semantics of the C++ maps.

What I will produce next if you want code
- A small pthread-based C++ benchmark skeleton that:
  - parses command-line scenario parameters
  - pins threads with pthread_setaffinity_np
  - uses clock_gettime(CLOCK_MONOTONIC_RAW)
  - implements the common PRNG and sampling
  - writes per-trial CSV
- Equivalent Rust harness (uses dashmap) using the same PRNG and sampling; uses libc pthread affinity via pthread_setaffinity_np through libc crate for pinning.
- gnuplot scripts to plot results and generate PNG/PDF.

If you want, I can now produce:
- The C/C++ pthread skeleton (with clock_gettime and affinity).
- The Rust harness skeleton (with PRNG and sampling).
- The gnuplot scripts and example CSV headers.
Pick which code skeletons you want first; I'll produce them next.