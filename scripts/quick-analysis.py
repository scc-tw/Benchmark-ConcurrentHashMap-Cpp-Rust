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
    print("=" * 70)
    print("  Concurrent HashMap Benchmark Results Summary")
    print("=" * 70)
    print()

    # Group by scenario
    by_scenario = defaultdict(list)
    for row in data:
        by_scenario[row["scenario"]].append(row)

    # Summary table header
    print(f"{'Scenario':<20} {'Threads':>8} {'Winner':<20} {'Ops/sec':>12} {'± 95% CI':>10}")
    print("-" * 70)

    for scenario, rows in sorted(by_scenario.items()):
        # Find best implementation for 1, 8, and 16 threads at 1M entries
        for target_threads in [1, 8, 16]:
            relevant = [r for r in rows
                       if int(r["threads"]) == target_threads
                       and r["mapsize"] == "1000000"
                       and r["pinning"] == "compact"]

            if relevant:
                best = max(relevant, key=lambda r: float(r["ops_per_sec_mean"]))
                ops = float(best["ops_per_sec_mean"]) / 1e6
                ci = (float(best["ops_per_sec_ci95_high"]) - float(best["ops_per_sec_mean"])) / 1e6

                if target_threads == 1:
                    print(f"{scenario:<20} {target_threads:>8} {best['map_name']:<20} {ops:>10.2f}M {ci:>8.2f}M")
                else:
                    print(f"{'':<20} {target_threads:>8} {best['map_name']:<20} {ops:>10.2f}M {ci:>8.2f}M")
        print()

    # Overall winners section
    print()
    print("=" * 70)
    print("  PERFORMANCE LEADERS (16 threads, 1M entries, compact)")
    print("=" * 70)
    print()

    print(f"{'Scenario':<25} {'Winner':<20} {'Throughput':>15}")
    print("-" * 60)

    winners = defaultdict(int)
    for scenario, rows in sorted(by_scenario.items()):
        relevant = [r for r in rows
                   if r["threads"] == "16"
                   and r["mapsize"] == "1000000"
                   and r["pinning"] == "compact"]
        if relevant:
            best = max(relevant, key=lambda r: float(r["ops_per_sec_mean"]))
            ops = float(best["ops_per_sec_mean"]) / 1e6
            print(f"{scenario:<25} {best['map_name']:<20} {ops:>12.2f} M/s")
            winners[best["map_name"]] += 1

    print()
    print("-" * 60)
    print("Win counts:")
    for impl, count in sorted(winners.items(), key=lambda x: -x[1]):
        print(f"  {impl}: {count} scenarios")

    # Memory efficiency section
    print()
    print("=" * 70)
    print("  MEMORY EFFICIENCY (bytes per entry)")
    print("=" * 70)
    print()

    print(f"{'Implementation':<25} {'100K':>12} {'1M':>12} {'10M':>12}")
    print("-" * 60)

    for impl in ["parallel-hashmap", "libcuckoo", "dashmap"]:
        row_100k = next((r for r in data if r["map_name"] == impl
                        and r["scenario"] == "insert_only"
                        and r["mapsize"] == "100000"
                        and r["threads"] == "1"
                        and r["pinning"] == "compact"), None)
        row_1m = next((r for r in data if r["map_name"] == impl
                      and r["scenario"] == "insert_only"
                      and r["mapsize"] == "1000000"
                      and r["threads"] == "1"
                      and r["pinning"] == "compact"), None)
        row_10m = next((r for r in data if r["map_name"] == impl
                       and r["scenario"] == "insert_only"
                       and r["mapsize"] == "10000000"
                       and r["threads"] == "1"
                       and r["pinning"] == "compact"), None)

        bpe_100k = f"{float(row_100k['bytes_per_entry']):.1f}" if row_100k else "N/A"
        bpe_1m = f"{float(row_1m['bytes_per_entry']):.1f}" if row_1m else "N/A"
        bpe_10m = f"{float(row_10m['bytes_per_entry']):.1f}" if row_10m else "N/A"

        print(f"{impl:<25} {bpe_100k:>12} {bpe_1m:>12} {bpe_10m:>12}")

    print()
    print("Note: Theoretical minimum is 16 bytes (u64 key + u64 value)")

    # Latency section
    print()
    print("=" * 70)
    print("  LATENCY PERCENTILES (read_only, 8 threads, 1M entries, ns)")
    print("=" * 70)
    print()

    print(f"{'Implementation':<25} {'p50':>10} {'p90':>10} {'p95':>10} {'p99':>10}")
    print("-" * 60)

    for impl in ["parallel-hashmap", "libcuckoo", "dashmap"]:
        row = next((r for r in data if r["map_name"] == impl
                   and r["scenario"] == "read_only"
                   and r["threads"] == "8"
                   and r["mapsize"] == "1000000"
                   and r["pinning"] == "compact"), None)

        if row:
            print(f"{impl:<25} {row['p50_latency_ns']:>10} {row['p90_latency_ns']:>10} "
                  f"{row['p95_latency_ns']:>10} {row['p99_latency_ns']:>10}")
        else:
            print(f"{impl:<25} {'N/A':>10} {'N/A':>10} {'N/A':>10} {'N/A':>10}")


def main():
    summary_file = "results/aggregated/summary.csv"

    if not Path(summary_file).exists():
        print(f"ERROR: Summary file not found: {summary_file}")
        print("Run: python scripts/aggregate-results.py")
        sys.exit(1)

    data = load_summary(summary_file)
    if not data:
        print("ERROR: No data in summary file")
        sys.exit(1)

    analyze(data)


if __name__ == "__main__":
    main()
