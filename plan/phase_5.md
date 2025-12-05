# Phase 5: Validation

## Objective

Validate that all three implementations (parallel-hashmap, libcuckoo, DashMap) produce identical PRNG sequences, hash values, and CSV output formats. Verify correctness of each scenario before running full benchmark suite.

## Prerequisites

- Phase 1-4 complete
- All three executables built:
  - `build/cpp-impl/bench-phmap`
  - `build/cpp-impl/bench-libcuckoo`
  - `rust-impl/target/release/bench-dashmap`

## Validation Categories

```
┌─────────────────────────────────────────────────────────────┐
│                    Validation Tests                          │
├─────────────────┬─────────────────┬─────────────────────────┤
│ PRNG Sequence   │ Hash Function   │ CSV Format              │
│ (Critical)      │ (Critical)      │ (Required)              │
├─────────────────┼─────────────────┼─────────────────────────┤
│ Scenario        │ Memory          │ Thread Affinity         │
│ Correctness     │ Measurement     │ (Optional)              │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## Steps

---

### Step 5.1: Create Validation Scripts Directory

**Tasks:**
- [ ] Create scripts directory
- [ ] Create validation subdirectory

**Commands:**
```bash
mkdir -p scripts/validation
```

---

### Step 5.2: PRNG Sequence Validation

**File:** `scripts/validation/validate_prng.sh`

**Purpose:** Verify all implementations produce identical PRNG sequences.

**Tasks:**
- [ ] Create validation script
- [ ] Generate sequences from all three implementations
- [ ] Compare outputs with diff
- [ ] Report pass/fail status

**Implementation:**
```bash
#!/bin/bash
# validate_prng.sh - Verify PRNG sequences match across implementations

set -e

SEED=${1:-42}
COUNT=${2:-1000}

echo "=== PRNG Validation (seed=$SEED) ==="

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
    echo "First 5 values:"
    head -7 /tmp/prng_phmap.txt
    exit 0
else
    echo ""
    echo "PRNG validation FAILED"
    exit 1
fi
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_prng.sh
```

---

### Step 5.3: Hash Function Validation

**File:** `scripts/validation/validate_hash.sh`

**Purpose:** Verify all implementations produce identical hash values.

**Tasks:**
- [ ] Create validation script
- [ ] Generate hash outputs from all three implementations
- [ ] Compare outputs
- [ ] Report pass/fail status

**Implementation:**
```bash
#!/bin/bash
# validate_hash.sh - Verify hash functions match across implementations

set -e

echo "=== Hash Function Validation ==="

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
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_hash.sh
```

---

### Step 5.4: CSV Format Validation

**File:** `scripts/validation/validate_csv.sh`

**Purpose:** Verify CSV output format is consistent across implementations.

**Tasks:**
- [ ] Create validation script
- [ ] Run minimal benchmark from each implementation
- [ ] Compare CSV headers
- [ ] Verify column count matches
- [ ] Check data types in each column

**Implementation:**
```bash
#!/bin/bash
# validate_csv.sh - Verify CSV output format consistency

set -e

echo "=== CSV Format Validation ==="

# Run minimal benchmarks to generate CSV
echo "Running phmap..."
./build/cpp-impl/bench-phmap --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_phmap.csv

echo "Running libcuckoo..."
./build/cpp-impl/bench-libcuckoo --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_libcuckoo.csv

echo "Running dashmap..."
./rust-impl/target/release/bench-dashmap --scenario insert_only --threads 1 --mapsize 1000 --repeats 1 > /tmp/csv_dashmap.csv

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
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_csv.sh
```

---

### Step 5.5: Scenario Correctness Tests

**File:** `scripts/validation/validate_scenarios.sh`

**Purpose:** Verify each scenario runs without errors and produces valid output.

**Tasks:**
- [ ] Create validation script
- [ ] Test each scenario with each implementation
- [ ] Verify non-zero throughput
- [ ] Check map size changes appropriately

**Implementation:**
```bash
#!/bin/bash
# validate_scenarios.sh - Verify all scenarios run correctly

set -e

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

    for scenario in $SCENARIOS; do
        echo -n "  $scenario: "

        OUTPUT=$($BIN --scenario $scenario --threads $THREADS --mapsize $MAPSIZE --repeats $REPEATS 2>/dev/null)

        if [ $? -ne 0 ]; then
            echo "FAIL (exit code)"
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
        if (( $(echo "$OPS_PER_SEC < 1000" | bc -l) )); then
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
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_scenarios.sh
```

---

### Step 5.6: Memory Measurement Validation

**File:** `scripts/validation/validate_memory.sh`

**Purpose:** Verify memory measurements are populated and reasonable.

**Tasks:**
- [ ] Create validation script
- [ ] Run benchmark with known map size
- [ ] Check RSS values are positive
- [ ] Verify bytes_per_entry is reasonable (16-64 bytes typical)

**Implementation:**
```bash
#!/bin/bash
# validate_memory.sh - Verify memory measurements are correct

set -e

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

    # Validate peak RSS
    if [ "$PEAK_RSS" -lt "$MIN_RSS_KB" ] 2>/dev/null; then
        echo "  FAIL: peak_rss too low ($PEAK_RSS < $MIN_RSS_KB)"
        PASS=false
    elif [ "$PEAK_RSS" -gt "$MAX_RSS_KB" ] 2>/dev/null; then
        echo "  FAIL: peak_rss too high ($PEAK_RSS > $MAX_RSS_KB)"
        PASS=false
    else
        echo "  peak_rss: OK"
    fi

    # Validate bytes_per_entry (should be 16-100 bytes typically)
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
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_memory.sh
```

---

### Step 5.7: Thread Affinity Validation

**File:** `scripts/validation/validate_affinity.sh`

**Purpose:** Verify thread pinning works correctly.

**Tasks:**
- [ ] Create validation script
- [ ] Run benchmark with specific core mapping
- [ ] Use taskset or /proc to verify pinning

**Implementation:**
```bash
#!/bin/bash
# validate_affinity.sh - Verify thread pinning works

echo "=== Thread Affinity Validation ==="
echo ""
echo "This test requires manual verification with htop or similar."
echo ""

THREADS=4
MAPSIZE=1000000
REPEATS=5

echo "Running 4-thread benchmark for 5 repetitions..."
echo "Open htop in another terminal and verify:"
echo "  - With --pinning compact: threads on consecutive cores (e.g., 0,1,2,3)"
echo "  - With --pinning spread: threads distributed across NUMA nodes"
echo ""

echo "--- Testing COMPACT pinning ---"
echo "Command: ./build/cpp-impl/bench-phmap --scenario read_only --threads 4 --mapsize 1000000 --repeats 5 --pinning compact"
read -p "Press Enter to run (watch htop)..."

./build/cpp-impl/bench-phmap --scenario read_only --threads $THREADS --mapsize $MAPSIZE --repeats $REPEATS --pinning compact 2>&1 | tail -3

echo ""
echo "--- Testing SPREAD pinning ---"
echo "Command: ./build/cpp-impl/bench-phmap --scenario read_only --threads 4 --mapsize 1000000 --repeats 5 --pinning spread"
read -p "Press Enter to run (watch htop)..."

./build/cpp-impl/bench-phmap --scenario read_only --threads $THREADS --mapsize $MAPSIZE --repeats $REPEATS --pinning spread 2>&1 | tail -3

echo ""
echo "Did threads appear on expected cores? (Verify manually)"
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_affinity.sh
```

---

### Step 5.8: Create Master Validation Script

**File:** `scripts/validation/run_all_validations.sh`

**Purpose:** Run all validation tests in sequence.

**Tasks:**
- [ ] Create master script
- [ ] Run each validation in order
- [ ] Report overall status

**Implementation:**
```bash
#!/bin/bash
# run_all_validations.sh - Run all validation tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")/.."  # Go to project root

echo "========================================"
echo "  Concurrent HashMap Benchmark Validation"
echo "========================================"
echo ""

PASS=true

# 1. PRNG Validation
echo ">>> Running PRNG validation..."
if ! $SCRIPT_DIR/validate_prng.sh; then
    PASS=false
fi
echo ""

# 2. Hash Validation
echo ">>> Running Hash validation..."
if ! $SCRIPT_DIR/validate_hash.sh; then
    PASS=false
fi
echo ""

# 3. CSV Format Validation
echo ">>> Running CSV format validation..."
if ! $SCRIPT_DIR/validate_csv.sh; then
    PASS=false
fi
echo ""

# 4. Scenario Correctness
echo ">>> Running Scenario correctness validation..."
if ! $SCRIPT_DIR/validate_scenarios.sh; then
    PASS=false
fi
echo ""

# 5. Memory Measurement
echo ">>> Running Memory measurement validation..."
if ! $SCRIPT_DIR/validate_memory.sh; then
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
```

**Make executable:**
```bash
chmod +x scripts/validation/run_all_validations.sh
```

---

### Step 5.9: Extended PRNG Test (1000 values)

**File:** `scripts/validation/validate_prng_extended.sh`

**Purpose:** Generate and compare 1000 PRNG values for thorough verification.

**Tasks:**
- [ ] Modify benchmark to output more values (or use separate test binary)
- [ ] Compare extended sequences

**Implementation:**

First, add `--verify-prng-count` argument to benchmarks:

**C++ addition (in bench-phmap.cpp):**
```cpp
// In parse_args(), add:
} else if (strcmp(argv[i], "--verify-prng-count") == 0 && i + 1 < argc) {
    cfg.verify_prng_count = std::atoi(argv[++i]);
}

// In verify_prng():
void verify_prng(uint64_t seed, int count = 10) {
    uint64_t state = seed;
    printf("PRNG verification (seed=%lu, count=%d):\n", seed, count);
    for (int i = 0; i < count; ++i) {
        uint64_t val = xorshift64star(&state);
        printf("%d: %lu\n", i, val);
    }
}
```

**Validation script:**
```bash
#!/bin/bash
# validate_prng_extended.sh - Extended PRNG validation with 1000 values

set -e

SEED=42
COUNT=1000

echo "=== Extended PRNG Validation (count=$COUNT) ==="

# Create test programs that output more values
# (Alternatively, modify --verify-prng to accept count)

# For now, use a simple C++ test program
cat > /tmp/test_prng_extended.cpp << 'EOF'
#include <cstdint>
#include <cstdio>

inline uint64_t xorshift64star(uint64_t* state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

int main(int argc, char** argv) {
    uint64_t seed = argc > 1 ? strtoull(argv[1], nullptr, 10) : 42;
    int count = argc > 2 ? atoi(argv[2]) : 1000;

    uint64_t state = seed;
    for (int i = 0; i < count; ++i) {
        printf("%lu\n", xorshift64star(&state));
    }
    return 0;
}
EOF

g++ -O2 -o /tmp/test_prng_cpp /tmp/test_prng_extended.cpp

# Rust version
cat > /tmp/test_prng_extended.rs << 'EOF'
fn xorshift64star(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545F4914F6CDD1Du64)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let seed: u64 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(42);
    let count: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1000);

    let mut state = seed;
    for _ in 0..count {
        println!("{}", xorshift64star(&mut state));
    }
}
EOF

rustc -O -o /tmp/test_prng_rust /tmp/test_prng_extended.rs

echo "Generating $COUNT values..."
/tmp/test_prng_cpp $SEED $COUNT > /tmp/prng_cpp_extended.txt
/tmp/test_prng_rust $SEED $COUNT > /tmp/prng_rust_extended.txt

echo "Comparing..."
if diff -q /tmp/prng_cpp_extended.txt /tmp/prng_rust_extended.txt > /dev/null; then
    echo "PASS: All $COUNT PRNG values match"
    echo ""
    echo "Sample (first 5 and last 5):"
    head -5 /tmp/prng_cpp_extended.txt
    echo "..."
    tail -5 /tmp/prng_cpp_extended.txt
else
    echo "FAIL: PRNG mismatch detected"
    diff /tmp/prng_cpp_extended.txt /tmp/prng_rust_extended.txt | head -20
    exit 1
fi
```

**Make executable:**
```bash
chmod +x scripts/validation/validate_prng_extended.sh
```

---

### Step 5.10: Create Validation Report Template

**File:** `scripts/validation/generate_report.sh`

**Purpose:** Generate a validation report for documentation.

**Tasks:**
- [ ] Create report generation script
- [ ] Capture all validation outputs
- [ ] Generate markdown report

**Implementation:**
```bash
#!/bin/bash
# generate_report.sh - Generate validation report

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")/.."

REPORT_FILE="results/validation_report.md"
mkdir -p results

echo "Generating validation report..."

cat > $REPORT_FILE << 'EOF'
# Validation Report

Generated: $(date)

## System Information

EOF

# Add system info
echo '```' >> $REPORT_FILE
echo "Hostname: $(hostname)" >> $REPORT_FILE
echo "Kernel: $(uname -r)" >> $REPORT_FILE
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)" >> $REPORT_FILE
echo "Cores: $(nproc)" >> $REPORT_FILE
echo "Memory: $(free -h | grep Mem | awk '{print $2}')" >> $REPORT_FILE
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## Compiler Versions" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
g++ --version | head -1 >> $REPORT_FILE
rustc --version >> $REPORT_FILE
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## PRNG Validation" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
$SCRIPT_DIR/validate_prng.sh 2>&1 >> $REPORT_FILE || true
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## Hash Validation" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
$SCRIPT_DIR/validate_hash.sh 2>&1 >> $REPORT_FILE || true
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## CSV Format Validation" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
$SCRIPT_DIR/validate_csv.sh 2>&1 >> $REPORT_FILE || true
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## Scenario Validation" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
$SCRIPT_DIR/validate_scenarios.sh 2>&1 >> $REPORT_FILE || true
echo '```' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "## Memory Validation" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo '```' >> $REPORT_FILE
$SCRIPT_DIR/validate_memory.sh 2>&1 >> $REPORT_FILE || true
echo '```' >> $REPORT_FILE

echo ""
echo "Report generated: $REPORT_FILE"
```

**Make executable:**
```bash
chmod +x scripts/validation/generate_report.sh
```

---

### Step 5.11: Run All Validations

**Tasks:**
- [ ] Execute master validation script
- [ ] Review all results
- [ ] Fix any failures before proceeding

**Commands:**
```bash
# Run all validations
./scripts/validation/run_all_validations.sh

# If any fail, debug individually:
./scripts/validation/validate_prng.sh
./scripts/validation/validate_hash.sh
./scripts/validation/validate_csv.sh
./scripts/validation/validate_scenarios.sh
./scripts/validation/validate_memory.sh

# Generate report
./scripts/validation/generate_report.sh
```

---

### Step 5.12: Document Expected Values

**File:** `scripts/validation/expected_values.md`

**Purpose:** Document expected PRNG and hash values for reference.

**Tasks:**
- [ ] Record expected PRNG sequence (seed=42)
- [ ] Record expected hash values

**Content:**
```markdown
# Expected Validation Values

## PRNG Sequence (seed=42)

First 10 values from xorshift64* with seed=42:

| Index | Value |
|-------|-------|
| 0 | [generated value] |
| 1 | [generated value] |
| 2 | [generated value] |
| ... | ... |

## Hash Values

Using multiplier 0x517cc1b727220a95:

| Key | Hash |
|-----|------|
| 0 | 0 |
| 1 | 5863438014042413205 |
| 42 | [computed] |
| 1000000 | [computed] |
| UINT64_MAX | [computed] |

## Notes

- PRNG and hash must match EXACTLY between C++ and Rust
- Any mismatch invalidates benchmark comparisons
- Re-run validation after any changes to prng.h, prng.rs, hasher.h, or hasher.rs
```

---

## Verification Checklist

- [ ] All validation scripts created and executable
- [ ] PRNG sequences match across all implementations
- [ ] Hash values match across all implementations
- [ ] CSV format consistent (same headers, same column count)
- [ ] All 9 scenarios run without errors on all implementations
- [ ] Memory measurements are reasonable
- [ ] Validation report generated

## Files Created

| File | Purpose |
|------|---------|
| `scripts/validation/validate_prng.sh` | PRNG sequence validation |
| `scripts/validation/validate_hash.sh` | Hash function validation |
| `scripts/validation/validate_csv.sh` | CSV format validation |
| `scripts/validation/validate_scenarios.sh` | Scenario correctness |
| `scripts/validation/validate_memory.sh` | Memory measurement validation |
| `scripts/validation/validate_affinity.sh` | Thread pinning (manual) |
| `scripts/validation/validate_prng_extended.sh` | Extended PRNG test |
| `scripts/validation/run_all_validations.sh` | Master validation runner |
| `scripts/validation/generate_report.sh` | Report generator |
| `scripts/validation/expected_values.md` | Reference values |

## Failure Resolution Guide

| Failure | Likely Cause | Resolution |
|---------|--------------|------------|
| PRNG mismatch | Bit operations differ | Check shift values (12, 25, 27) and multiplier |
| Hash mismatch | Multiplier differs | Verify 0x517cc1b727220a95 in both |
| CSV columns differ | Missing/extra fields | Compare headers, update output functions |
| Scenario crash | API misuse | Check map operations for that scenario |
| Memory invalid | /proc not available | Verify Linux platform, check file parsing |
| Low throughput | Debug build | Ensure release/optimized build |

## Next Phase

After all validations pass, proceed to **Phase 6: Orchestration Scripts** to implement the experiment runner and analysis pipeline.
