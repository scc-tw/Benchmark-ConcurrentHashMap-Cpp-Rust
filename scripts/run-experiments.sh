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

# ============================================================================
# Generate Experiment Matrix
# ============================================================================

generate_experiment_matrix() {
    local idx=0

    for impl in $IMPLEMENTATIONS; do
        for scenario in $SCENARIOS; do
            for mapsize in $MAP_SIZES; do
                for threads in $THREAD_COUNTS; do
                    for pinning in $PINNING_STRATEGIES; do
                        echo "$idx|$impl|$scenario|$mapsize|$threads|$pinning"
                        idx=$((idx + 1))
                    done
                done
            done
        done
    done
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
    "hostname": "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo 'unknown')",
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

    # Use temp file instead of process substitution for better compatibility
    local tmp_matrix=$(mktemp)
    generate_experiment_matrix > "$tmp_matrix"
    mapfile -t EXPERIMENTS < "$tmp_matrix"
    rm -f "$tmp_matrix"

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

    # Check CPU governor (only warn in interactive mode)
    local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    if [ "$governor" != "performance" ] && [ "$governor" != "unknown" ]; then
        echo "WARNING: CPU governor is '$governor', not 'performance'"
        echo "For accurate results, run: sudo cpupower frequency-set -g performance"
        if [ -t 0 ]; then
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo "Non-interactive mode, continuing anyway..."
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
        current=$((current + 1))

        # Parse experiment
        IFS='|' read -r idx impl scenario mapsize threads pinning <<< "$exp"
        local exp_id="${impl}_${scenario}_${mapsize}_${threads}_${pinning}"

        # Skip if already completed (resume mode)
        if $RESUME && is_completed "$exp_id"; then
            continue
        fi

        # Progress
        local elapsed=$(( $(date +%s) - start_time ))
        local remaining=$(( TOTAL_EXPERIMENTS - current ))
        local eta="?"
        if [ $current -gt 0 ] && [ $elapsed -gt 0 ]; then
            # Simple integer ETA calculation (seconds per experiment * remaining)
            local secs_per_exp=$(( elapsed / current ))
            eta=$(( (remaining * secs_per_exp) / 60 ))
        fi

        printf "\r[%d/%d] %s %s threads=%s mapsize=%s pinning=%s (ETA: %sm)     " \
            "$current" "$TOTAL_EXPERIMENTS" "$impl" "$scenario" "$threads" "$mapsize" "$pinning" "$eta"

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
