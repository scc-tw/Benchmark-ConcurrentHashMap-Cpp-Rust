#!/bin/bash
# run_all_validations.sh - Run all validation tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

echo "========================================"
echo "  Concurrent HashMap Benchmark Validation"
echo "========================================"
echo ""

PASS=true

# 1. PRNG Validation
echo ">>> Running PRNG validation..."
if ! "$SCRIPT_DIR/validate_prng.sh"; then
    PASS=false
fi
echo ""

# 2. Hash Validation
echo ">>> Running Hash validation..."
if ! "$SCRIPT_DIR/validate_hash.sh"; then
    PASS=false
fi
echo ""

# 3. CSV Format Validation
echo ">>> Running CSV format validation..."
if ! "$SCRIPT_DIR/validate_csv.sh"; then
    PASS=false
fi
echo ""

# 4. Scenario Correctness
echo ">>> Running Scenario correctness validation..."
if ! "$SCRIPT_DIR/validate_scenarios.sh"; then
    PASS=false
fi
echo ""

# 5. Memory Measurement
echo ">>> Running Memory measurement validation..."
if ! "$SCRIPT_DIR/validate_memory.sh"; then
    PASS=false
fi
echo ""

echo "========================================"
if $PASS; then
    echo "  ALL VALIDATIONS PASSED"
    echo "========================================"
    exit 0
else
    echo "  SOME VALIDATIONS FAILED"
    echo "========================================"
    exit 1
fi
