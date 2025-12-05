#include "prng.h"
#include <cstdio>

int main() {
    uint64_t state = 42;

    printf("PRNG verification (seed=42):\n");
    for (int i = 0; i < 10; ++i) {
        uint64_t val = bench::xorshift64star(&state);
        printf("%d: %lu\n", i, val);
    }

    return 0;
}
