cmake_minimum_required(VERSION 3.16)
project(concurrent_hashmap_bench CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Release by default
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Optimization flags
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto -DNDEBUG")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)

# FetchContent for dependencies
include(FetchContent)

FetchContent_Declare(
    parallel-hashmap
    GIT_REPOSITORY https://github.com/greg7mdp/parallel-hashmap.git
    GIT_TAG        v2.0.0
    GIT_SHALLOW    ON
)

FetchContent_Declare(
    libcuckoo
    GIT_REPOSITORY https://github.com/efficient/libcuckoo.git
    GIT_TAG        master
    GIT_SHALLOW    ON
)

FetchContent_MakeAvailable(parallel-hashmap libcuckoo)

# Add benchmark implementations
add_subdirectory(cpp-impl)
