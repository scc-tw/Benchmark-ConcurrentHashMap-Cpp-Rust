#pragma once

#include "prng.h"
#include <cmath>
#include <cstdint>

namespace bench {

// Zipfian distribution generator
// Generates values in [0, n) with Zipf(s) distribution
// s = 1.0 is standard Zipf's law
class ZipfGenerator {
    uint64_t n_;
    double s_;
    uint64_t prng_state_;

    // Pre-computed values for fast sampling
    double h_integral_x1_;
    double h_integral_n_;
    double s_minus_1_;

    // Compute H(x) = integral of x^(-s) from 1 to x
    [[nodiscard]]
    double h_integral(double x) const noexcept {
        if (s_ == 1.0) {
            return std::log(x);
        }
        return (std::pow(x, 1.0 - s_) - 1.0) / (1.0 - s_);
    }

    // Inverse of h_integral
    [[nodiscard]]
    double h_integral_inv(double y) const noexcept {
        if (s_ == 1.0) {
            return std::exp(y);
        }
        return std::pow(y * (1.0 - s_) + 1.0, 1.0 / (1.0 - s_));
    }

public:
    ZipfGenerator(uint64_t n, double s, uint64_t seed)
        : n_(n), s_(s), prng_state_(seed) {
        s_minus_1_ = s - 1.0;
        h_integral_x1_ = h_integral(1.5) - 1.0;
        h_integral_n_ = h_integral(static_cast<double>(n) + 0.5);
    }

    // Generate next Zipfian-distributed value in [0, n)
    [[nodiscard]]
    uint64_t next() noexcept {
        while (true) {
            // Generate uniform random in [0, 1)
            double u = static_cast<double>(xorshift64star(&prng_state_))
                     / static_cast<double>(UINT64_MAX);

            // Map to [h_integral_x1_, h_integral_n_]
            double h_inv = h_integral_inv(
                h_integral_x1_ + u * (h_integral_n_ - h_integral_x1_)
            );

            uint64_t k = static_cast<uint64_t>(h_inv + 0.5);

            // Clamp to valid range
            if (k < 1) k = 1;
            if (k > n_) k = n_;

            // Acceptance test
            double h_k = h_integral(static_cast<double>(k) + 0.5)
                       - h_integral(static_cast<double>(k) - 0.5);

            double prob = std::pow(static_cast<double>(k), -s_) / h_k;

            double u2 = static_cast<double>(xorshift64star(&prng_state_))
                      / static_cast<double>(UINT64_MAX);

            if (u2 < prob) {
                return k - 1;  // Return 0-indexed
            }
        }
    }
};

} // namespace bench
