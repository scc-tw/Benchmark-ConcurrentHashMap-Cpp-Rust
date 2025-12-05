#include "hasher.h"
#include <cstdio>
#include <cstdint>

int main() {
    bench::FastHasher hasher;

    printf("Hasher verification:\n");
    printf("hash(0) = %zu\n", hasher(0));
    printf("hash(1) = %zu\n", hasher(1));
    printf("hash(42) = %zu\n", hasher(42));
    printf("hash(1000000) = %zu\n", hasher(1000000));
    printf("hash(UINT64_MAX) = %zu\n", hasher(UINT64_MAX));

    return 0;
}
