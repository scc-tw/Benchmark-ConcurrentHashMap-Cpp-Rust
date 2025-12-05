# Phase 1: Build Infrastructure

## Objective

Set up CMake build system with FetchContent for C++ dependencies, configure optimization flags, and verify all dependencies compile correctly.

## Prerequisites

- CMake 3.16+
- C++17 compiler (GCC 9+ or Clang 10+)
- Git (for FetchContent)
- pthread library

## Steps

### Step 1.1: Create Root CMakeLists.txt

**File:** `CMakeLists.txt`

**Tasks:**
- [ ] Create CMakeLists.txt in project root
- [ ] Set minimum CMake version to 3.16
- [ ] Configure C++17 standard
- [ ] Enable compile_commands.json export

**Content to implement:**
```cmake
cmake_minimum_required(VERSION 3.16)
project(concurrent_hashmap_bench CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
```

---

### Step 1.2: Configure Build Type and Optimization Flags

**File:** `CMakeLists.txt` (append)

**Tasks:**
- [ ] Set Release as default build type
- [ ] Configure `-O3 -march=native -flto -DNDEBUG` for Release
- [ ] Enable interprocedural optimization

**Content to implement:**
```cmake
# Release by default
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Optimization flags
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto -DNDEBUG")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
```

---

### Step 1.3: Add FetchContent for parallel-hashmap

**File:** `CMakeLists.txt` (append)

**Tasks:**
- [ ] Include FetchContent module
- [ ] Declare parallel-hashmap dependency (v2.0.0)
- [ ] Use git tag for version pinning

**Content to implement:**
```cmake
include(FetchContent)

FetchContent_Declare(
    parallel-hashmap
    GIT_REPOSITORY https://github.com/greg7mdp/parallel-hashmap.git
    GIT_TAG        v2.0.0
)
```

---

### Step 1.4: Add FetchContent for libcuckoo

**File:** `CMakeLists.txt` (append)

**Tasks:**
- [ ] Declare libcuckoo dependency
- [ ] Use master branch (no stable tags)

**Content to implement:**
```cmake
FetchContent_Declare(
    libcuckoo
    GIT_REPOSITORY https://github.com/efficient/libcuckoo.git
    GIT_TAG        master
)
```

---

### Step 1.5: Make Dependencies Available

**File:** `CMakeLists.txt` (append)

**Tasks:**
- [ ] Call FetchContent_MakeAvailable for both dependencies
- [ ] Add subdirectory for cpp-impl

**Content to implement:**
```cmake
FetchContent_MakeAvailable(parallel-hashmap libcuckoo)

# Add benchmark implementations
add_subdirectory(cpp-impl)
```

---

### Step 1.6: Create cpp-impl Directory Structure

**Tasks:**
- [ ] Create `cpp-impl/` directory
- [ ] Create `common/` directory for shared headers
- [ ] Create placeholder files

**Commands:**
```bash
mkdir -p cpp-impl
mkdir -p common
touch cpp-impl/CMakeLists.txt
touch cpp-impl/bench-phmap.cpp
touch cpp-impl/bench-libcuckoo.cpp
```

---

### Step 1.7: Create cpp-impl/CMakeLists.txt

**File:** `cpp-impl/CMakeLists.txt`

**Tasks:**
- [ ] Create bench-phmap executable
- [ ] Configure include directories (common, parallel-hashmap)
- [ ] Link pthread library

**Content to implement:**
```cmake
# bench-phmap
add_executable(bench-phmap bench-phmap.cpp)
target_include_directories(bench-phmap PRIVATE
    ${CMAKE_SOURCE_DIR}/common
    ${parallel-hashmap_SOURCE_DIR}
)
target_link_libraries(bench-phmap pthread)

# bench-libcuckoo
add_executable(bench-libcuckoo bench-libcuckoo.cpp)
target_include_directories(bench-libcuckoo PRIVATE
    ${CMAKE_SOURCE_DIR}/common
    ${libcuckoo_SOURCE_DIR}
)
target_link_libraries(bench-libcuckoo pthread)
```

---

### Step 1.8: Create Minimal Test Files

**File:** `cpp-impl/bench-phmap.cpp`

**Tasks:**
- [ ] Create minimal main() that includes parallel-hashmap
- [ ] Verify header inclusion works

**Content to implement:**
```cpp
#include <parallel_hashmap/phmap.h>
#include <cstdio>

int main() {
    phmap::parallel_flat_hash_map<int, int> map;
    map[1] = 100;
    printf("parallel-hashmap works: map[1] = %d\n", map[1]);
    return 0;
}
```

**File:** `cpp-impl/bench-libcuckoo.cpp`

**Tasks:**
- [ ] Create minimal main() that includes libcuckoo
- [ ] Verify header inclusion works

**Content to implement:**
```cpp
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
```

---

### Step 1.9: Build and Verify

**Tasks:**
- [ ] Create build directory
- [ ] Run CMake configuration
- [ ] Build both executables
- [ ] Run both executables to verify

**Commands:**
```bash
mkdir -p build
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)

# Verify
./cpp-impl/bench-phmap
./cpp-impl/bench-libcuckoo
```

**Expected output:**
```
parallel-hashmap works: map[1] = 100
libcuckoo works: map[1] = 100
```

---

### Step 1.10: Verify Optimization Flags

**Tasks:**
- [ ] Check compile_commands.json for correct flags
- [ ] Verify `-O3 -march=native -flto` present

**Commands:**
```bash
cat build/compile_commands.json | grep -o '"-O3\|"-march=native\|"-flto' | head -10
```

---

## Verification Checklist

- [ ] CMake configures without errors
- [ ] Both dependencies download successfully
- [ ] bench-phmap compiles and runs
- [ ] bench-libcuckoo compiles and runs
- [ ] Optimization flags present in compile_commands.json
- [ ] No compiler warnings with `-Wall -Wextra`

## Files Created

| File | Purpose |
|------|---------|
| `CMakeLists.txt` | Root build configuration |
| `cpp-impl/CMakeLists.txt` | C++ benchmark build rules |
| `cpp-impl/bench-phmap.cpp` | Minimal phmap test |
| `cpp-impl/bench-libcuckoo.cpp` | Minimal libcuckoo test |

## Next Phase

After verification, proceed to **Phase 2: Common Headers** to implement shared infrastructure (prng.h, timing.h, hasher.h, spinlock.h, etc.).
