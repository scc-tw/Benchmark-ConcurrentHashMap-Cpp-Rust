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
        for pinning in $PINNINGS; do
            echo "  $scenario / $mapsize / $pinning"
            gnuplot -e "scenario='$scenario'; mapsize=$mapsize; pinning='$pinning'" \
                "$PLOTS_DIR/plot-scalability.gnu" 2>/dev/null || true
        done
    done
done

# ============================================================================
# Latency plots
# ============================================================================

THREAD_COUNTS="1 4 8 16 32"

echo "Generating latency plots..."
for scenario in $SCENARIOS; do
    for threads in $THREAD_COUNTS; do
        for pinning in $PINNINGS; do
            echo "  $scenario / $threads threads / $pinning"
            gnuplot -e "scenario='$scenario'; threads=$threads; mapsize=1000000; pinning='$pinning'" \
                "$PLOTS_DIR/plot-latency.gnu" 2>/dev/null || true
        done
    done
done

# ============================================================================
# Memory efficiency plot
# ============================================================================

echo "Generating memory efficiency plots..."
for threads in 1 8; do
    for pinning in $PINNINGS; do
        echo "  $threads threads / $pinning"
        gnuplot -e "threads=$threads; pinning='$pinning'" \
            "$PLOTS_DIR/plot-memory.gnu" 2>/dev/null || true
    done
done

# ============================================================================
# Comparison plots
# ============================================================================

echo "Generating comparison plots..."
for threads in $THREAD_COUNTS; do
    for mapsize in $MAP_SIZES; do
        for pinning in $PINNINGS; do
            echo "  $threads threads / $mapsize / $pinning"
            gnuplot -e "threads=$threads; mapsize=$mapsize; pinning='$pinning'" \
                "$PLOTS_DIR/plot-comparison.gnu" 2>/dev/null || true
        done
    done
done

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
echo "  - Memory: memory_efficiency_<threads>t_<pinning>.png"
echo "  - Comparison: comparison_<threads>t_<mapsize>_<pinning>.png"
