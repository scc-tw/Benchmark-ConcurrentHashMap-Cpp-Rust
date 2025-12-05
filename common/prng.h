#pragma once

#include <cstdint>

namespace bench {

// xorshift64* PRNG
// CRITICAL: Must produce identical sequence to Rust implementation
// Reference: https://en.wikipedia.org/wiki/Xorshift#xorshift*
inline uint64_t xorshift64star(uint64_t* state) noexcept {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

// Generate random number in range [0, max)
inline uint64_t rand_range(uint64_t* state, uint64_t max) noexcept {
    return xorshift64star(state) % max;
}

} // namespace bench
