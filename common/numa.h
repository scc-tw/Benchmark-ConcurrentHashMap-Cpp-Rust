#pragma once

#include <vector>
#include <string>
#include <fstream>
#include <sstream>
#include <dirent.h>
#include <algorithm> // for std::max

namespace bench {

enum class PinningStrategy {
    COMPACT,  // All threads on consecutive cores (same socket)
    SPREAD    // Threads distributed across NUMA nodes
};

struct NumaTopology {
    int num_nodes = 1;
    std::vector<std::vector<int>> node_cores;  // node_cores[node] = {core_ids}

    [[nodiscard]]
    int total_cores() const noexcept {
        int total = 0;
        for (const auto& cores : node_cores) {
            total += static_cast<int>(cores.size());
        }
        return total;
    }
};

// Parse CPU list format "0-3,8-11" into vector of core IDs
[[nodiscard]]
inline std::vector<int> parse_cpulist(const std::string& cpulist) {
    std::vector<int> cores;
    std::stringstream ss(cpulist);
    std::string token;

    while (std::getline(ss, token, ',')) {
        size_t dash = token.find('-');
        if (dash != std::string::npos) {
            int start = std::stoi(token.substr(0, dash));
            int end = std::stoi(token.substr(dash + 1));
            for (int i = start; i <= end; ++i) {
                cores.push_back(i);
            }
        } else {
            cores.push_back(std::stoi(token));
        }
    }
    return cores;
}

// Detect NUMA topology from /sys filesystem
[[nodiscard]]
inline NumaTopology detect_numa() {
    NumaTopology topo;
    const std::string base = "/sys/devices/system/node/";

    DIR* dir = opendir(base.c_str());
    if (!dir) {
        // Fallback: single node with all cores
        topo.num_nodes = 1;
        // Read from /sys/devices/system/cpu/online
        std::ifstream online("/sys/devices/system/cpu/online");
        std::string cpulist;
        if (std::getline(online, cpulist)) {
            topo.node_cores.push_back(parse_cpulist(cpulist));
        }
        return topo;
    }

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        if (name.rfind("node", 0) == 0 && name.size() > 4) {
            int node_id = std::stoi(name.substr(4));

            std::string cpulist_path = base + name + "/cpulist";
            std::ifstream cpulist_file(cpulist_path);
            std::string cpulist;
            if (std::getline(cpulist_file, cpulist)) {
                // Ensure vector is large enough
                if (static_cast<size_t>(node_id) >= topo.node_cores.size()) {
                    topo.node_cores.resize(node_id + 1);
                }
                topo.node_cores[node_id] = parse_cpulist(cpulist);
            }
        }
    }
    closedir(dir);

    topo.num_nodes = static_cast<int>(topo.node_cores.size());

    // Ensure at least one node exists if detection failed but dir existed
    if (topo.num_nodes == 0) {
        topo.num_nodes = 1;
        topo.node_cores.resize(1);
        // Try fallback to online cpus
         std::ifstream online("/sys/devices/system/cpu/online");
        std::string cpulist;
        if (std::getline(online, cpulist)) {
            topo.node_cores[0] = parse_cpulist(cpulist);
        }
    }
    return topo;
}

// Get core IDs for given strategy and thread count
[[nodiscard]]
inline std::vector<int> get_cores(const NumaTopology& topo,
                                   PinningStrategy strategy,
                                   int num_threads) {
    std::vector<int> cores;

    if (strategy == PinningStrategy::COMPACT) {
        // Take consecutive cores from first node(s)
        for (const auto& node_cores : topo.node_cores) {
            for (int core : node_cores) {
                cores.push_back(core);
                if (static_cast<int>(cores.size()) >= num_threads) {
                    return cores;
                }
            }
        }
    } else {  // SPREAD
        // Round-robin across nodes
        size_t max_per_node = 0;
        for (const auto& node_cores : topo.node_cores) {
            max_per_node = std::max(max_per_node, node_cores.size());
        }

        for (size_t i = 0; i < max_per_node; ++i) {
            for (const auto& node_cores : topo.node_cores) {
                if (i < node_cores.size()) {
                    cores.push_back(node_cores[i]);
                    if (static_cast<int>(cores.size()) >= num_threads) {
                        return cores;
                    }
                }
            }
        }
    }

    return cores;
}

// Convert strategy to string for CSV output
[[nodiscard]]
inline const char* strategy_to_string(PinningStrategy strategy) noexcept {
    switch (strategy) {
        case PinningStrategy::COMPACT: return "compact";
        case PinningStrategy::SPREAD:  return "spread";
        default: return "unknown";
    }
}

} // namespace bench
