#include <libcuckoo/cuckoohash_map.hh>
#include <cstdio>

int main() {
    libcuckoo::cuckoohash_map<int, int> map;
    map.insert(1, 100);
    int val;
    map.find(1, val);
    printf("libcuckoo works: map[1] = %d\n", val);
    return 0;
}
