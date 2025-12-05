#!/bin/bash
# validate_memory.sh - Verify memory measurements are correct

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

echo "=== Memory Measurement Validation ==="

MAPSIZE=100000  # 100K entries
THREADS=1
REPEATS=1

# Expected: ~1.6MB minimum (100K * 16 bytes)
MIN_RSS_KB=1000   # 1MB minimum
MAX_RSS_KB=100000 # 100MB maximum (allows for overhead)

PASS=true

for impl in phmap libcuckoo dashmap; do
    echo ""
    echo "--- Testing $impl ---"

    if [ "$impl" = "phmap" ]; then
        BIN="./build/cpp-impl/bench-phmap"
    elif [ "$impl" = "libcuckoo" ]; then
        BIN="./build/cpp-impl/bench-libcuckoo"
    else
        BIN="./rust-impl/target/release/bench-dashmap"
    fi

    if [ ! -x "$BIN" ]; then
        echo "ERROR: Binary not found: $BIN"
        PASS=false
        continue
    fi

    OUTPUT=$($BIN --scenario insert_only --threads $THREADS --mapsize $MAPSIZE --repeats $REPEATS 2>/dev/null)

    # Extract memory columns (peak_rss_kb is column 20, current_rss_kb is 21)
    DATA=$(echo "$OUTPUT" | tail -1)
    PEAK_RSS=$(echo "$DATA" | cut -d',' -f20)
    CURRENT_RSS=$(echo "$DATA" | cut -d',' -f21)
    BYTES_PER_ENTRY=$(echo "$DATA" | cut -d',' -f22)
    OVERHEAD_RATIO=$(echo "$DATA" | cut -d',' -f23)

    echo "  peak_rss_kb: $PEAK_RSS"
    echo "  current_rss_kb: $CURRENT_RSS"
    echo "  bytes_per_entry: $BYTES_PER_ENTRY"
    echo "  overhead_ratio: $OVERHEAD_RATIO"

    # Validate peak RSS is a number
    if ! echo "$PEAK_RSS" | grep -qE '^-?[0-9]+$'; then
        echo "  FAIL: peak_rss not a valid number"
        PASS=false
        continue
    fi

    # Validate peak RSS range
    if [ "$PEAK_RSS" -lt "$MIN_RSS_KB" ] 2>/dev/null; then
        echo "  FAIL: peak_rss too low ($PEAK_RSS < $MIN_RSS_KB)"
        PASS=false
    elif [ "$PEAK_RSS" -gt "$MAX_RSS_KB" ] 2>/dev/null; then
        echo "  FAIL: peak_rss too high ($PEAK_RSS > $MAX_RSS_KB)"
        PASS=false
    else
        echo "  peak_rss: OK"
    fi

    # Validate bytes_per_entry (should be 16-200 bytes typically)
    BPE_INT=$(printf '%.0f' "$BYTES_PER_ENTRY" 2>/dev/null || echo "0")
    if [ "$BPE_INT" -lt 16 ] || [ "$BPE_INT" -gt 200 ]; then
        echo "  WARN: bytes_per_entry unusual ($BYTES_PER_ENTRY)"
    else
        echo "  bytes_per_entry: OK"
    fi
done

echo ""
if $PASS; then
    echo "=== Memory validation PASSED ==="
    exit 0
else
    echo "=== Memory validation FAILED ==="
    exit 1
fi
