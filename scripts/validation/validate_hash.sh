#!/bin/bash
# validate_hash.sh - Verify hash functions match across implementations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

echo "=== Hash Function Validation ==="

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

# Generate hash outputs
echo "Generating C++ (phmap) hashes..."
./build/cpp-impl/bench-phmap --verify-hash > /tmp/hash_phmap.txt

echo "Generating C++ (libcuckoo) hashes..."
./build/cpp-impl/bench-libcuckoo --verify-hash > /tmp/hash_libcuckoo.txt

echo "Generating Rust (dashmap) hashes..."
./rust-impl/target/release/bench-dashmap --verify-hash > /tmp/hash_dashmap.txt

# Compare
echo ""
echo "Comparing hash values..."

PASS=true

if ! diff -q /tmp/hash_phmap.txt /tmp/hash_libcuckoo.txt > /dev/null 2>&1; then
    echo "FAIL: phmap vs libcuckoo hash mismatch"
    diff /tmp/hash_phmap.txt /tmp/hash_libcuckoo.txt
    PASS=false
fi

if ! diff -q /tmp/hash_phmap.txt /tmp/hash_dashmap.txt > /dev/null 2>&1; then
    echo "FAIL: phmap vs dashmap hash mismatch"
    diff /tmp/hash_phmap.txt /tmp/hash_dashmap.txt
    PASS=false
fi

if $PASS; then
    echo "PASS: All hash functions match"
    echo ""
    echo "Hash values:"
    cat /tmp/hash_phmap.txt
    exit 0
else
    echo ""
    echo "Hash validation FAILED"
    exit 1
fi
