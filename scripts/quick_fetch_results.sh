#!/bin/bash
set -e

# Configuration
RESULTS_DIR="results/quick_fetch"
mkdir -p "$RESULTS_DIR"
OUTPUT_FILE="$RESULTS_DIR/results.csv"
rm -f "$OUTPUT_FILE"

# Executables
PHMAP_BIN="./build/cpp-impl/bench-phmap"
LIBCUCKOO_BIN="./build/cpp-impl/bench-libcuckoo"
DASHMAP_BIN="./rust-impl/target/release/bench-dashmap"

# Verify executables exist
if [ ! -f "$PHMAP_BIN" ]; then echo "Error: $PHMAP_BIN not found"; exit 1; fi
if [ ! -f "$LIBCUCKOO_BIN" ]; then echo "Error: $LIBCUCKOO_BIN not found"; exit 1; fi
if [ ! -f "$DASHMAP_BIN" ]; then echo "Error: $DASHMAP_BIN not found"; exit 1; fi

# Experiment Matrix
SCENARIOS=("insert_only" "read_only" "read_majority_99" "read_majority_95" "balanced" "zipfian" "resize_stress" "sequential_keys" "random_keys")
MAP_SIZES=(100000 1000000 10000000)

# Threads: 1, 2, 4, 8, N_cores
# Get number of cores
N_CORES=$(nproc)
# Construct thread list. We use a simple array and sort -u later if needed, 
# but bash array deduplication is annoying. 
# Let's just define the list explicitly.
THREADS_LIST="1 2 4 8 $N_CORES"
# Convert to array and dedup
read -r -a THREADS <<< "$(echo "$THREADS_LIST" | tr ' ' '\n' | sort -nu | tr '\n' ' ')"

PINNING_STRATEGIES=("compact" "spread")

REPEATS=1

# Helper function to run benchmark
run_bench() {
    local map_name=$1
    local bin=$2
    local scenario=$3
    local threads=$4
    local map_size=$5
    local pinning=$6
    
    echo "[$(date +'%H:%M:%S')] Running $map_name: scenario=$scenario threads=$threads mapsize=$map_size pinning=$pinning"
    
    # Use a temporary file for output to handle header logic
    local tmp_out=$(mktemp)
    
    $bin \
        --scenario "$scenario" \
        --threads "$threads" \
        --mapsize "$map_size" \
        --repeats "$REPEATS" \
        --pinning "$pinning" \
        --output "$tmp_out"
        
    # Append to main output file
    if [ ! -s "$OUTPUT_FILE" ]; then
        # First run, keep header
        cat "$tmp_out" > "$OUTPUT_FILE"
    else
        # Subsequent runs, skip header
        tail -n +2 "$tmp_out" >> "$OUTPUT_FILE"
    fi
    
    rm "$tmp_out"
}

echo "Starting benchmarks..."
echo "Results will be saved to $OUTPUT_FILE"

# Loop through matrix
for scenario in "${SCENARIOS[@]}"; do
    for map_size in "${MAP_SIZES[@]}"; do
        for threads in "${THREADS[@]}"; do
            for pinning in "${PINNING_STRATEGIES[@]}"; do
                
                # phmap
                run_bench "phmap" "$PHMAP_BIN" "$scenario" "$threads" "$map_size" "$pinning"
                
                # libcuckoo
                run_bench "libcuckoo" "$LIBCUCKOO_BIN" "$scenario" "$threads" "$map_size" "$pinning"
                
                # dashmap
                run_bench "dashmap" "$DASHMAP_BIN" "$scenario" "$threads" "$map_size" "$pinning"
                
            done
        done
    done
done

echo "Benchmark completed. Results in $OUTPUT_FILE"
