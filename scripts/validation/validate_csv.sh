#!/bin/bash
# validate_csv.sh - Verify CSV output format consistency

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

echo "=== CSV Format Validation ==="

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

# Run minimal benchmarks to generate CSV
echo "Running phmap..."
./build/cpp-impl/bench-phmap --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_phmap.csv 2>/dev/null

echo "Running libcuckoo..."
./build/cpp-impl/bench-libcuckoo --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_libcuckoo.csv 2>/dev/null

echo "Running dashmap..."
./rust-impl/target/release/bench-dashmap --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_dashmap.csv 2>/dev/null

# Extract and compare headers
echo ""
echo "Comparing CSV headers..."

HEADER_PHMAP=$(head -1 /tmp/csv_phmap.csv)
HEADER_LIBCUCKOO=$(head -1 /tmp/csv_libcuckoo.csv)
HEADER_DASHMAP=$(head -1 /tmp/csv_dashmap.csv)

PASS=true

if [ "$HEADER_PHMAP" != "$HEADER_LIBCUCKOO" ]; then
    echo "FAIL: phmap vs libcuckoo header mismatch"
    echo "phmap:     $HEADER_PHMAP"
    echo "libcuckoo: $HEADER_LIBCUCKOO"
    PASS=false
fi

if [ "$HEADER_PHMAP" != "$HEADER_DASHMAP" ]; then
    echo "FAIL: phmap vs dashmap header mismatch"
    echo "phmap:   $HEADER_PHMAP"
    echo "dashmap: $HEADER_DASHMAP"
    PASS=false
fi

# Count columns
COLS_PHMAP=$(echo "$HEADER_PHMAP" | tr ',' '\n' | wc -l)
COLS_LIBCUCKOO=$(echo "$HEADER_LIBCUCKOO" | tr ',' '\n' | wc -l)
COLS_DASHMAP=$(echo "$HEADER_DASHMAP" | tr ',' '\n' | wc -l)

echo ""
echo "Column counts: phmap=$COLS_PHMAP, libcuckoo=$COLS_LIBCUCKOO, dashmap=$COLS_DASHMAP"

if [ "$COLS_PHMAP" != "$COLS_LIBCUCKOO" ] || [ "$COLS_PHMAP" != "$COLS_DASHMAP" ]; then
    echo "FAIL: Column count mismatch"
    PASS=false
fi

# Verify data row exists and has correct column count
DATA_PHMAP=$(tail -1 /tmp/csv_phmap.csv)
DATA_COLS=$(echo "$DATA_PHMAP" | tr ',' '\n' | wc -l)

if [ "$DATA_COLS" != "$COLS_PHMAP" ]; then
    echo "FAIL: Data row column count mismatch (header=$COLS_PHMAP, data=$DATA_COLS)"
    PASS=false
fi

if $PASS; then
    echo ""
    echo "PASS: CSV format validation successful"
    echo ""
    echo "Header ($COLS_PHMAP columns):"
    echo "$HEADER_PHMAP" | tr ',' '\n' | head -10
    echo "..."
    exit 0
else
    echo ""
    echo "CSV format validation FAILED"
    exit 1
fi
