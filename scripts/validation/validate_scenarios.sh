#!/bin/bash
# validate_scenarios.sh - Verify all scenarios run correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

SCENARIOS="insert_only read_only read_majority_99 read_majority_95 balanced zipfian resize_stress sequential_keys random_keys"
IMPLEMENTATIONS="phmap libcuckoo dashmap"
THREADS=2
MAPSIZE=10000
REPEATS=2

echo "=== Scenario Correctness Validation ==="
echo "Testing with threads=$THREADS, mapsize=$MAPSIZE, repeats=$REPEATS"
echo ""

PASS=true
FAILED_TESTS=""

for impl in $IMPLEMENTATIONS; do
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

    for scenario in $SCENARIOS; do
        echo -n "  $scenario: "

        OUTPUT=$($BIN --scenario $scenario --threads $THREADS --mapsize $MAPSIZE --repeats $REPEATS 2>/dev/null)
        EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
            echo "FAIL (exit code $EXIT_CODE)"
            PASS=false
            FAILED_TESTS="$FAILED_TESTS $impl:$scenario"
            continue
        fi

        # Check we got output (header + data rows)
        LINES=$(echo "$OUTPUT" | wc -l)
        EXPECTED=$((REPEATS + 1))  # header + data rows

        if [ "$LINES" -lt "$EXPECTED" ]; then
            echo "FAIL (expected $EXPECTED lines, got $LINES)"
            PASS=false
            FAILED_TESTS="$FAILED_TESTS $impl:$scenario"
            continue
        fi

        # Extract ops_per_sec from last data row (column 12)
        OPS_PER_SEC=$(echo "$OUTPUT" | tail -1 | cut -d',' -f12)

        # Check it's a positive number
        if ! echo "$OPS_PER_SEC" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
            echo "FAIL (invalid ops_per_sec: $OPS_PER_SEC)"
            PASS=false
            FAILED_TESTS="$FAILED_TESTS $impl:$scenario"
            continue
        fi

        # Check ops_per_sec is reasonable (> 1000)
        OPS_INT=$(printf '%.0f' "$OPS_PER_SEC" 2>/dev/null || echo "0")
        if [ "$OPS_INT" -lt 1000 ]; then
            echo "WARN (very low ops_per_sec: $OPS_PER_SEC)"
        else
            echo "PASS (ops/sec: $(printf '%.0f' $OPS_PER_SEC))"
        fi
    done
    echo ""
done

if $PASS; then
    echo "=== All scenario tests PASSED ==="
    exit 0
else
    echo "=== Scenario tests FAILED ==="
    echo "Failed tests:$FAILED_TESTS"
    exit 1
fi
