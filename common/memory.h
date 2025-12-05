#pragma once

#include <fstream>
#include <string>
#include <cstdint>

namespace bench {

// Get peak resident set size in KB (VmHWM = High Water Mark)
inline int64_t get_peak_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmHWM:", 0) == 0) {
            // Format: "VmHWM:    12345 kB"
            size_t pos = 6;
            while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t')) {
                ++pos;
            }
            return std::stoll(line.substr(pos));
        }
    }
    return -1;
}

// Get current resident set size in KB
inline int64_t get_current_rss_kb() {
    std::ifstream status("/proc/self/status");
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("VmRSS:", 0) == 0) {
            size_t pos = 6;
            while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t')) {
                ++pos;
            }
            return std::stoll(line.substr(pos));
        }
    }
    return -1;
}

// Compute bytes per entry
inline double bytes_per_entry(int64_t rss_kb, uint64_t num_entries) {
    return (static_cast<double>(rss_kb) * 1024.0) / static_cast<double>(num_entries);
}

// Compute overhead ratio (actual / theoretical minimum)
// Theoretical minimum for uint64_t key + uint64_t value = 16 bytes
inline double overhead_ratio(int64_t rss_kb, uint64_t num_entries) {
    double actual = bytes_per_entry(rss_kb, num_entries);
    return actual / 16.0;
}

} // namespace bench
