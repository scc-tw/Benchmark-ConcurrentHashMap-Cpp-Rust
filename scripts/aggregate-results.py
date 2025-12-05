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
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

try:
    import numpy as np
except ImportError:
    print("ERROR: NumPy is required. Install with: pip install numpy")
    sys.exit(1)

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


# ============================================================================
# Data Loading
# ============================================================================

def parse_row_with_core_mapping(line: str, header_parts: List[str]) -> dict:
    """
    Parse a CSV row that may contain comma-separated core_mapping values.
    The core_mapping field contains values like "0,1,2,3" without quotes.
    We handle this by parsing from known positions.
    """
    parts = line.strip().split(',')

    # Header positions (0-based)
    # Core positions that don't shift:
    # 0: run_id, 1: map_name, 2: map_version, 3: scenario, 4: thread_count,
    # 5: map_size, 6: ops_per_trial, 7: repeat_index, 8: seed, 9+: core_mapping...
    #
    # From the end (negative indexing):
    # -1: notes, -2: allocation_node, -3: pinning_strategy, -4: numa_nodes,
    # -5: overhead_ratio, -6: bytes_per_entry, -7: current_rss_kb, -8: peak_rss_kb,
    # -9: sampled_ops_count, -10: max_sample_latency_ns, -11: p99_latency_ns,
    # -12: p95_latency_ns, -13: p90_latency_ns, -14: p50_latency_ns,
    # -15: mean_sample_latency_ns, -16: ops_per_sec, -17: duration_ns

    result = {}
    result["map_name"] = parts[1]
    result["scenario"] = parts[3]
    result["thread_count"] = parts[4]
    result["map_size"] = parts[5]

    # Parse from end
    result["notes"] = parts[-1]
    result["allocation_node"] = parts[-2]
    result["pinning_strategy"] = parts[-3]
    result["numa_nodes"] = parts[-4]
    result["overhead_ratio"] = parts[-5]
    result["bytes_per_entry"] = parts[-6]
    result["current_rss_kb"] = parts[-7]
    result["peak_rss_kb"] = parts[-8]
    result["sampled_ops_count"] = parts[-9]
    result["max_sample_latency_ns"] = parts[-10]
    result["p99_latency_ns"] = parts[-11]
    result["p95_latency_ns"] = parts[-12]
    result["p90_latency_ns"] = parts[-13]
    result["p50_latency_ns"] = parts[-14]
    result["mean_sample_latency_ns"] = parts[-15]
    result["ops_per_sec"] = parts[-16]
    result["duration_ns"] = parts[-17]

    return result


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
            lines = f.readlines()
            if len(lines) < 2:
                continue

            header_parts = lines[0].strip().split(',')

            for line in lines[1:]:
                try:
                    row = parse_row_with_core_mapping(line, header_parts)

                    # Extract key fields
                    map_name = row["map_name"]
                    scenario = row["scenario"]
                    threads = int(row["thread_count"])
                    mapsize = int(row["map_size"])
                    pinning = row["pinning_strategy"]

                    # Create configuration key
                    config_key = f"{map_name}|{scenario}|{threads}|{mapsize}|{pinning}"

                    # Extract metrics
                    metrics = {
                        "ops_per_sec": float(row["ops_per_sec"]),
                        "mean_latency_ns": float(row["mean_sample_latency_ns"]),
                        "p50_latency_ns": int(row["p50_latency_ns"]),
                        "p90_latency_ns": int(row["p90_latency_ns"]),
                        "p95_latency_ns": int(row["p95_latency_ns"]),
                        "p99_latency_ns": int(row["p99_latency_ns"]),
                        "peak_rss_kb": int(row["peak_rss_kb"]),
                        "current_rss_kb": int(row["current_rss_kb"]),
                        "bytes_per_entry": float(row["bytes_per_entry"]),
                        "overhead_ratio": float(row["overhead_ratio"]),
                    }

                    data[config_key].append(metrics)

                except (ValueError, KeyError, IndexError) as e:
                    if verbose:
                        print(f"    Warning: Skipping row: {e}")
                    continue

    if verbose:
        print(f"Loaded {sum(len(v) for v in data.values())} data points")
        print(f"Unique configurations: {len(data)}")

    return data


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

    if not raw_data:
        print("No data to aggregate.")
        sys.exit(1)

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
