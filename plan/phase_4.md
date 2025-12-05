# Phase 4: Rust Benchmark

## Objective

Implement the Rust benchmark (`bench-dashmap`) using DashMap, with identical PRNG, hasher, scenarios, and CSV output format to ensure fair comparison with C++ implementations.

## Prerequisites

- Phase 1-3 complete (C++ benchmarks working)
- Rust 1.70+ (stable)
- PRNG and hash verification outputs from C++ for comparison

## Architecture

```
rust-impl/
├── Cargo.toml
├── .cargo/
│   └── config.toml          # target-cpu=native
└── src/
    ├── main.rs              # CLI and orchestration
    ├── prng.rs              # xorshift64* (must match C++)
    ├── hasher.rs            # FastHasher (must match C++)
    ├── scenarios.rs         # All workload implementations
    ├── affinity.rs          # Thread pinning via libc
    ├── memory.rs            # RSS measurement
    └── numa.rs              # NUMA topology detection
```

## Steps

---

### Step 4.1: Create rust-impl Directory Structure

**Tasks:**
- [ ] Create rust-impl directory
- [ ] Create src subdirectory
- [ ] Create .cargo subdirectory

**Commands:**
```bash
mkdir -p rust-impl/src
mkdir -p rust-impl/.cargo
```

---

### Step 4.2: Create Cargo.toml

**File:** `rust-impl/Cargo.toml`

**Tasks:**
- [ ] Define package metadata
- [ ] Add dependencies: dashmap, libc, clap
- [ ] Configure release profile for maximum optimization

**Implementation:**
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

---

### Step 4.3: Create .cargo/config.toml

**File:** `rust-impl/.cargo/config.toml`

**Tasks:**
- [ ] Set target-cpu=native for architecture-specific optimizations

**Implementation:**
```toml
[build]
rustflags = ["-C", "target-cpu=native"]
```

---

### Step 4.4: Implement prng.rs

**File:** `rust-impl/src/prng.rs`

**Purpose:** xorshift64* PRNG - MUST produce identical sequence to C++.

**Tasks:**
- [ ] Implement xorshift64star() function
- [ ] Use exact bit shifts: 12, 25, 27
- [ ] Use multiplier 0x2545F4914F6CDD1Du64
- [ ] Implement rand_range() helper

**Implementation:**
```rust
//! xorshift64* PRNG implementation
//! CRITICAL: Must produce identical sequence to C++ implementation

/// xorshift64* PRNG
/// Reference: https://en.wikipedia.org/wiki/Xorshift#xorshift*
#[inline]
pub fn xorshift64star(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545F4914F6CDD1Du64)
}

/// Generate random number in range [0, max)
#[inline]
pub fn rand_range(state: &mut u64, max: u64) -> u64 {
    xorshift64star(state) % max
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prng_deterministic() {
        let mut state = 42u64;
        let v1 = xorshift64star(&mut state);

        let mut state2 = 42u64;
        let v2 = xorshift64star(&mut state2);

        assert_eq!(v1, v2);
    }
}
```

---

### Step 4.5: Implement hasher.rs

**File:** `rust-impl/src/hasher.rs`

**Purpose:** Custom fast hasher - MUST produce identical hashes to C++.

**Tasks:**
- [ ] Implement FastHasher struct
- [ ] Implement Hasher trait
- [ ] Use multiplier 0x517cc1b727220a95u64
- [ ] Implement BuildHasher for DashMap integration

**Implementation:**
```rust
//! Fast hash function for u64 keys
//! CRITICAL: Must produce identical hashes to C++ implementation

use std::hash::{BuildHasher, Hasher};

/// Fast hasher using FxHash-style multiplication
#[derive(Default, Clone)]
pub struct FastHasher {
    hash: u64,
}

impl Hasher for FastHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        // For u64 keys, this will be called via write_u64
        for &byte in bytes {
            self.hash = self.hash.wrapping_mul(0x517cc1b727220a95u64)
                .wrapping_add(byte as u64);
        }
    }

    #[inline]
    fn write_u64(&mut self, key: u64) {
        self.hash = key.wrapping_mul(0x517cc1b727220a95u64);
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

/// BuildHasher implementation for use with DashMap
#[derive(Default, Clone)]
pub struct BuildFastHasher;

impl BuildHasher for BuildFastHasher {
    type Hasher = FastHasher;

    #[inline]
    fn build_hasher(&self) -> FastHasher {
        FastHasher::default()
    }
}

/// Standalone hash function for verification
#[inline]
pub fn hash_u64(key: u64) -> u64 {
    key.wrapping_mul(0x517cc1b727220a95u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_deterministic() {
        assert_eq!(hash_u64(0), 0);
        assert_eq!(hash_u64(1), 0x517cc1b727220a95u64);
        assert_eq!(hash_u64(42), 42u64.wrapping_mul(0x517cc1b727220a95u64));
    }
}
```

---

### Step 4.6: Implement affinity.rs

**File:** `rust-impl/src/affinity.rs`

**Purpose:** Thread pinning via libc FFI.

**Tasks:**
- [ ] Implement pin_thread() using pthread_setaffinity_np
- [ ] Handle errors gracefully

**Implementation:**
```rust
//! Thread affinity (CPU pinning) via libc

use libc::{cpu_set_t, pthread_self, pthread_setaffinity_np, CPU_SET, CPU_ZERO};
use std::mem;

/// Pin current thread to specific CPU core
pub fn pin_thread(core_id: usize) -> Result<(), String> {
    unsafe {
        let mut cpuset: cpu_set_t = mem::zeroed();
        CPU_ZERO(&mut cpuset);
        CPU_SET(core_id, &mut cpuset);

        let result = pthread_setaffinity_np(
            pthread_self(),
            mem::size_of::<cpu_set_t>(),
            &cpuset,
        );

        if result == 0 {
            Ok(())
        } else {
            Err(format!("Failed to pin thread to core {}: error {}", core_id, result))
        }
    }
}
```

---

### Step 4.7: Implement memory.rs

**File:** `rust-impl/src/memory.rs`

**Purpose:** RSS measurement from /proc/self/status.

**Tasks:**
- [ ] Implement get_peak_rss_kb() reading VmHWM
- [ ] Implement get_current_rss_kb() reading VmRSS
- [ ] Implement bytes_per_entry() and overhead_ratio()

**Implementation:**
```rust
//! Memory measurement utilities

use std::fs;

/// Get peak resident set size in KB (VmHWM = High Water Mark)
pub fn get_peak_rss_kb() -> i64 {
    read_proc_status("VmHWM:")
}

/// Get current resident set size in KB
pub fn get_current_rss_kb() -> i64 {
    read_proc_status("VmRSS:")
}

fn read_proc_status(field: &str) -> i64 {
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|content| {
            content
                .lines()
                .find(|line| line.starts_with(field))
                .and_then(|line| {
                    line.split_whitespace()
                        .nth(1)
                        .and_then(|v| v.parse().ok())
                })
        })
        .unwrap_or(-1)
}

/// Compute bytes per entry
pub fn bytes_per_entry(rss_kb: i64, num_entries: u64) -> f64 {
    if num_entries == 0 {
        return 0.0;
    }
    (rss_kb as f64 * 1024.0) / num_entries as f64
}

/// Compute overhead ratio (actual / theoretical minimum)
/// Theoretical minimum for u64 key + u64 value = 16 bytes
pub fn overhead_ratio(rss_kb: i64, num_entries: u64) -> f64 {
    bytes_per_entry(rss_kb, num_entries) / 16.0
}
```

---

### Step 4.8: Implement numa.rs

**File:** `rust-impl/src/numa.rs`

**Purpose:** NUMA topology detection and pinning strategies.

**Tasks:**
- [ ] Define PinningStrategy enum
- [ ] Define NumaTopology struct
- [ ] Implement detect_numa() from /sys filesystem
- [ ] Implement get_cores() for each strategy

**Implementation:**
```rust
//! NUMA topology detection and thread pinning strategies

use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PinningStrategy {
    Compact,  // All threads on consecutive cores (same socket)
    Spread,   // Threads distributed across NUMA nodes
}

impl PinningStrategy {
    pub fn as_str(&self) -> &'static str {
        match self {
            PinningStrategy::Compact => "compact",
            PinningStrategy::Spread => "spread",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "compact" => Some(PinningStrategy::Compact),
            "spread" => Some(PinningStrategy::Spread),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct NumaTopology {
    pub num_nodes: usize,
    pub node_cores: Vec<Vec<usize>>,  // node_cores[node] = [core_ids]
}

impl NumaTopology {
    pub fn total_cores(&self) -> usize {
        self.node_cores.iter().map(|v| v.len()).sum()
    }
}

/// Parse CPU list format "0-3,8-11" into vector of core IDs
fn parse_cpulist(cpulist: &str) -> Vec<usize> {
    let mut cores = Vec::new();

    for token in cpulist.trim().split(',') {
        if let Some(dash_pos) = token.find('-') {
            let start: usize = token[..dash_pos].parse().unwrap_or(0);
            let end: usize = token[dash_pos + 1..].parse().unwrap_or(0);
            for i in start..=end {
                cores.push(i);
            }
        } else if let Ok(core) = token.parse() {
            cores.push(core);
        }
    }

    cores
}

/// Detect NUMA topology from /sys filesystem
pub fn detect_numa() -> NumaTopology {
    let base = Path::new("/sys/devices/system/node");
    let mut node_cores: Vec<Vec<usize>> = Vec::new();

    if base.exists() {
        if let Ok(entries) = fs::read_dir(base) {
            let mut nodes: Vec<(usize, Vec<usize>)> = Vec::new();

            for entry in entries.flatten() {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();

                if name_str.starts_with("node") {
                    if let Ok(node_id) = name_str[4..].parse::<usize>() {
                        let cpulist_path = entry.path().join("cpulist");
                        if let Ok(cpulist) = fs::read_to_string(&cpulist_path) {
                            let cores = parse_cpulist(&cpulist);
                            nodes.push((node_id, cores));
                        }
                    }
                }
            }

            // Sort by node ID and build vector
            nodes.sort_by_key(|(id, _)| *id);
            node_cores = nodes.into_iter().map(|(_, cores)| cores).collect();
        }
    }

    // Fallback: single node with all online CPUs
    if node_cores.is_empty() {
        if let Ok(online) = fs::read_to_string("/sys/devices/system/cpu/online") {
            node_cores.push(parse_cpulist(&online));
        } else {
            // Last resort: assume 1 core
            node_cores.push(vec![0]);
        }
    }

    NumaTopology {
        num_nodes: node_cores.len(),
        node_cores,
    }
}

/// Get core IDs for given strategy and thread count
pub fn get_cores(topo: &NumaTopology, strategy: PinningStrategy, num_threads: usize) -> Vec<usize> {
    let mut cores = Vec::with_capacity(num_threads);

    match strategy {
        PinningStrategy::Compact => {
            // Take consecutive cores from first node(s)
            for node_cores in &topo.node_cores {
                for &core in node_cores {
                    cores.push(core);
                    if cores.len() >= num_threads {
                        return cores;
                    }
                }
            }
        }
        PinningStrategy::Spread => {
            // Round-robin across nodes
            let max_per_node = topo.node_cores.iter().map(|v| v.len()).max().unwrap_or(0);

            for i in 0..max_per_node {
                for node_cores in &topo.node_cores {
                    if i < node_cores.len() {
                        cores.push(node_cores[i]);
                        if cores.len() >= num_threads {
                            return cores;
                        }
                    }
                }
            }
        }
    }

    cores
}
```

---

### Step 4.9: Implement scenarios.rs - Config and Types

**File:** `rust-impl/src/scenarios.rs`

**Tasks:**
- [ ] Define constants (OPS_PER_TRIAL, SAMPLE_INTERVAL, etc.)
- [ ] Define LatencySample struct
- [ ] Define LatencyStats struct

**Implementation:**
```rust
//! Benchmark scenarios and worker implementations

use crate::hasher::BuildFastHasher;
use crate::prng::{rand_range, xorshift64star};
use crate::affinity::pin_thread;

use dashmap::DashMap;
use std::sync::{Arc, Barrier};
use std::time::Instant;

// Constants (must match C++)
pub const OPS_PER_TRIAL: u64 = 1_000_000;
pub const WARMUP_OPS: u64 = 100_000;
pub const SAMPLE_INTERVAL: u64 = 1000;
pub const REPEATS: usize = 40;

pub const SIZE_SMALL: u64 = 100_000;
pub const SIZE_MEDIUM: u64 = 1_000_000;
pub const SIZE_LARGE: u64 = 10_000_000;

/// Latency sample from a single operation
#[derive(Debug, Clone)]
pub struct LatencySample {
    pub op_index: u64,
    pub thread_id: usize,
    pub latency_ns: i64,
}

/// Latency statistics
#[derive(Debug, Clone, Default)]
pub struct LatencyStats {
    pub mean_ns: f64,
    pub p50_ns: i64,
    pub p90_ns: i64,
    pub p95_ns: i64,
    pub p99_ns: i64,
    pub max_ns: i64,
    pub count: u64,
}

impl LatencyStats {
    pub fn compute(samples: &[LatencySample]) -> Self {
        if samples.is_empty() {
            return Self::default();
        }

        let mut latencies: Vec<i64> = samples.iter().map(|s| s.latency_ns).collect();
        latencies.sort_unstable();

        let count = latencies.len() as u64;
        let sum: i64 = latencies.iter().sum();
        let mean_ns = sum as f64 / count as f64;

        let percentile = |p: f64| -> i64 {
            let idx = (p * (latencies.len() - 1) as f64) as usize;
            latencies[idx]
        };

        Self {
            mean_ns,
            p50_ns: percentile(0.50),
            p90_ns: percentile(0.90),
            p95_ns: percentile(0.95),
            p99_ns: percentile(0.99),
            max_ns: *latencies.last().unwrap(),
            count,
        }
    }
}

/// Type alias for our concurrent map
pub type ConcurrentMap = DashMap<u64, u64, BuildFastHasher>;

/// Create a new map with custom hasher
pub fn new_map() -> ConcurrentMap {
    DashMap::with_hasher(BuildFastHasher)
}

/// Create a new map with capacity
pub fn new_map_with_capacity(capacity: usize) -> ConcurrentMap {
    DashMap::with_capacity_and_hasher(capacity, BuildFastHasher)
}

/// Pre-populate map with sequential keys [0, count)
pub fn pre_populate(map: &ConcurrentMap, count: u64) {
    for i in 0..count {
        map.insert(i, i);
    }
}
```

---

### Step 4.10: Implement scenarios.rs - Worker Result and Timing

**File:** `rust-impl/src/scenarios.rs` (append)

**Tasks:**
- [ ] Define WorkerResult struct
- [ ] Implement timing helper using Instant

**Implementation:**
```rust
/// Worker thread result
#[derive(Debug)]
pub struct WorkerResult {
    pub duration_ns: i64,
    pub latencies: Vec<LatencySample>,
}

/// Convert Duration to nanoseconds
fn duration_to_ns(start: Instant, end: Instant) -> i64 {
    end.duration_since(start).as_nanos() as i64
}

/// Compute ops per thread
pub fn ops_per_thread(num_threads: usize) -> u64 {
    OPS_PER_TRIAL / num_threads as u64
}
```

---

### Step 4.11: Implement scenarios.rs - Scenario Workers

**File:** `rust-impl/src/scenarios.rs` (append)

**Tasks:**
- [ ] Implement run_insert_only()
- [ ] Implement run_read_only()
- [ ] Implement run_read_majority()
- [ ] Implement run_balanced()
- [ ] Implement run_zipfian()
- [ ] Implement run_resize_stress()
- [ ] Implement run_sequential_keys()
- [ ] Implement run_random_keys()

**Implementation:**
```rust
/// Scenario 1: Insert-only (100% writes, unique keys per thread)
pub fn run_insert_only(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let base_key = thread_id as u64 * ops;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = base_key + i;
        map.insert(key, key);

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 2: Read-only (100% reads)
pub fn run_read_only(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    mut seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let map_size = map.len() as u64;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = rand_range(&mut seed, map_size);
        let _ = map.get(&key);

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 3: Read-majority (parameterized read percentage)
pub fn run_read_majority(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    mut seed: u64,
    read_percent: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let map_size = map.len() as u64;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = rand_range(&mut seed, map_size);
        let op_type = rand_range(&mut seed, 100);

        if op_type < read_percent {
            let _ = map.get(&key);
        } else {
            map.insert(key, key + 1);
        }

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 4: Balanced (50% read, 50% write)
pub fn run_balanced(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    mut seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let map_size = map.len() as u64;
    let write_base = map_size;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let op_type = rand_range(&mut seed, 100);

        if op_type < 50 {
            let key = rand_range(&mut seed, map_size);
            let _ = map.get(&key);
        } else {
            let key = write_base + rand_range(&mut seed, map_size);
            map.insert(key, key);
        }

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 5: Zipfian (90% read, 10% write)
pub fn run_zipfian(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    mut seed: u64,
    zipf_gen: &mut ZipfGenerator,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = zipf_gen.next();
        let op_type = rand_range(&mut seed, 100);

        if op_type < 90 {
            let _ = map.get(&key);
        } else {
            map.insert(key, key + 1);
        }

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 6: Resize stress (small initial capacity)
pub fn run_resize_stress(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    _seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let base_key = thread_id as u64 * ops;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = base_key + i;
        map.insert(key, key);

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 7a: Sequential keys
pub fn run_sequential_keys(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    _seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let base_key = thread_id as u64 * ops;
    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = base_key + i;
        map.insert(key, key);

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}

/// Scenario 7b: Random keys
pub fn run_random_keys(
    map: Arc<ConcurrentMap>,
    thread_id: usize,
    core_id: usize,
    ops: u64,
    mut seed: u64,
    barrier: Arc<Barrier>,
) -> WorkerResult {
    let _ = pin_thread(core_id);
    barrier.wait();

    let mut latencies = Vec::with_capacity((ops / SAMPLE_INTERVAL + 1) as usize);

    let t_start = Instant::now();

    for i in 0..ops {
        let sample = i % SAMPLE_INTERVAL == 0;
        let t0 = if sample { Some(Instant::now()) } else { None };

        let key = xorshift64star(&mut seed);
        map.insert(key, key);

        if let Some(t0) = t0 {
            let t1 = Instant::now();
            latencies.push(LatencySample {
                op_index: i,
                thread_id,
                latency_ns: duration_to_ns(t0, t1),
            });
        }
    }

    let t_end = Instant::now();

    WorkerResult {
        duration_ns: duration_to_ns(t_start, t_end),
        latencies,
    }
}
```

---

### Step 4.12: Implement scenarios.rs - Zipf Generator

**File:** `rust-impl/src/scenarios.rs` (append before workers)

**Tasks:**
- [ ] Implement ZipfGenerator struct
- [ ] Pre-compute harmonic numbers
- [ ] Implement next() method

**Implementation:**
```rust
/// Zipfian distribution generator
pub struct ZipfGenerator {
    n: u64,
    s: f64,
    state: u64,
    h_integral_x1: f64,
    h_integral_n: f64,
}

impl ZipfGenerator {
    pub fn new(n: u64, s: f64, seed: u64) -> Self {
        let h_integral = |x: f64, s: f64| -> f64 {
            if (s - 1.0).abs() < 1e-10 {
                x.ln()
            } else {
                (x.powf(1.0 - s) - 1.0) / (1.0 - s)
            }
        };

        Self {
            n,
            s,
            state: seed,
            h_integral_x1: h_integral(1.5, s) - 1.0,
            h_integral_n: h_integral(n as f64 + 0.5, s),
        }
    }

    pub fn next(&mut self) -> u64 {
        let h_integral_inv = |y: f64, s: f64| -> f64 {
            if (s - 1.0).abs() < 1e-10 {
                y.exp()
            } else {
                (y * (1.0 - s) + 1.0).powf(1.0 / (1.0 - s))
            }
        };

        loop {
            let u = xorshift64star(&mut self.state) as f64 / u64::MAX as f64;
            let h_inv = h_integral_inv(
                self.h_integral_x1 + u * (self.h_integral_n - self.h_integral_x1),
                self.s,
            );

            let mut k = (h_inv + 0.5) as u64;
            if k < 1 {
                k = 1;
            }
            if k > self.n {
                k = self.n;
            }

            let h_integral = |x: f64, s: f64| -> f64 {
                if (s - 1.0).abs() < 1e-10 {
                    x.ln()
                } else {
                    (x.powf(1.0 - s) - 1.0) / (1.0 - s)
                }
            };

            let h_k = h_integral(k as f64 + 0.5, self.s) - h_integral(k as f64 - 0.5, self.s);
            let prob = (k as f64).powf(-self.s) / h_k;

            let u2 = xorshift64star(&mut self.state) as f64 / u64::MAX as f64;

            if u2 < prob {
                return k - 1; // Return 0-indexed
            }
        }
    }
}
```

---

### Step 4.13: Implement main.rs - CLI and Verification

**File:** `rust-impl/src/main.rs`

**Tasks:**
- [ ] Define CLI arguments with clap
- [ ] Implement verify_prng()
- [ ] Implement verify_hash()

**Implementation:**
```rust
mod prng;
mod hasher;
mod affinity;
mod memory;
mod numa;
mod scenarios;

use clap::Parser;
use std::fs::File;
use std::io::{self, Write, BufWriter};
use std::sync::{Arc, Barrier};
use std::thread;

use prng::xorshift64star;
use hasher::hash_u64;
use memory::{get_peak_rss_kb, get_current_rss_kb, bytes_per_entry, overhead_ratio};
use numa::{detect_numa, get_cores, PinningStrategy};
use scenarios::*;

#[derive(Parser, Debug)]
#[command(name = "bench-dashmap")]
#[command(about = "DashMap benchmark for concurrent hash map comparison")]
struct Args {
    /// Scenario name
    #[arg(long, default_value = "insert_only")]
    scenario: String,

    /// Number of threads
    #[arg(long, default_value_t = 1)]
    threads: usize,

    /// Map size (pre-population)
    #[arg(long, default_value_t = SIZE_MEDIUM)]
    mapsize: u64,

    /// Number of repetitions
    #[arg(long, default_value_t = REPEATS)]
    repeats: usize,

    /// PRNG seed
    #[arg(long, default_value_t = 42)]
    seed: u64,

    /// Pinning strategy (compact or spread)
    #[arg(long, default_value = "compact")]
    pinning: String,

    /// Output CSV file (default: stdout)
    #[arg(long)]
    output: Option<String>,

    /// Verify PRNG sequence and exit
    #[arg(long)]
    verify_prng: bool,

    /// Verify hash values and exit
    #[arg(long)]
    verify_hash: bool,
}

fn verify_prng_sequence(seed: u64) {
    let mut state = seed;
    println!("PRNG verification (seed={}):", seed);
    for i in 0..10 {
        let val = xorshift64star(&mut state);
        println!("{}: {}", i, val);
    }
}

fn verify_hash_values() {
    println!("Hash verification:");
    println!("hash(0) = {}", hash_u64(0));
    println!("hash(1) = {}", hash_u64(1));
    println!("hash(42) = {}", hash_u64(42));
    println!("hash(1000000) = {}", hash_u64(1000000));
    println!("hash(UINT64_MAX) = {}", hash_u64(u64::MAX));
}
```

---

### Step 4.14: Implement main.rs - CSV Output

**File:** `rust-impl/src/main.rs` (append)

**Tasks:**
- [ ] Implement print_csv_header()
- [ ] Implement print_csv_row()

**Implementation:**
```rust
fn print_csv_header(out: &mut dyn Write) -> io::Result<()> {
    writeln!(out, "run_id,map_name,map_version,scenario,thread_count,map_size,\
        ops_per_trial,repeat_index,seed,core_mapping,duration_ns,\
        ops_per_sec,mean_sample_latency_ns,p50_latency_ns,\
        p90_latency_ns,p95_latency_ns,p99_latency_ns,\
        max_sample_latency_ns,sampled_ops_count,peak_rss_kb,\
        current_rss_kb,bytes_per_entry,overhead_ratio,\
        numa_nodes,pinning_strategy,allocation_node,notes")
}

#[allow(clippy::too_many_arguments)]
fn print_csv_row(
    out: &mut dyn Write,
    run_id: &str,
    scenario: &str,
    threads: usize,
    map_size: u64,
    repeat_idx: usize,
    seed: u64,
    core_mapping: &str,
    duration_ns: i64,
    lat_stats: &LatencyStats,
    peak_rss: i64,
    current_rss: i64,
    final_map_size: u64,
    numa_nodes: usize,
    pinning: &str,
    notes: &str,
) -> io::Result<()> {
    let ops_per_sec = OPS_PER_TRIAL as f64 * 1_000_000_000.0 / duration_ns as f64;
    let bpe = bytes_per_entry(current_rss, final_map_size);
    let ovr = overhead_ratio(current_rss, final_map_size);

    writeln!(out, "{},dashmap,6.0.0,{},{},{},{},{},{},{},{},{:.2},{:.2},{},{},{},{},{},{},{},{},{:.2},{:.2},{},{},0,{}",
        run_id,
        scenario,
        threads,
        map_size,
        OPS_PER_TRIAL,
        repeat_idx,
        seed,
        core_mapping,
        duration_ns,
        ops_per_sec,
        lat_stats.mean_ns,
        lat_stats.p50_ns,
        lat_stats.p90_ns,
        lat_stats.p95_ns,
        lat_stats.p99_ns,
        lat_stats.max_ns,
        lat_stats.count,
        peak_rss,
        current_rss,
        bpe,
        ovr,
        numa_nodes,
        pinning,
        notes)
}
```

---

### Step 4.15: Implement main.rs - Trial Runner

**File:** `rust-impl/src/main.rs` (append)

**Tasks:**
- [ ] Implement run_trial() function
- [ ] Handle all scenarios
- [ ] Spawn threads and collect results

**Implementation:**
```rust
struct TrialResult {
    total_duration_ns: i64,
    lat_stats: LatencyStats,
    peak_rss_kb: i64,
    current_rss_kb: i64,
    final_map_size: u64,
    core_mapping: String,
}

fn run_trial(
    scenario: &str,
    threads: usize,
    map_size: u64,
    core_ids: &[usize],
    trial_seed: u64,
) -> TrialResult {
    // Create map
    let needs_prepop = matches!(scenario,
        "read_only" | "read_majority_99" | "read_majority_95" | "balanced" | "zipfian");

    let map = if needs_prepop {
        let m = new_map_with_capacity(map_size as usize);
        pre_populate(&m, map_size);
        Arc::new(m)
    } else if scenario == "resize_stress" {
        Arc::new(new_map_with_capacity(1024))
    } else {
        Arc::new(new_map_with_capacity(map_size as usize))
    };

    let core_mapping: String = core_ids.iter()
        .map(|c| c.to_string())
        .collect::<Vec<_>>()
        .join(",");

    let barrier = Arc::new(Barrier::new(threads));
    let ops = ops_per_thread(threads);

    let handles: Vec<_> = (0..threads)
        .map(|tid| {
            let map = Arc::clone(&map);
            let barrier = Arc::clone(&barrier);
            let core_id = core_ids[tid];
            let seed = trial_seed + tid as u64;
            let scenario = scenario.to_string();

            thread::spawn(move || {
                match scenario.as_str() {
                    "insert_only" => run_insert_only(map, tid, core_id, ops, seed, barrier),
                    "read_only" => run_read_only(map, tid, core_id, ops, seed, barrier),
                    "read_majority_99" => run_read_majority(map, tid, core_id, ops, seed, 99, barrier),
                    "read_majority_95" => run_read_majority(map, tid, core_id, ops, seed, 95, barrier),
                    "balanced" => run_balanced(map, tid, core_id, ops, seed, barrier),
                    "zipfian" => {
                        let mut zipf = ZipfGenerator::new(map.len() as u64, 1.0, seed + 1000);
                        run_zipfian(map, tid, core_id, ops, seed, &mut zipf, barrier)
                    }
                    "resize_stress" => run_resize_stress(map, tid, core_id, ops, seed, barrier),
                    "sequential_keys" => run_sequential_keys(map, tid, core_id, ops, seed, barrier),
                    "random_keys" => run_random_keys(map, tid, core_id, ops, seed, barrier),
                    _ => panic!("Unknown scenario: {}", scenario),
                }
            })
        })
        .collect();

    // Collect results
    let results: Vec<WorkerResult> = handles.into_iter()
        .map(|h| h.join().expect("Thread panicked"))
        .collect();

    let max_duration = results.iter().map(|r| r.duration_ns).max().unwrap_or(0);
    let all_latencies: Vec<LatencySample> = results.into_iter()
        .flat_map(|r| r.latencies)
        .collect();

    TrialResult {
        total_duration_ns: max_duration,
        lat_stats: LatencyStats::compute(&all_latencies),
        peak_rss_kb: get_peak_rss_kb(),
        current_rss_kb: get_current_rss_kb(),
        final_map_size: map.len() as u64,
        core_mapping,
    }
}
```

---

### Step 4.16: Implement main.rs - Main Function

**File:** `rust-impl/src/main.rs` (append)

**Tasks:**
- [ ] Parse CLI args
- [ ] Handle verification modes
- [ ] Run repetitions
- [ ] Output CSV

**Implementation:**
```rust
fn main() -> io::Result<()> {
    let args = Args::parse();

    // Handle verification modes
    if args.verify_prng {
        verify_prng_sequence(args.seed);
        return Ok(());
    }
    if args.verify_hash {
        verify_hash_values();
        return Ok(());
    }

    // Parse pinning strategy
    let pinning = PinningStrategy::from_str(&args.pinning)
        .unwrap_or(PinningStrategy::Compact);

    // Detect NUMA topology
    let topo = detect_numa();
    let core_ids = get_cores(&topo, pinning, args.threads);

    if core_ids.len() < args.threads {
        eprintln!("Error: Not enough cores ({}) for {} threads",
            core_ids.len(), args.threads);
        std::process::exit(1);
    }

    // Open output file
    let mut out: Box<dyn Write> = match &args.output {
        Some(path) => Box::new(BufWriter::new(File::create(path)?)),
        None => Box::new(io::stdout()),
    };

    // Print CSV header
    print_csv_header(&mut out)?;

    // Generate run ID
    let run_id = format!("dashmap_{}_{:}t_{:}m",
        args.scenario, args.threads, args.mapsize);

    // Run repetitions
    for rep in 0..args.repeats {
        let trial_seed = args.seed + rep as u64;

        let result = run_trial(
            &args.scenario,
            args.threads,
            args.mapsize,
            &core_ids,
            trial_seed,
        );

        print_csv_row(
            &mut out,
            &run_id,
            &args.scenario,
            args.threads,
            args.mapsize,
            rep,
            trial_seed,
            &result.core_mapping,
            result.total_duration_ns,
            &result.lat_stats,
            result.peak_rss_kb,
            result.current_rss_kb,
            result.final_map_size,
            topo.num_nodes,
            pinning.as_str(),
            "",
        )?;

        // Progress indicator
        eprint!("\r[{}/{}] {} threads={} mapsize={}",
            rep + 1, args.repeats, args.scenario,
            args.threads, args.mapsize);
    }

    eprintln!();
    Ok(())
}
```

---

### Step 4.17: Build and Verify

**Tasks:**
- [ ] Build in release mode
- [ ] Verify PRNG matches C++
- [ ] Verify hash matches C++
- [ ] Run simple benchmark

**Commands:**
```bash
cd rust-impl
cargo build --release

# Verify PRNG (compare with C++)
./target/release/bench-dashmap --verify-prng --seed 42 > rust_prng.txt
diff ../cpp_prng.txt rust_prng.txt

# Verify hash (compare with C++)
./target/release/bench-dashmap --verify-hash > rust_hash.txt
diff ../cpp_hasher.txt rust_hash.txt

# Quick benchmark test
./target/release/bench-dashmap --scenario insert_only --threads 4 --mapsize 100000 --repeats 3
```

---

### Step 4.18: Test All Scenarios

**Tasks:**
- [ ] Test each scenario
- [ ] Verify CSV output format matches C++
- [ ] Check for errors or panics

**Commands:**
```bash
SCENARIOS="insert_only read_only read_majority_99 read_majority_95 balanced zipfian resize_stress sequential_keys random_keys"

for s in $SCENARIOS; do
    echo "Testing $s..."
    ./target/release/bench-dashmap --scenario $s --threads 2 --mapsize 10000 --repeats 2
done
```

---

## Verification Checklist

- [ ] cargo build --release succeeds
- [ ] --verify-prng output matches C++ exactly
- [ ] --verify-hash output matches C++ exactly
- [ ] All 9 scenarios run without panics
- [ ] CSV output format matches C++ specification
- [ ] Thread pinning works (verify with htop)
- [ ] Memory measurements are populated

## Files Created

| File | Purpose | Lines (approx) |
|------|---------|----------------|
| `rust-impl/Cargo.toml` | Package configuration | ~20 |
| `rust-impl/.cargo/config.toml` | Build flags | ~3 |
| `rust-impl/src/prng.rs` | xorshift64* PRNG | ~30 |
| `rust-impl/src/hasher.rs` | Fast hash function | ~50 |
| `rust-impl/src/affinity.rs` | Thread pinning | ~25 |
| `rust-impl/src/memory.rs` | RSS measurement | ~35 |
| `rust-impl/src/numa.rs` | NUMA topology | ~120 |
| `rust-impl/src/scenarios.rs` | Workload scenarios | ~400 |
| `rust-impl/src/main.rs` | CLI and orchestration | ~250 |

## API Comparison: DashMap vs C++ Maps

| Operation | DashMap | parallel-hashmap | libcuckoo |
|-----------|---------|------------------|-----------|
| Insert | `map.insert(k, v)` | `map.insert({k, v})` | `map.insert(k, v)` |
| Get | `map.get(&k)` | `map.find(k)` | `map.find(k, &v)` |
| Update | `map.insert(k, v)` | `map.insert_or_assign(k, v)` | `map.upsert(k, fn, v)` |
| Size | `map.len()` | `map.size()` | `map.size()` |
| With capacity | `DashMap::with_capacity(n)` | `map.reserve(n)` | `map.reserve(n)` |

## DashMap Characteristics

| Property | Value |
|----------|-------|
| Default shards | `num_cpus * 4` |
| Lock type | `parking_lot::RwLock` (spin + park) |
| Read-read parallelism | Yes |
| Hash function | Configurable (using BuildFastHasher) |

## Next Phase

After verification, proceed to **Phase 5: Validation** to run cross-implementation verification tests.
