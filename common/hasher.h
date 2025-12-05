#pragma once

#include <cstdint>
#include <cstddef>

namespace bench {

// Fast hash function for uint64_t keys
// CRITICAL: Must produce identical hashes to Rust implementation
// Uses FxHash-style multiplication
struct FastHasher {
    size_t operator()(uint64_t key) const noexcept {
        return static_cast<size_t>(key * 0x517cc1b727220a95ULL);
    }
};

} // namespace bench
