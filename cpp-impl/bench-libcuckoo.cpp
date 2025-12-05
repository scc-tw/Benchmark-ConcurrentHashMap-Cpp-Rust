#include <libcuckoo/cuckoohash_map.hh>

#include "config.h"
#include "prng.h"
#include "timing.h"
#include "hasher.h"
#include "zipf.h"
#include "worker.h"
#include "memory.h"
#include "numa.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <numeric>
#include <pthread.h>

using namespace bench;

// ============================================================================
// CLI Configuration
// ============================================================================

struct BenchConfig {
    std::string scenario = "insert_only";
    int threads = 1;
    uint64_t map_size = SIZE_MEDIUM;
    int repeats = REPEATS;
    uint64_t seed = 42;
    PinningStrategy pinning = PinningStrategy::COMPACT;
    std::string output_file = "";
    bool verify_prng = false;
    bool verify_hash = false;
};

namespace {

void print_usage(const char* prog) {
    fprintf(stderr, "Usage: %s [options]\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --scenario <name>     Scenario: insert_only, read_only, read_majority_99,\n");
    fprintf(stderr, "                        read_majority_95, balanced, zipfian, resize_stress,\n");
    fprintf(stderr, "                        sequential_keys, random_keys\n");
    fprintf(stderr, "  --threads <n>         Number of threads (default: 1)\n");
    fprintf(stderr, "  --mapsize <n>         Map size (default: 1000000)\n");
    fprintf(stderr, "  --repeats <n>         Number of repetitions (default: 40)\n");
    fprintf(stderr, "  --seed <n>            PRNG seed (default: 42)\n");
    fprintf(stderr, "  --pinning <strategy>  compact or spread (default: compact)\n");
    fprintf(stderr, "  --output <file>       Output CSV file (default: stdout)\n");
    fprintf(stderr, "  --verify-prng         Print PRNG sequence and exit\n");
    fprintf(stderr, "  --verify-hash         Print hash values and exit\n");
}

} // namespace

[[nodiscard]]
static BenchConfig parse_args(int argc, char** argv) {
    BenchConfig cfg;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--scenario") == 0 && i + 1 < argc) {
            cfg.scenario = argv[++i];
        } else if (strcmp(argv[i], "--threads") == 0 && i + 1 < argc) {
            cfg.threads = std::atoi(argv[++i]);
        } else if (strcmp(argv[i], "--mapsize") == 0 && i + 1 < argc) {
            cfg.map_size = std::strtoull(argv[++i], nullptr, 10);
        } else if (strcmp(argv[i], "--repeats") == 0 && i + 1 < argc) {
            cfg.repeats = std::atoi(argv[++i]);
        } else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            cfg.seed = std::strtoull(argv[++i], nullptr, 10);
        } else if (strcmp(argv[i], "--pinning") == 0 && i + 1 < argc) {
            const char* p = argv[++i];
            if (strcmp(p, "spread") == 0) {
                cfg.pinning = PinningStrategy::SPREAD;
            } else {
                cfg.pinning = PinningStrategy::COMPACT;
            }
        } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
            cfg.output_file = argv[++i];
        } else if (strcmp(argv[i], "--verify-prng") == 0) {
            cfg.verify_prng = true;
        } else if (strcmp(argv[i], "--verify-hash") == 0) {
            cfg.verify_hash = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            exit(0);
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            exit(1);
        }
    }

    return cfg;
}

// ============================================================================
// Map Type Definition
// ============================================================================

// Concurrent map type using libcuckoo with custom hasher
using ConcurrentMap = libcuckoo::cuckoohash_map<
    uint64_t,     // Key
    uint64_t,     // Value
    FastHasher   // Hash
>;

// ============================================================================
// Internal Helpers (Anonymous Namespace)
// ============================================================================

namespace {

void verify_prng(uint64_t seed) {
    uint64_t state = seed;
    printf("PRNG verification (seed=%lu):\n", seed);
    for (int i = 0; i < 10; ++i) {
        uint64_t val = xorshift64star(&state);
        printf("%d: %lu\n", i, val);
    }
}

void verify_hash() {
    FastHasher hasher;
    printf("Hash verification:\n");
    printf("hash(0) = %zu\n", hasher(0));
    printf("hash(1) = %zu\n", hasher(1));
    printf("hash(42) = %zu\n", hasher(42));
    printf("hash(1000000) = %zu\n", hasher(1000000ULL));
    printf("hash(UINT64_MAX) = %zu\n", hasher(UINT64_MAX));
}

void pre_populate(ConcurrentMap& map, uint64_t count) {
    map.reserve(count);
    for (uint64_t i = 0; i < count; ++i) {
        map.insert(i, i);
    }
}

// ============================================================================
// Worker Thread Functions
// ============================================================================

// Scenario 1: Insert-only (100% writes, unique keys per thread)
void* worker_insert_only(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    const uint64_t base_key = static_cast<uint64_t>(ctx->thread_id) * ctx->ops_per_thread;
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = base_key + i;
        map->insert(key, key);

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 2: Read-only (100% reads)
void* worker_read_only(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    const uint64_t map_size = map->size();
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = rand_range(&ctx->prng_state, map_size);
        uint64_t val;
        map->find(key, val);
        (void)val;  // Prevent optimization

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 3: Read-majority (parameterized read percentage)
struct ReadMajorityArgs {
    WorkerContext* ctx;
    int read_percent;  // 99 or 95
};

void* worker_read_majority(void* arg) noexcept {
    ReadMajorityArgs* args = static_cast<ReadMajorityArgs*>(arg);
    WorkerContext* ctx = args->ctx;
    const int read_pct = args->read_percent;
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    const uint64_t map_size = map->size();
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = rand_range(&ctx->prng_state, map_size);
        const int op_type = static_cast<int>(rand_range(&ctx->prng_state, 100));

        if (op_type < read_pct) {
            // Read
            uint64_t val;
            map->find(key, val);
            (void)val;
        } else {
            // Write (update existing key)
            map->upsert(key, [](uint64_t& v) { v += 1; }, key + 1);
        }

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 4: Balanced (50% read, 50% write)
void* worker_balanced(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    const uint64_t map_size = map->size();
    const uint64_t write_base = map_size;  // New keys start after existing
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const int op_type = static_cast<int>(rand_range(&ctx->prng_state, 100));

        if (op_type < 50) {
            // Read existing key
            const uint64_t key = rand_range(&ctx->prng_state, map_size);
            uint64_t val;
            map->find(key, val);
            (void)val;
        } else {
            // Write new key
            const uint64_t key = write_base + rand_range(&ctx->prng_state, map_size);
            map->insert(key, key);
        }

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 5: Zipfian (90% read, 10% write, Zipf distribution)
struct ZipfianArgs {
    WorkerContext* ctx;
    ZipfGenerator* zipf;
};

void* worker_zipfian(void* arg) noexcept {
    ZipfianArgs* args = static_cast<ZipfianArgs*>(arg);
    WorkerContext* ctx = args->ctx;
    ZipfGenerator* zipf = args->zipf;
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = zipf->next();
        const int op_type = static_cast<int>(rand_range(&ctx->prng_state, 100));

        if (op_type < 90) {
            // Read
            uint64_t val;
            map->find(key, val);
            (void)val;
        } else {
            // Write
            map->upsert(key, [](uint64_t& v) { v += 1; }, key + 1);
        }

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 6: Resize stress (small initial capacity, many inserts)
void* worker_resize_stress(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    const uint64_t base_key = static_cast<uint64_t>(ctx->thread_id) * ctx->ops_per_thread;
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = base_key + i;
        map->insert(key, key);

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 7a: Sequential keys (insert sequential keys)
void* worker_sequential_keys(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    // Each thread gets a contiguous range
    const uint64_t base_key = static_cast<uint64_t>(ctx->thread_id) * ctx->ops_per_thread;
    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = base_key + i;
        map->insert(key, key);

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// Scenario 7b: Random keys (insert random keys)
void* worker_random_keys(void* arg) noexcept {
    WorkerContext* ctx = static_cast<WorkerContext*>(arg);
    ConcurrentMap* map = static_cast<ConcurrentMap*>(ctx->map);

    pin_thread(ctx->core_id);
    pthread_barrier_wait(ctx->barrier);

    auto t_start = get_time();

    for (uint64_t i = 0; i < ctx->ops_per_thread; ++i) {
        const bool sample = (i % SAMPLE_INTERVAL == 0);
        struct timespec t0;

        if (sample) t0 = get_time();

        const uint64_t key = xorshift64star(&ctx->prng_state);
        map->insert(key, key);

        if (sample) {
            struct timespec t1 = get_time();
            ctx->latencies.push_back({i, ctx->thread_id, diff_ns(t0, t1)});
        }
    }

    auto t_end = get_time();
    ctx->duration_ns = diff_ns(t_start, t_end);
    return nullptr;
}

// ============================================================================
// Latency Statistics
// ============================================================================

struct LatencyStats {
    double mean_ns;
    int64_t p50_ns;
    int64_t p90_ns;
    int64_t p95_ns;
    int64_t p99_ns;
    int64_t max_ns;
    uint64_t count;
};

[[nodiscard]]
LatencyStats compute_latency_stats(const std::vector<LatencySample>& samples) {
    LatencyStats stats = {};
    if (samples.empty()) return stats;

    std::vector<int64_t> latencies;
    latencies.reserve(samples.size());
    for (const auto& s : samples) {
        latencies.push_back(s.latency_ns);
    }

    std::sort(latencies.begin(), latencies.end());

    stats.count = latencies.size();
    stats.max_ns = latencies.back();

    // Mean
    double sum = 0;
    for (int64_t lat : latencies) sum += lat;
    stats.mean_ns = sum / static_cast<double>(stats.count);

    // Percentiles
    auto percentile = [&](double p) -> int64_t {
        size_t idx = static_cast<size_t>(p * (latencies.size() - 1));
        return latencies[idx];
    };

    stats.p50_ns = percentile(0.50);
    stats.p90_ns = percentile(0.90);
    stats.p95_ns = percentile(0.95);
    stats.p99_ns = percentile(0.99);

    return stats;
}

// ============================================================================
// CSV Output
// ============================================================================

void print_csv_header(FILE* out) {
    fprintf(out, "run_id,map_name,map_version,scenario,thread_count,map_size,"
                 "ops_per_trial,repeat_index,seed,core_mapping,duration_ns,"
                 "ops_per_sec,mean_sample_latency_ns,p50_latency_ns,"
                 "p90_latency_ns,p95_latency_ns,p99_latency_ns,"
                 "max_sample_latency_ns,sampled_ops_count,peak_rss_kb,"
                 "current_rss_kb,bytes_per_entry,overhead_ratio,"
                 "numa_nodes,pinning_strategy,allocation_node,notes\n");
}

void print_csv_row(FILE* out,
                   const std::string& run_id,
                   const std::string& scenario,
                   int threads,
                   uint64_t map_size,
                   int repeat_idx,
                   uint64_t seed,
                   const std::string& core_mapping,
                   int64_t duration_ns,
                   const LatencyStats& lat_stats,
                   int64_t peak_rss_kb,
                   int64_t current_rss_kb,
                   uint64_t final_map_size,
                   int numa_nodes,
                   PinningStrategy pinning,
                   const std::string& notes) {

    double ops_per_sec = ns_to_ops_per_sec(duration_ns, OPS_PER_TRIAL);
    double bpe = bytes_per_entry(current_rss_kb, final_map_size);
    double ovr = overhead_ratio(current_rss_kb, final_map_size);

    fprintf(out, "%s,libcuckoo,master,%s,%d,%lu,%lu,%d,%lu,%s,"
                 "%ld,%.2f,%.2f,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%.2f,%.2f,"
                 "%d,%s,0,%s\n",
            run_id.c_str(),
            scenario.c_str(),
            threads,
            map_size,
            OPS_PER_TRIAL,
            repeat_idx,
            seed,
            core_mapping.c_str(),
            duration_ns,
            ops_per_sec,
            lat_stats.mean_ns,
            lat_stats.p50_ns,
            lat_stats.p90_ns,
            lat_stats.p95_ns,
            lat_stats.p99_ns,
            lat_stats.max_ns,
            lat_stats.count,
            peak_rss_kb,
            current_rss_kb,
            bpe,
            ovr,
            numa_nodes,
            strategy_to_string(pinning),
            notes.c_str());
}

// ============================================================================
// Trial Runner
// ============================================================================

struct TrialResult {
    int64_t total_duration_ns;
    LatencyStats lat_stats;
    int64_t peak_rss_kb;
    int64_t current_rss_kb;
    uint64_t final_map_size;
    std::string core_mapping;
};

TrialResult run_trial(const BenchConfig& cfg,
                      const std::vector<int>& core_ids,
                      uint64_t trial_seed) {
    TrialResult result = {};

    // Create map
    ConcurrentMap map;

    // Pre-populate if needed
    bool needs_prepop = (cfg.scenario == "read_only" ||
                         cfg.scenario == "read_majority_99" ||
                         cfg.scenario == "read_majority_95" ||
                         cfg.scenario == "balanced" ||
                         cfg.scenario == "zipfian");

    if (needs_prepop) {
        pre_populate(map, cfg.map_size);
    } else if (cfg.scenario == "resize_stress") {
        // Small initial capacity for resize stress
        map.reserve(1024);
    } else {
        map.reserve(cfg.map_size);
    }

    // Build core mapping string
    std::string core_map_str;
    for (size_t i = 0; i < core_ids.size(); ++i) {
        if (i > 0) core_map_str += ",";
        core_map_str += std::to_string(core_ids[i]);
    }
    result.core_mapping = core_map_str;

    // Create barrier
    pthread_barrier_t barrier;
    pthread_barrier_init(&barrier, nullptr, cfg.threads);

    // Create workers
    auto workers = create_workers(cfg.threads, core_ids, trial_seed, &map, &barrier);

    // Scenario-specific args
    std::vector<ReadMajorityArgs> rm_args(cfg.threads);
    std::vector<ZipfianArgs> zipf_args(cfg.threads);
    std::vector<ZipfGenerator> zipf_gens;

    // Prepare zipf generators if needed
    if (cfg.scenario == "zipfian") {
        for (int i = 0; i < cfg.threads; ++i) {
            zipf_gens.emplace_back(cfg.map_size, 1.0, trial_seed + i + 1000);
        }
    }

    // Select worker function
    void* (*worker_fn)(void*) = nullptr;
    std::vector<void*> thread_args(cfg.threads);

    if (cfg.scenario == "insert_only") {
        worker_fn = worker_insert_only;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    } else if (cfg.scenario == "read_only") {
        worker_fn = worker_read_only;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    } else if (cfg.scenario == "read_majority_99") {
        worker_fn = worker_read_majority;
        for (int i = 0; i < cfg.threads; ++i) {
            rm_args[i] = {&workers[i], 99};
            thread_args[i] = &rm_args[i];
        }
    } else if (cfg.scenario == "read_majority_95") {
        worker_fn = worker_read_majority;
        for (int i = 0; i < cfg.threads; ++i) {
            rm_args[i] = {&workers[i], 95};
            thread_args[i] = &rm_args[i];
        }
    } else if (cfg.scenario == "balanced") {
        worker_fn = worker_balanced;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    } else if (cfg.scenario == "zipfian") {
        worker_fn = worker_zipfian;
        for (int i = 0; i < cfg.threads; ++i) {
            zipf_args[i] = {&workers[i], &zipf_gens[i]};
            thread_args[i] = &zipf_args[i];
        }
    } else if (cfg.scenario == "resize_stress") {
        worker_fn = worker_resize_stress;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    } else if (cfg.scenario == "sequential_keys") {
        worker_fn = worker_sequential_keys;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    } else if (cfg.scenario == "random_keys") {
        worker_fn = worker_random_keys;
        for (int i = 0; i < cfg.threads; ++i) thread_args[i] = &workers[i];
    }

    // Create and run threads
    std::vector<pthread_t> threads(cfg.threads);
    for (int i = 0; i < cfg.threads; ++i) {
        pthread_create(&threads[i], nullptr, worker_fn, thread_args[i]);
    }

    // Wait for completion
    for (int i = 0; i < cfg.threads; ++i) {
        pthread_join(threads[i], nullptr);
    }

    pthread_barrier_destroy(&barrier);

    // Aggregate results
    int64_t max_duration = 0;
    std::vector<LatencySample> all_latencies;

    for (const auto& w : workers) {
        max_duration = std::max(max_duration, w.duration_ns);
        all_latencies.insert(all_latencies.end(),
                             w.latencies.begin(), w.latencies.end());
    }

    result.total_duration_ns = max_duration;
    result.lat_stats = compute_latency_stats(all_latencies);
    result.peak_rss_kb = get_peak_rss_kb();
    result.current_rss_kb = get_current_rss_kb();
    result.final_map_size = map.size();

    return result;
}

} // namespace

// ============================================================================
// Main
// ============================================================================

int main(int argc, char** argv) {
    BenchConfig cfg = parse_args(argc, argv);

    // Handle verification modes
    if (cfg.verify_prng) {
        verify_prng(cfg.seed);
        return 0;
    }
    if (cfg.verify_hash) {
        verify_hash();
        return 0;
    }

    // Detect NUMA topology
    NumaTopology topo = detect_numa();
    std::vector<int> core_ids = get_cores(topo, cfg.pinning, cfg.threads);

    if (static_cast<int>(core_ids.size()) < cfg.threads) {
        fprintf(stderr, "Error: Not enough cores (%zu) for %d threads\n",
                core_ids.size(), cfg.threads);
        return 1;
    }

    // Open output file
    FILE* out = stdout;
    if (!cfg.output_file.empty()) {
        out = fopen(cfg.output_file.c_str(), "w");
        if (!out) {
            fprintf(stderr, "Error: Cannot open output file: %s\n",
                    cfg.output_file.c_str());
            return 1;
        }
    }

    // Print CSV header
    print_csv_header(out);

    // Generate run ID
    char run_id[64];
    snprintf(run_id, sizeof(run_id), "libcuckoo_%s_%dt_%lum",
             cfg.scenario.c_str(), cfg.threads, cfg.map_size);

    // Run repetitions
    for (int rep = 0; rep < cfg.repeats; ++rep) {
        uint64_t trial_seed = cfg.seed + static_cast<uint64_t>(rep);

        TrialResult result = run_trial(cfg, core_ids, trial_seed);

        print_csv_row(out,
                      run_id,
                      cfg.scenario,
                      cfg.threads,
                      cfg.map_size,
                      rep,
                      trial_seed,
                      result.core_mapping,
                      result.total_duration_ns,
                      result.lat_stats,
                      result.peak_rss_kb,
                      result.current_rss_kb,
                      result.final_map_size,
                      topo.num_nodes,
                      cfg.pinning,
                      "");

        // Progress indicator to stderr
        fprintf(stderr, "\r[%d/%d] %s threads=%d mapsize=%lu",
                rep + 1, cfg.repeats, cfg.scenario.c_str(),
                cfg.threads, cfg.map_size);
        fflush(stderr);
    }

    fprintf(stderr, "\n");

    if (out != stdout) {
        fclose(out);
    }

    return 0;
}
