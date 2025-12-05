#include <parallel_hashmap/phmap.h>
#include <cstdio>

int main() {
    phmap::parallel_flat_hash_map<int, int> map;
    map[1] = 100;
    printf("parallel-hashmap works: map[1] = %d\n", map[1]);
    return 0;
}
