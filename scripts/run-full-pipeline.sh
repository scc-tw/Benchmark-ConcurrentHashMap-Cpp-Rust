#!/bin/bash
# run-full-pipeline.sh - Complete benchmark pipeline

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=============================================="
echo "  Concurrent HashMap Benchmark Pipeline"
echo "=============================================="
echo ""

# Parse arguments to pass to run-experiments.sh
EXPERIMENT_ARGS=""
SKIP_VALIDATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        *)
            EXPERIMENT_ARGS="$EXPERIMENT_ARGS $1"
            shift
            ;;
    esac
done

# Step 1: Validate
if ! $SKIP_VALIDATION; then
    echo "[1/5] Running validations..."
    if [ -f "./scripts/validation/run_all_validations.sh" ]; then
        ./scripts/validation/run_all_validations.sh || {
            echo "Validation failed. Fix issues before running experiments."
            echo "Or use --skip-validation to bypass."
            exit 1
        }
    else
        echo "  Validation scripts not found, skipping..."
    fi
    echo ""
else
    echo "[1/5] Skipping validation (--skip-validation)"
    echo ""
fi

# Step 2: Run experiments
echo "[2/5] Running experiments..."
./scripts/run-experiments.sh $EXPERIMENT_ARGS
echo ""

# Step 3: Aggregate results
echo "[3/5] Aggregating results..."
python3 scripts/aggregate-results.py
echo ""

# Step 4: Generate plots
echo "[4/5] Generating plots..."
if command -v gnuplot &> /dev/null; then
    ./scripts/generate-plots.sh
else
    echo "  gnuplot not found, skipping plot generation"
    echo "  Install with: sudo apt install gnuplot"
fi
echo ""

# Step 5: Quick analysis
echo "[5/5] Generating summary..."
python3 scripts/quick-analysis.py
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
