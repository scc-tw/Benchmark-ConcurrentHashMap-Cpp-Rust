#!/bin/bash
# validate_prng.sh - Verify PRNG sequences match across implementations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

SEED=${1:-42}

echo "=== PRNG Validation (seed=$SEED) ==="

# Check binaries exist
if [ ! -x "build/cpp-impl/bench-phmap" ]; then
    echo "ERROR: build/cpp-impl/bench-phmap not found"
    exit 1
fi
if [ ! -x "build/cpp-impl/bench-libcuckoo" ]; then
    echo "ERROR: build/cpp-impl/bench-libcuckoo not found"
    exit 1
fi
if [ ! -x "rust-impl/target/release/bench-dashmap" ]; then
    echo "ERROR: rust-impl/target/release/bench-dashmap not found"
    exit 1
fi

# Generate sequences
echo "Generating C++ (phmap) sequence..."
./build/cpp-impl/bench-phmap --verify-prng --seed $SEED > /tmp/prng_phmap.txt

echo "Generating C++ (libcuckoo) sequence..."
./build/cpp-impl/bench-libcuckoo --verify-prng --seed $SEED > /tmp/prng_libcuckoo.txt

echo "Generating Rust (dashmap) sequence..."
./rust-impl/target/release/bench-dashmap --verify-prng --seed $SEED > /tmp/prng_dashmap.txt

# Compare
echo ""
echo "Comparing sequences..."

PASS=true

if ! diff -q /tmp/prng_phmap.txt /tmp/prng_libcuckoo.txt > /dev/null 2>&1; then
    echo "FAIL: phmap vs libcuckoo PRNG mismatch"
    diff /tmp/prng_phmap.txt /tmp/prng_libcuckoo.txt | head -20
    PASS=false
fi

if ! diff -q /tmp/prng_phmap.txt /tmp/prng_dashmap.txt > /dev/null 2>&1; then
    echo "FAIL: phmap vs dashmap PRNG mismatch"
    diff /tmp/prng_phmap.txt /tmp/prng_dashmap.txt | head -20
    PASS=false
fi

if $PASS; then
    echo "PASS: All PRNG sequences match"
    echo ""
    echo "First 7 lines:"
    head -7 /tmp/prng_phmap.txt
    exit 0
else
    echo ""
    echo "PRNG validation FAILED"
    exit 1
fi
