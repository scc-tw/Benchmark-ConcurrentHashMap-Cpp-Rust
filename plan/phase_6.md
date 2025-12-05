# Phase 6: Orchestration Scripts

## Objective

Implement experiment orchestration, statistical analysis, and visualization pipeline:
- `run-experiments.sh` - Generate and execute experiment matrix with randomization
- `aggregate-results.py` - Compute CLT-based statistics (mean, std, 95% CI)
- `generate-plots.sh` - Produce publication-quality gnuplot visualizations

## Prerequisites

- Phase 1-5 complete (all validations pass)
- Python 3.x with NumPy installed
- gnuplot 5.0+ installed
- Sufficient disk space (~1GB for full experiment suite)

## Experiment Matrix

| Dimension | Values | Count |
|-----------|--------|-------|
| Maps | phmap, libcuckoo, dashmap | 3 |
| Scenarios | insert_only, read_only, read_majority_99, read_majority_95, balanced, zipfian, resize_stress, sequential_keys, random_keys | 9 |
| Map sizes | 100K, 1M, 10M | 3 |
| Thread counts | 1, 2, 4, 8, 16, 32 | 6 |
| Pinning strategies | compact, spread | 2 |
| Repetitions | 40 | 40 |

**Total trials:** 3 × 9 × 3 × 6 × 2 × 40 = **38,880**

**Estimated runtime:** ~2-3 seconds/trial → **24-36 hours**

## Steps

---

### Step 6.1: Create Scripts Directory Structure

**Tasks:**
- [ ] Create scripts directory (if not exists)
- [ ] Create plots directory
- [ ] Create results directory structure

**Commands:**
```bash
mkdir -p scripts
mkdir -p plots
mkdir -p results/raw
mkdir -p results/aggregated
mkdir -p results/plots
```

---

### Step 6.2: Implement run-experiments.sh - Configuration

**File:** `scripts/run-experiments.sh`

**Tasks:**
- [ ] Define experiment parameters
- [ ] Define implementation binaries
- [ ] Add configuration options

**Implementation (Part 1 - Configuration):**
```bash
#!/bin/bash
# run-experiments.sh - Execute full benchmark experiment matrix
#
# Usage: ./scripts/run-experiments.sh [options]
#   --dry-run       Show experiment matrix without executing
#   --quick         Run reduced matrix for testing
#   --resume        Resume from last checkpoint
#   --single-impl   Run only specified implementation (phmap|libcuckoo|dashmap)
#   --single-scenario Run only specified scenario

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ============================================================================
# Configuration
# ============================================================================

# Implementations
IMPLEMENTATIONS="phmap libcuckoo dashmap"

# Scenarios
SCENARIOS="insert_only read_only read_majority_99 read_majority_95 balanced zipfian resize_stress sequential_keys random_keys"

# Map sizes
MAP_SIZES="100000 1000000 10000000"

# Thread counts
THREAD_COUNTS="1 2 4 8 16 32"

# Pinning strategies
PINNING_STRATEGIES="compact spread"

# Repetitions per configuration
REPEATS=40

# Base seed for reproducibility
BASE_SEED=42

# Output directories
RAW_DIR="results/raw"
LOG_DIR="results/logs"
CHECKPOINT_FILE="results/.checkpoint"

# Binaries
BIN_PHMAP="build/cpp-impl/bench-phmap"
BIN_LIBCUCKOO="build/cpp-impl/bench-libcuckoo"
BIN_DASHMAP="rust-impl/target/release/bench-dashmap"

# ============================================================================
# Parse Arguments
# ============================================================================

DRY_RUN=false
QUICK_MODE=false
RESUME=false
SINGLE_IMPL=""
SINGLE_SCENARIO=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --single-impl)
            SINGLE_IMPL="$2"
            shift 2
            ;;
        --single-scenario)
            SINGLE_SCENARIO="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Quick mode: reduced matrix
if $QUICK_MODE; then
    MAP_SIZES="100000 1000000"
    THREAD_COUNTS="1 4 16"
    PINNING_STRATEGIES="compact"
    REPEATS=5
    echo "Quick mode: reduced experiment matrix"
fi

# Single implementation mode
if [ -n "$SINGLE_IMPL" ]; then
    IMPLEMENTATIONS="$SINGLE_IMPL"
fi

# Single scenario mode
if [ -n "$SINGLE_SCENARIO" ]; then
    SCENARIOS="$SINGLE_SCENARIO"
fi
```

---

### Step 6.3: Implement run-experiments.sh - Matrix Generation

**File:** `scripts/run-experiments.sh` (append)

**Tasks:**
- [ ] Generate experiment list
- [ ] Randomize order to avoid systematic bias
- [ ] Support checkpoint/resume

**Implementation (Part 2 - Matrix Generation):**
```bash
# ============================================================================
# Generate Experiment Matrix
# ============================================================================

generate_experiment_matrix() {
    local experiments=()
    local idx=0

    for impl in $IMPLEMENTATIONS; do
        for scenario in $SCENARIOS; do
            for mapsize in $MAP_SIZES; do
                for threads in $THREAD_COUNTS; do
                    for pinning in $PINNING_STRATEGIES; do
                        experiments+=("$idx|$impl|$scenario|$mapsize|$threads|$pinning")
                        ((idx++))
                    done
                done
            done
        done
    done

    # Shuffle experiments to randomize order (avoid systematic bias)
    printf '%s\n' "${experiments[@]}" | shuf --random-source=<(echo $BASE_SEED)
}

# ============================================================================
# Checkpoint Management
# ============================================================================

load_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        cat "$CHECKPOINT_FILE"
    else
        echo ""
    fi
}

save_checkpoint() {
    echo "$1" >> "$CHECKPOINT_FILE"
}

is_completed() {
    local exp_id="$1"
    if [ -f "$CHECKPOINT_FILE" ]; then
        grep -q "^$exp_id$" "$CHECKPOINT_FILE"
        return $?
    fi
    return 1
}

# ============================================================================
# System Metadata
# ============================================================================

capture_system_metadata() {
    local metadata_file="results/system_metadata.json"

    cat > "$metadata_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "cpu_model": "$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)",
    "cpu_cores": $(nproc),
    "cpu_threads": $(grep -c processor /proc/cpuinfo),
    "memory_gb": $(free -g | grep Mem | awk '{print $2}'),
    "numa_nodes": $(ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l || echo 1),
    "gcc_version": "$(g++ --version | head -1)",
    "rustc_version": "$(rustc --version)",
    "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')",
    "experiment_config": {
        "implementations": "$IMPLEMENTATIONS",
        "scenarios": "$SCENARIOS",
        "map_sizes": "$MAP_SIZES",
        "thread_counts": "$THREAD_COUNTS",
        "pinning_strategies": "$PINNING_STRATEGIES",
        "repeats": $REPEATS,
        "base_seed": $BASE_SEED
    }
}
EOF
    echo "System metadata saved to $metadata_file"
}
```

---

### Step 6.4: Implement run-experiments.sh - Execution

**File:** `scripts/run-experiments.sh` (append)

**Tasks:**
- [ ] Implement experiment execution function
- [ ] Handle output file naming
- [ ] Add progress reporting

**Implementation (Part 3 - Execution):**
```bash
# ============================================================================
# Run Single Experiment
# ============================================================================

run_experiment() {
    local impl="$1"
    local scenario="$2"
    local mapsize="$3"
    local threads="$4"
    local pinning="$5"

    # Select binary
    local bin=""
    case $impl in
        phmap)
            bin="$BIN_PHMAP"
            ;;
        libcuckoo)
            bin="$BIN_LIBCUCKOO"
            ;;
        dashmap)
            bin="$BIN_DASHMAP"
            ;;
        *)
            echo "Unknown implementation: $impl"
            return 1
            ;;
    esac

    # Output file
    local output_file="${RAW_DIR}/${impl}_${scenario}_${threads}t_${mapsize}m_${pinning}.csv"

    # Run benchmark
    $bin \
        --scenario "$scenario" \
        --threads "$threads" \
        --mapsize "$mapsize" \
        --repeats "$REPEATS" \
        --seed "$BASE_SEED" \
        --pinning "$pinning" \
        --output "$output_file" \
        2>> "${LOG_DIR}/${impl}.log"

    return $?
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo "=============================================="
    echo "  Concurrent HashMap Benchmark Suite"
    echo "=============================================="
    echo ""

    # Create directories
    mkdir -p "$RAW_DIR"
    mkdir -p "$LOG_DIR"

    # Verify binaries exist
    for bin in "$BIN_PHMAP" "$BIN_LIBCUCKOO" "$BIN_DASHMAP"; do
        if [ ! -x "$bin" ]; then
            echo "ERROR: Binary not found or not executable: $bin"
            echo "Please build the project first."
            exit 1
        fi
    done

    # Capture system metadata
    capture_system_metadata

    # Generate experiment matrix
    echo "Generating experiment matrix..."
    mapfile -t EXPERIMENTS < <(generate_experiment_matrix)
    TOTAL_EXPERIMENTS=${#EXPERIMENTS[@]}
    echo "Total experiments: $TOTAL_EXPERIMENTS"
    echo ""

    # Dry run mode
    if $DRY_RUN; then
        echo "Dry run mode - showing first 20 experiments:"
        printf '%s\n' "${EXPERIMENTS[@]}" | head -20
        echo "..."
        echo ""
        echo "Total: $TOTAL_EXPERIMENTS experiments"
        echo "Estimated time: $(( TOTAL_EXPERIMENTS * 3 / 60 )) minutes"
        exit 0
    fi

    # Check CPU governor
    local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    if [ "$governor" != "performance" ]; then
        echo "WARNING: CPU governor is '$governor', not 'performance'"
        echo "For accurate results, run: sudo cpupower frequency-set -g performance"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Resume mode
    local completed=0
    if $RESUME && [ -f "$CHECKPOINT_FILE" ]; then
        completed=$(wc -l < "$CHECKPOINT_FILE")
        echo "Resuming from checkpoint: $completed experiments completed"
    fi

    # Execute experiments
    local start_time=$(date +%s)
    local current=0

    for exp in "${EXPERIMENTS[@]}"; do
        ((current++))

        # Parse experiment
        IFS='|' read -r idx impl scenario mapsize threads pinning <<< "$exp"
        local exp_id="${impl}_${scenario}_${mapsize}_${threads}_${pinning}"

        # Skip if already completed (resume mode)
        if $RESUME && is_completed "$exp_id"; then
            continue
        fi

        # Progress
        local elapsed=$(( $(date +%s) - start_time ))
        local rate=$(echo "scale=2; $current / ($elapsed + 1)" | bc)
        local eta=$(echo "scale=0; ($TOTAL_EXPERIMENTS - $current) / ($rate + 0.01)" | bc)

        printf "\r[%d/%d] %s %s threads=%s mapsize=%s pinning=%s (ETA: %dm)     " \
            "$current" "$TOTAL_EXPERIMENTS" "$impl" "$scenario" "$threads" "$mapsize" "$pinning" "$((eta / 60))"

        # Run experiment
        if run_experiment "$impl" "$scenario" "$mapsize" "$threads" "$pinning"; then
            save_checkpoint "$exp_id"
        else
            echo ""
            echo "ERROR: Experiment failed: $exp_id"
            echo "Check log: ${LOG_DIR}/${impl}.log"
        fi
    done

    echo ""
    echo ""
    echo "=============================================="
    echo "  Experiments Complete"
    echo "=============================================="
    echo "Total time: $(( ($(date +%s) - start_time) / 60 )) minutes"
    echo "Results in: $RAW_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Run: python scripts/aggregate-results.py"
    echo "  2. Run: ./scripts/generate-plots.sh"
}

main
```

**Make executable:**
```bash
chmod +x scripts/run-experiments.sh
```

---

### Step 6.5: Implement aggregate-results.py - Setup

**File:** `scripts/aggregate-results.py`

**Tasks:**
- [ ] Import required libraries
- [ ] Define input/output paths
- [ ] Parse command-line arguments

**Implementation (Part 1 - Setup):**
```python
#!/usr/bin/env python3
"""
aggregate-results.py - Compute CLT-based statistics from raw benchmark results

Usage:
    python scripts/aggregate-results.py [--input DIR] [--output FILE]

Computes for each (map, scenario, threads, mapsize, pinning) configuration:
    - Sample mean (x̄)
    - Sample standard deviation (s)
    - Standard error (SE = s / √n)
    - 95% confidence interval (x̄ ± 1.96 × SE)
"""

import argparse
import csv
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_INPUT_DIR = "results/raw"
DEFAULT_OUTPUT_FILE = "results/aggregated/summary.csv"

# CSV column indices (0-based)
COL_MAP_NAME = 1
COL_SCENARIO = 3
COL_THREADS = 4
COL_MAPSIZE = 5
COL_OPS_PER_SEC = 11
COL_MEAN_LATENCY = 12
COL_P50_LATENCY = 13
COL_P90_LATENCY = 14
COL_P95_LATENCY = 15
COL_P99_LATENCY = 16
COL_PEAK_RSS = 19
COL_CURRENT_RSS = 20
COL_BYTES_PER_ENTRY = 21
COL_OVERHEAD_RATIO = 22
COL_PINNING = 24

# Confidence level
Z_95 = 1.96  # z-score for 95% CI


def parse_args():
    parser = argparse.ArgumentParser(description="Aggregate benchmark results")
    parser.add_argument(
        "--input", "-i",
        default=DEFAULT_INPUT_DIR,
        help=f"Input directory with raw CSV files (default: {DEFAULT_INPUT_DIR})"
    )
    parser.add_argument(
        "--output", "-o",
        default=DEFAULT_OUTPUT_FILE,
        help=f"Output aggregated CSV file (default: {DEFAULT_OUTPUT_FILE})"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output"
    )
    return parser.parse_args()
```

---

### Step 6.6: Implement aggregate-results.py - Data Loading

**File:** `scripts/aggregate-results.py` (append)

**Tasks:**
- [ ] Implement CSV loading
- [ ] Group data by configuration
- [ ] Handle multiple files

**Implementation (Part 2 - Data Loading):**
```python
# ============================================================================
# Data Loading
# ============================================================================

def load_csv_files(input_dir: str, verbose: bool = False) -> Dict[str, List[dict]]:
    """Load all CSV files and group by configuration key."""
    data = defaultdict(list)
    input_path = Path(input_dir)

    if not input_path.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    csv_files = list(input_path.glob("*.csv"))
    if not csv_files:
        print(f"ERROR: No CSV files found in {input_dir}")
        sys.exit(1)

    if verbose:
        print(f"Found {len(csv_files)} CSV files")

    for csv_file in csv_files:
        if verbose:
            print(f"  Loading: {csv_file.name}")

        with open(csv_file, "r") as f:
            reader = csv.reader(f)
            header = next(reader)  # Skip header

            for row in reader:
                if len(row) < 25:  # Minimum expected columns
                    continue

                try:
                    # Extract key fields
                    map_name = row[COL_MAP_NAME]
                    scenario = row[COL_SCENARIO]
                    threads = int(row[COL_THREADS])
                    mapsize = int(row[COL_MAPSIZE])
                    pinning = row[COL_PINNING]

                    # Create configuration key
                    config_key = f"{map_name}|{scenario}|{threads}|{mapsize}|{pinning}"

                    # Extract metrics
                    metrics = {
                        "ops_per_sec": float(row[COL_OPS_PER_SEC]),
                        "mean_latency_ns": float(row[COL_MEAN_LATENCY]),
                        "p50_latency_ns": int(row[COL_P50_LATENCY]),
                        "p90_latency_ns": int(row[COL_P90_LATENCY]),
                        "p95_latency_ns": int(row[COL_P95_LATENCY]),
                        "p99_latency_ns": int(row[COL_P99_LATENCY]),
                        "peak_rss_kb": int(row[COL_PEAK_RSS]),
                        "current_rss_kb": int(row[COL_CURRENT_RSS]),
                        "bytes_per_entry": float(row[COL_BYTES_PER_ENTRY]),
                        "overhead_ratio": float(row[COL_OVERHEAD_RATIO]),
                    }

                    data[config_key].append(metrics)

                except (ValueError, IndexError) as e:
                    if verbose:
                        print(f"    Warning: Skipping row: {e}")
                    continue

    if verbose:
        print(f"Loaded {sum(len(v) for v in data.values())} data points")
        print(f"Unique configurations: {len(data)}")

    return data
```

---

### Step 6.7: Implement aggregate-results.py - Statistics

**File:** `scripts/aggregate-results.py` (append)

**Tasks:**
- [ ] Implement CLT-based statistics calculation
- [ ] Compute mean, std, SE, 95% CI

**Implementation (Part 3 - Statistics):**
```python
# ============================================================================
# Statistical Analysis
# ============================================================================

def compute_statistics(samples: List[float]) -> Tuple[float, float, float, float, float]:
    """
    Compute CLT-based statistics.

    Returns:
        (mean, std, se, ci95_low, ci95_high)
    """
    arr = np.array(samples)
    n = len(arr)

    if n < 2:
        mean = arr[0] if n == 1 else 0.0
        return (mean, 0.0, 0.0, mean, mean)

    mean = np.mean(arr)
    std = np.std(arr, ddof=1)  # Sample std (ddof=1)
    se = std / np.sqrt(n)
    ci95_half = Z_95 * se
    ci95_low = mean - ci95_half
    ci95_high = mean + ci95_half

    return (mean, std, se, ci95_low, ci95_high)


def aggregate_configuration(metrics_list: List[dict]) -> dict:
    """Aggregate metrics for a single configuration."""
    # Extract arrays for each metric
    ops_per_sec = [m["ops_per_sec"] for m in metrics_list]
    mean_latency = [m["mean_latency_ns"] for m in metrics_list]
    p50_latency = [m["p50_latency_ns"] for m in metrics_list]
    p90_latency = [m["p90_latency_ns"] for m in metrics_list]
    p95_latency = [m["p95_latency_ns"] for m in metrics_list]
    p99_latency = [m["p99_latency_ns"] for m in metrics_list]
    peak_rss = [m["peak_rss_kb"] for m in metrics_list]
    bytes_per_entry = [m["bytes_per_entry"] for m in metrics_list]

    # Compute statistics for throughput (primary metric)
    ops_mean, ops_std, ops_se, ops_ci_low, ops_ci_high = compute_statistics(ops_per_sec)

    # Compute statistics for latency
    lat_mean, lat_std, lat_se, lat_ci_low, lat_ci_high = compute_statistics(mean_latency)

    # Compute median of percentiles (more robust)
    p50_median = np.median(p50_latency)
    p90_median = np.median(p90_latency)
    p95_median = np.median(p95_latency)
    p99_median = np.median(p99_latency)

    # Memory (take median - should be stable)
    rss_median = np.median(peak_rss)
    bpe_median = np.median(bytes_per_entry)

    return {
        "n_samples": len(metrics_list),
        # Throughput
        "ops_per_sec_mean": ops_mean,
        "ops_per_sec_std": ops_std,
        "ops_per_sec_se": ops_se,
        "ops_per_sec_ci95_low": ops_ci_low,
        "ops_per_sec_ci95_high": ops_ci_high,
        # Latency
        "latency_mean_ns": lat_mean,
        "latency_std_ns": lat_std,
        "latency_ci95_low": lat_ci_low,
        "latency_ci95_high": lat_ci_high,
        # Percentiles (median of samples)
        "p50_latency_ns": p50_median,
        "p90_latency_ns": p90_median,
        "p95_latency_ns": p95_median,
        "p99_latency_ns": p99_median,
        # Memory
        "peak_rss_kb": rss_median,
        "bytes_per_entry": bpe_median,
    }
```

---

### Step 6.8: Implement aggregate-results.py - Output

**File:** `scripts/aggregate-results.py` (append)

**Tasks:**
- [ ] Write aggregated CSV output
- [ ] Format numbers appropriately
- [ ] Add main function

**Implementation (Part 4 - Output):**
```python
# ============================================================================
# Output
# ============================================================================

def write_aggregated_csv(data: Dict[str, dict], output_file: str, verbose: bool = False):
    """Write aggregated statistics to CSV file."""
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    header = [
        "map_name", "scenario", "threads", "mapsize", "pinning", "n_samples",
        "ops_per_sec_mean", "ops_per_sec_std", "ops_per_sec_se",
        "ops_per_sec_ci95_low", "ops_per_sec_ci95_high",
        "latency_mean_ns", "latency_std_ns",
        "latency_ci95_low", "latency_ci95_high",
        "p50_latency_ns", "p90_latency_ns", "p95_latency_ns", "p99_latency_ns",
        "peak_rss_kb", "bytes_per_entry"
    ]

    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)

        for config_key, stats in sorted(data.items()):
            map_name, scenario, threads, mapsize, pinning = config_key.split("|")

            row = [
                map_name, scenario, threads, mapsize, pinning,
                stats["n_samples"],
                f"{stats['ops_per_sec_mean']:.2f}",
                f"{stats['ops_per_sec_std']:.2f}",
                f"{stats['ops_per_sec_se']:.2f}",
                f"{stats['ops_per_sec_ci95_low']:.2f}",
                f"{stats['ops_per_sec_ci95_high']:.2f}",
                f"{stats['latency_mean_ns']:.2f}",
                f"{stats['latency_std_ns']:.2f}",
                f"{stats['latency_ci95_low']:.2f}",
                f"{stats['latency_ci95_high']:.2f}",
                f"{stats['p50_latency_ns']:.0f}",
                f"{stats['p90_latency_ns']:.0f}",
                f"{stats['p95_latency_ns']:.0f}",
                f"{stats['p99_latency_ns']:.0f}",
                f"{stats['peak_rss_kb']:.0f}",
                f"{stats['bytes_per_entry']:.2f}",
            ]
            writer.writerow(row)

    if verbose:
        print(f"Wrote {len(data)} configurations to {output_file}")


# ============================================================================
# Main
# ============================================================================

def main():
    args = parse_args()

    print("=== Aggregating Benchmark Results ===")
    print(f"Input:  {args.input}")
    print(f"Output: {args.output}")
    print()

    # Load data
    raw_data = load_csv_files(args.input, args.verbose)

    # Aggregate each configuration
    aggregated = {}
    for config_key, metrics_list in raw_data.items():
        aggregated[config_key] = aggregate_configuration(metrics_list)

    # Write output
    write_aggregated_csv(aggregated, args.output, args.verbose)

    # Summary statistics
    total_samples = sum(s["n_samples"] for s in aggregated.values())
    print(f"Aggregated {total_samples} samples into {len(aggregated)} configurations")
    print(f"Output: {args.output}")

    # Show sample of results
    print("\nSample results (first 5):")
    for i, (key, stats) in enumerate(sorted(aggregated.items())[:5]):
        map_name, scenario, threads, mapsize, pinning = key.split("|")
        ops = stats["ops_per_sec_mean"]
        ci = stats["ops_per_sec_ci95_high"] - stats["ops_per_sec_mean"]
        print(f"  {map_name} {scenario} {threads}t: {ops/1e6:.2f}M ± {ci/1e6:.2f}M ops/sec")


if __name__ == "__main__":
    main()
```

**Make executable:**
```bash
chmod +x scripts/aggregate-results.py
```

---

### Step 6.9: Implement Gnuplot Scripts - Throughput

**File:** `plots/plot-throughput.gnu`

**Tasks:**
- [ ] Create throughput vs threads plot
- [ ] Add error bars for 95% CI
- [ ] Configure styling for publication quality

**Implementation:**
```gnuplot
# plot-throughput.gnu - Throughput vs Thread Count
#
# Usage: gnuplot -e "scenario='read_only'; mapsize=1000000" plots/plot-throughput.gnu

# Default values
if (!exists("scenario")) scenario = "read_only"
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

# Output
set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/throughput_%s_%d_%s.png", scenario, mapsize, pinning)

# Title and labels
set title sprintf("Throughput: %s (mapsize=%d, pinning=%s)", scenario, mapsize, pinning)
set xlabel "Thread Count"
set ylabel "Throughput (Million ops/sec)"

# Grid and styling
set grid
set key top left
set style data linespoints

# X-axis (thread counts)
set xtics (1, 2, 4, 8, 16, 32)
set logscale x 2

# Error bars style
set style line 1 lc rgb '#0072BD' pt 7 ps 1.5 lw 2  # phmap - blue
set style line 2 lc rgb '#D95319' pt 5 ps 1.5 lw 2  # libcuckoo - orange
set style line 3 lc rgb '#77AC30' pt 9 ps 1.5 lw 2  # dashmap - green

# Data file
datafile = "results/aggregated/summary.csv"

# Filter function (gnuplot)
filter_phmap(scen, size, pin) = \
    (strcol(1) eq "parallel-hashmap" && \
     strcol(2) eq scen && \
     column(4) == size && \
     strcol(5) eq pin) ? column(7)/1e6 : 1/0

filter_libcuckoo(scen, size, pin) = \
    (strcol(1) eq "libcuckoo" && \
     strcol(2) eq scen && \
     column(4) == size && \
     strcol(5) eq pin) ? column(7)/1e6 : 1/0

filter_dashmap(scen, size, pin) = \
    (strcol(1) eq "dashmap" && \
     strcol(2) eq scen && \
     column(4) == size && \
     strcol(5) eq pin) ? column(7)/1e6 : 1/0

# Plot with error bars
plot datafile using 3:(filter_phmap(scenario, mapsize, pinning)):(column(10)/1e6):(column(11)/1e6) \
        with yerrorbars ls 1 title "parallel-hashmap", \
     "" using 3:(filter_phmap(scenario, mapsize, pinning)) with lines ls 1 notitle, \
     "" using 3:(filter_libcuckoo(scenario, mapsize, pinning)):(column(10)/1e6):(column(11)/1e6) \
        with yerrorbars ls 2 title "libcuckoo", \
     "" using 3:(filter_libcuckoo(scenario, mapsize, pinning)) with lines ls 2 notitle, \
     "" using 3:(filter_dashmap(scenario, mapsize, pinning)):(column(10)/1e6):(column(11)/1e6) \
        with yerrorbars ls 3 title "DashMap", \
     "" using 3:(filter_dashmap(scenario, mapsize, pinning)) with lines ls 3 notitle
```

---

### Step 6.10: Implement Gnuplot Scripts - Scalability

**File:** `plots/plot-scalability.gnu`

**Tasks:**
- [ ] Create normalized speedup plot
- [ ] Show linear scaling reference line

**Implementation:**
```gnuplot
# plot-scalability.gnu - Scalability (Normalized Speedup)
#
# Usage: gnuplot -e "scenario='insert_only'; mapsize=1000000" plots/plot-scalability.gnu

if (!exists("scenario")) scenario = "insert_only"
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/scalability_%s_%d_%s.png", scenario, mapsize, pinning)

set title sprintf("Scalability: %s (mapsize=%d, pinning=%s)", scenario, mapsize, pinning)
set xlabel "Thread Count"
set ylabel "Speedup (relative to 1 thread)"

set grid
set key top left
set style data linespoints

set xtics (1, 2, 4, 8, 16, 32)
set logscale x 2
set logscale y 2

set style line 1 lc rgb '#0072BD' pt 7 ps 1.5 lw 2
set style line 2 lc rgb '#D95319' pt 5 ps 1.5 lw 2
set style line 3 lc rgb '#77AC30' pt 9 ps 1.5 lw 2
set style line 4 lc rgb '#999999' dt 2 lw 1.5  # Linear scaling reference

datafile = "results/aggregated/summary.csv"

# Reference line: perfect linear scaling
set arrow from 1,1 to 32,32 nohead ls 4

# Plot (would need preprocessing to compute speedup)
# This is a simplified version - actual implementation would use awk preprocessing

plot x title "Linear scaling" ls 4, \
     datafile using 3:($3) with linespoints ls 1 title "parallel-hashmap", \
     "" using 3:($3) with linespoints ls 2 title "libcuckoo", \
     "" using 3:($3) with linespoints ls 3 title "DashMap"
```

---

### Step 6.11: Implement Gnuplot Scripts - Latency CDF

**File:** `plots/plot-latency-cdf.gnu`

**Tasks:**
- [ ] Create latency percentile comparison
- [ ] Show p50, p90, p95, p99

**Implementation:**
```gnuplot
# plot-latency-cdf.gnu - Latency Percentiles Comparison
#
# Usage: gnuplot -e "scenario='read_only'; threads=8; mapsize=1000000" plots/plot-latency-cdf.gnu

if (!exists("scenario")) scenario = "read_only"
if (!exists("threads")) threads = 8
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/latency_%s_%dt_%d_%s.png", scenario, threads, mapsize, pinning)

set title sprintf("Latency Percentiles: %s (%d threads, mapsize=%d)", scenario, threads, mapsize)
set xlabel "Percentile"
set ylabel "Latency (nanoseconds)"

set grid
set key top left
set style data histogram
set style histogram cluster gap 1
set style fill solid 0.8 border -1

set xtics ("p50" 0, "p90" 1, "p95" 2, "p99" 3)

set style line 1 lc rgb '#0072BD'
set style line 2 lc rgb '#D95319'
set style line 3 lc rgb '#77AC30'

# This would require preprocessing the data for histograms
# Simplified placeholder

set boxwidth 0.25
plot "< grep 'parallel-hashmap.*read_only.*8.*1000000.*compact' results/aggregated/summary.csv | head -1" \
        using (0):16:17:18:19 with boxes ls 1 title "parallel-hashmap"
```

---

### Step 6.12: Implement Gnuplot Scripts - Memory

**File:** `plots/plot-memory.gnu`

**Tasks:**
- [ ] Create memory efficiency comparison
- [ ] Show bytes per entry across implementations

**Implementation:**
```gnuplot
# plot-memory.gnu - Memory Efficiency Comparison
#
# Usage: gnuplot plots/plot-memory.gnu

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output "results/plots/memory_efficiency.png"

set title "Memory Efficiency: Bytes per Entry"
set xlabel "Map Size"
set ylabel "Bytes per Entry"

set grid
set key top right
set style data histogram
set style histogram cluster gap 1
set style fill solid 0.8 border -1

set xtics ("100K" 0, "1M" 1, "10M" 2)

set style line 1 lc rgb '#0072BD'
set style line 2 lc rgb '#D95319'
set style line 3 lc rgb '#77AC30'

# Theoretical minimum
set arrow from -0.5,16 to 2.5,16 nohead lc rgb '#FF0000' dt 2 lw 2

set label "Theoretical min (16 bytes)" at 2.6,16 font ',10'

# Would need data extraction/preprocessing
# Placeholder for actual implementation
```

---

### Step 6.13: Implement generate-plots.sh

**File:** `scripts/generate-plots.sh`

**Tasks:**
- [ ] Generate all standard plots
- [ ] Support customization via arguments

**Implementation:**
```bash
#!/bin/bash
# generate-plots.sh - Generate all benchmark plots

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PLOTS_DIR="plots"
OUTPUT_DIR="results/plots"
DATA_FILE="results/aggregated/summary.csv"

mkdir -p "$OUTPUT_DIR"

# Check prerequisites
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Aggregated data not found: $DATA_FILE"
    echo "Run: python scripts/aggregate-results.py"
    exit 1
fi

if ! command -v gnuplot &> /dev/null; then
    echo "ERROR: gnuplot not found"
    echo "Install with: sudo apt install gnuplot"
    exit 1
fi

echo "=== Generating Benchmark Plots ==="
echo ""

# ============================================================================
# Throughput plots for each scenario and map size
# ============================================================================

SCENARIOS="insert_only read_only read_majority_99 read_majority_95 balanced zipfian"
MAP_SIZES="100000 1000000 10000000"
PINNINGS="compact spread"

echo "Generating throughput plots..."
for scenario in $SCENARIOS; do
    for mapsize in $MAP_SIZES; do
        for pinning in $PINNINGS; do
            echo "  $scenario / $mapsize / $pinning"
            gnuplot -e "scenario='$scenario'; mapsize=$mapsize; pinning='$pinning'" \
                "$PLOTS_DIR/plot-throughput.gnu" 2>/dev/null || true
        done
    done
done

# ============================================================================
# Scalability plots
# ============================================================================

echo "Generating scalability plots..."
for scenario in $SCENARIOS; do
    for mapsize in $MAP_SIZES; do
        echo "  $scenario / $mapsize"
        gnuplot -e "scenario='$scenario'; mapsize=$mapsize" \
            "$PLOTS_DIR/plot-scalability.gnu" 2>/dev/null || true
    done
done

# ============================================================================
# Latency plots
# ============================================================================

THREAD_COUNTS="1 4 8 16 32"

echo "Generating latency plots..."
for scenario in $SCENARIOS; do
    for threads in $THREAD_COUNTS; do
        echo "  $scenario / $threads threads"
        gnuplot -e "scenario='$scenario'; threads=$threads; mapsize=1000000" \
            "$PLOTS_DIR/plot-latency-cdf.gnu" 2>/dev/null || true
    done
done

# ============================================================================
# Memory efficiency plot
# ============================================================================

echo "Generating memory efficiency plot..."
gnuplot "$PLOTS_DIR/plot-memory.gnu" 2>/dev/null || true

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=== Plot Generation Complete ==="
PLOT_COUNT=$(ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l)
echo "Generated $PLOT_COUNT plots in $OUTPUT_DIR"
echo ""
echo "Key plots:"
echo "  - Throughput: throughput_<scenario>_<mapsize>_<pinning>.png"
echo "  - Scalability: scalability_<scenario>_<mapsize>_<pinning>.png"
echo "  - Latency: latency_<scenario>_<threads>t_<mapsize>_<pinning>.png"
echo "  - Memory: memory_efficiency.png"
```

**Make executable:**
```bash
chmod +x scripts/generate-plots.sh
```

---

### Step 6.14: Create Quick Analysis Script

**File:** `scripts/quick-analysis.py`

**Purpose:** Generate quick summary statistics and key findings.

**Tasks:**
- [ ] Load aggregated data
- [ ] Find best/worst performers
- [ ] Generate summary report

**Implementation:**
```python
#!/usr/bin/env python3
"""
quick-analysis.py - Generate quick summary of benchmark results
"""

import csv
import sys
from collections import defaultdict
from pathlib import Path


def load_summary(filepath: str):
    """Load aggregated summary CSV."""
    data = []
    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
    return data


def analyze(data):
    """Generate analysis report."""
    print("=" * 60)
    print("  Benchmark Results Summary")
    print("=" * 60)
    print()

    # Group by scenario
    by_scenario = defaultdict(list)
    for row in data:
        by_scenario[row["scenario"]].append(row)

    for scenario, rows in sorted(by_scenario.items()):
        print(f"\n### {scenario.upper()} ###\n")

        # Find best implementation for each thread count
        by_threads = defaultdict(list)
        for row in rows:
            if row["pinning"] == "compact" and row["mapsize"] == "1000000":
                by_threads[int(row["threads"])].append(row)

        for threads, thread_rows in sorted(by_threads.items()):
            best = max(thread_rows, key=lambda r: float(r["ops_per_sec_mean"]))
            ops = float(best["ops_per_sec_mean"]) / 1e6
            ci = (float(best["ops_per_sec_ci95_high"]) - float(best["ops_per_sec_mean"])) / 1e6
            print(f"  {threads:2d} threads: {best['map_name']:20s} {ops:8.2f} ± {ci:.2f} M ops/sec")

    # Overall winner for each scenario (at 16 threads, 1M entries)
    print("\n" + "=" * 60)
    print("  WINNERS (16 threads, 1M entries, compact)")
    print("=" * 60)

    for scenario, rows in sorted(by_scenario.items()):
        relevant = [r for r in rows
                    if r["threads"] == "16"
                    and r["mapsize"] == "1000000"
                    and r["pinning"] == "compact"]
        if relevant:
            best = max(relevant, key=lambda r: float(r["ops_per_sec_mean"]))
            ops = float(best["ops_per_sec_mean"]) / 1e6
            print(f"  {scenario:20s}: {best['map_name']:20s} ({ops:.2f} M ops/sec)")


def main():
    summary_file = "results/aggregated/summary.csv"

    if not Path(summary_file).exists():
        print(f"ERROR: Summary file not found: {summary_file}")
        print("Run: python scripts/aggregate-results.py")
        sys.exit(1)

    data = load_summary(summary_file)
    analyze(data)


if __name__ == "__main__":
    main()
```

**Make executable:**
```bash
chmod +x scripts/quick-analysis.py
```

---

### Step 6.15: Create Full Pipeline Script

**File:** `scripts/run-full-pipeline.sh`

**Purpose:** Run complete benchmark pipeline end-to-end.

**Tasks:**
- [ ] Validate prerequisites
- [ ] Run experiments
- [ ] Aggregate results
- [ ] Generate plots
- [ ] Produce summary

**Implementation:**
```bash
#!/bin/bash
# run-full-pipeline.sh - Complete benchmark pipeline

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  Concurrent HashMap Benchmark Pipeline"
echo "=============================================="
echo ""

# Step 1: Validate
echo "[1/5] Running validations..."
./scripts/validation/run_all_validations.sh || {
    echo "Validation failed. Fix issues before running experiments."
    exit 1
}
echo ""

# Step 2: Run experiments
echo "[2/5] Running experiments..."
./scripts/run-experiments.sh "$@"
echo ""

# Step 3: Aggregate results
echo "[3/5] Aggregating results..."
python scripts/aggregate-results.py
echo ""

# Step 4: Generate plots
echo "[4/5] Generating plots..."
./scripts/generate-plots.sh
echo ""

# Step 5: Quick analysis
echo "[5/5] Generating summary..."
python scripts/quick-analysis.py
echo ""

echo "=============================================="
echo "  Pipeline Complete"
echo "=============================================="
echo ""
echo "Results:"
echo "  Raw data:    results/raw/"
echo "  Aggregated:  results/aggregated/summary.csv"
echo "  Plots:       results/plots/"
echo "  Metadata:    results/system_metadata.json"
```

**Make executable:**
```bash
chmod +x scripts/run-full-pipeline.sh
```

---

## Verification Checklist

- [ ] run-experiments.sh executes without errors
- [ ] Checkpoint/resume works correctly
- [ ] aggregate-results.py produces valid statistics
- [ ] 95% CI calculations are correct
- [ ] gnuplot scripts generate valid images
- [ ] generate-plots.sh creates all expected plots
- [ ] quick-analysis.py shows meaningful summaries

## Files Created

| File | Purpose | Lines (approx) |
|------|---------|----------------|
| `scripts/run-experiments.sh` | Experiment orchestration | ~300 |
| `scripts/aggregate-results.py` | Statistical analysis | ~200 |
| `scripts/generate-plots.sh` | Plot generation wrapper | ~100 |
| `scripts/quick-analysis.py` | Quick summary report | ~80 |
| `scripts/run-full-pipeline.sh` | End-to-end automation | ~50 |
| `plots/plot-throughput.gnu` | Throughput vs threads | ~50 |
| `plots/plot-scalability.gnu` | Normalized speedup | ~40 |
| `plots/plot-latency-cdf.gnu` | Latency percentiles | ~40 |
| `plots/plot-memory.gnu` | Memory efficiency | ~30 |

## Usage Examples

```bash
# Full benchmark (24-36 hours)
./scripts/run-experiments.sh

# Quick test (30 minutes)
./scripts/run-experiments.sh --quick

# Dry run (show experiment matrix)
./scripts/run-experiments.sh --dry-run

# Single implementation
./scripts/run-experiments.sh --single-impl dashmap

# Single scenario
./scripts/run-experiments.sh --single-scenario read_only

# Resume interrupted run
./scripts/run-experiments.sh --resume

# Aggregate results
python scripts/aggregate-results.py

# Generate plots
./scripts/generate-plots.sh

# Full pipeline
./scripts/run-full-pipeline.sh --quick
```

## Output Files

| File | Description |
|------|-------------|
| `results/raw/*.csv` | Per-trial raw data |
| `results/aggregated/summary.csv` | Aggregated statistics |
| `results/plots/*.png` | Generated visualizations |
| `results/system_metadata.json` | System configuration |
| `results/logs/*.log` | Benchmark execution logs |
| `results/.checkpoint` | Resume checkpoint file |

## Statistical Output Format

The aggregated CSV includes:
- `ops_per_sec_mean`: Sample mean throughput
- `ops_per_sec_std`: Sample standard deviation
- `ops_per_sec_se`: Standard error (s/√n)
- `ops_per_sec_ci95_low`: Lower bound of 95% CI
- `ops_per_sec_ci95_high`: Upper bound of 95% CI
- Similar fields for latency metrics

## Project Complete

With Phase 6 complete, the benchmark framework is fully implemented:

1. **Phase 1**: Build infrastructure (CMake, dependencies)
2. **Phase 2**: Common headers (PRNG, timing, hasher, etc.)
3. **Phase 3**: C++ benchmarks (phmap, libcuckoo)
4. **Phase 4**: Rust benchmark (DashMap)
5. **Phase 5**: Validation suite
6. **Phase 6**: Orchestration and analysis pipeline

To run the complete benchmark:
```bash
./scripts/run-full-pipeline.sh
```
