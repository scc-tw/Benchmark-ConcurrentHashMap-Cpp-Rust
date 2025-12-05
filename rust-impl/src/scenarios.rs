//! Benchmark scenarios and worker implementations

use crate::affinity::pin_thread;
use crate::hasher::BuildFastHasher;
use crate::prng::{rand_range, xorshift64star};

use dashmap::DashMap;
use std::sync::{Arc, Barrier};
use std::time::Instant;

// Constants (must match C++)
pub const OPS_PER_TRIAL: u64 = 1_000_000;
#[allow(dead_code)]
pub const WARMUP_OPS: u64 = 100_000;
pub const SAMPLE_INTERVAL: u64 = 1000;
pub const REPEATS: usize = 40;

#[allow(dead_code)]
pub const SIZE_SMALL: u64 = 100_000;
pub const SIZE_MEDIUM: u64 = 1_000_000;
#[allow(dead_code)]
pub const SIZE_LARGE: u64 = 10_000_000;

/// Latency sample from a single operation
#[derive(Debug, Clone)]
pub struct LatencySample {
    #[allow(dead_code)]
    pub op_index: u64,
    #[allow(dead_code)]
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
#[allow(dead_code)]
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

// ============================================================================
// Zipfian Distribution Generator
// ============================================================================

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

        let h_integral = |x: f64, s: f64| -> f64 {
            if (s - 1.0).abs() < 1e-10 {
                x.ln()
            } else {
                (x.powf(1.0 - s) - 1.0) / (1.0 - s)
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

            let h_k = h_integral(k as f64 + 0.5, self.s) - h_integral(k as f64 - 0.5, self.s);
            let prob = (k as f64).powf(-self.s) / h_k;

            let u2 = xorshift64star(&mut self.state) as f64 / u64::MAX as f64;

            if u2 < prob {
                return k - 1; // Return 0-indexed
            }
        }
    }
}

// ============================================================================
// Scenario Workers
// ============================================================================

/// Scenario 1: Insert-only (100% writes, unique keys per thread)
pub fn run_insert_only(
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
