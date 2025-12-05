mod affinity;
mod hasher;
mod memory;
mod numa;
mod prng;
mod scenarios;

use clap::Parser;
use std::fs::File;
use std::io::{self, BufWriter, Write};
use std::sync::{Arc, Barrier};
use std::thread;

use hasher::hash_u64;
use memory::{bytes_per_entry, get_current_rss_kb, get_peak_rss_kb, overhead_ratio};
use numa::{detect_numa, get_cores, PinningStrategy};
use prng::xorshift64star;
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

fn print_csv_header(out: &mut dyn Write) -> io::Result<()> {
    writeln!(
        out,
        "run_id,map_name,map_version,scenario,thread_count,map_size,\
        ops_per_trial,repeat_index,seed,core_mapping,duration_ns,\
        ops_per_sec,mean_sample_latency_ns,p50_latency_ns,\
        p90_latency_ns,p95_latency_ns,p99_latency_ns,\
        max_sample_latency_ns,sampled_ops_count,peak_rss_kb,\
        current_rss_kb,bytes_per_entry,overhead_ratio,\
        numa_nodes,pinning_strategy,allocation_node,notes"
    )
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

    writeln!(
        out,
        "{},dashmap,6.0.0,{},{},{},{},{},{},{},{},{:.2},{:.2},{},{},{},{},{},{},{},{},{:.2},{:.2},{},{},0,{}",
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
        notes
    )
}

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
    let needs_prepop = matches!(
        scenario,
        "read_only" | "read_majority_99" | "read_majority_95" | "balanced" | "zipfian"
    );

    let map = if needs_prepop {
        let m = new_map_with_capacity(map_size as usize);
        pre_populate(&m, map_size);
        Arc::new(m)
    } else if scenario == "resize_stress" {
        Arc::new(new_map_with_capacity(1024))
    } else {
        Arc::new(new_map_with_capacity(map_size as usize))
    };

    let core_mapping: String = core_ids
        .iter()
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
            let map_len = map.len() as u64;

            thread::spawn(move || match scenario.as_str() {
                "insert_only" => run_insert_only(map, tid, core_id, ops, seed, barrier),
                "read_only" => run_read_only(map, tid, core_id, ops, seed, barrier),
                "read_majority_99" => {
                    run_read_majority(map, tid, core_id, ops, seed, 99, barrier)
                }
                "read_majority_95" => {
                    run_read_majority(map, tid, core_id, ops, seed, 95, barrier)
                }
                "balanced" => run_balanced(map, tid, core_id, ops, seed, barrier),
                "zipfian" => {
                    let mut zipf = ZipfGenerator::new(map_len, 1.0, seed + 1000);
                    run_zipfian(map, tid, core_id, ops, seed, &mut zipf, barrier)
                }
                "resize_stress" => run_resize_stress(map, tid, core_id, ops, seed, barrier),
                "sequential_keys" => run_sequential_keys(map, tid, core_id, ops, seed, barrier),
                "random_keys" => run_random_keys(map, tid, core_id, ops, seed, barrier),
                _ => panic!("Unknown scenario: {}", scenario),
            })
        })
        .collect();

    // Collect results
    let results: Vec<WorkerResult> = handles
        .into_iter()
        .map(|h| h.join().expect("Thread panicked"))
        .collect();

    let max_duration = results.iter().map(|r| r.duration_ns).max().unwrap_or(0);
    let all_latencies: Vec<LatencySample> = results.into_iter().flat_map(|r| r.latencies).collect();

    TrialResult {
        total_duration_ns: max_duration,
        lat_stats: LatencyStats::compute(&all_latencies),
        peak_rss_kb: get_peak_rss_kb(),
        current_rss_kb: get_current_rss_kb(),
        final_map_size: map.len() as u64,
        core_mapping,
    }
}

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
    let pinning = PinningStrategy::from_str(&args.pinning).unwrap_or(PinningStrategy::Compact);

    // Detect NUMA topology
    let topo = detect_numa();
    let core_ids = get_cores(&topo, pinning, args.threads);

    if core_ids.len() < args.threads {
        eprintln!(
            "Error: Not enough cores ({}) for {} threads",
            core_ids.len(),
            args.threads
        );
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
    let run_id = format!(
        "dashmap_{}_{}t_{}m",
        args.scenario, args.threads, args.mapsize
    );

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
        eprint!(
            "\r[{}/{}] {} threads={} mapsize={}",
            rep + 1,
            args.repeats,
            args.scenario,
            args.threads,
            args.mapsize
        );
    }

    eprintln!();
    Ok(())
}
