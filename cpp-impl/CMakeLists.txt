# Compiler warnings
add_compile_options(-Wall -Wextra)

# bench-phmap
add_executable(bench-phmap bench-phmap.cpp)
target_include_directories(bench-phmap PRIVATE ${CMAKE_SOURCE_DIR}/common)
target_include_directories(bench-phmap SYSTEM PRIVATE ${parallel-hashmap_SOURCE_DIR})
target_link_libraries(bench-phmap pthread)

# bench-libcuckoo
add_executable(bench-libcuckoo bench-libcuckoo.cpp)
target_include_directories(bench-libcuckoo PRIVATE ${CMAKE_SOURCE_DIR}/common)
target_include_directories(bench-libcuckoo SYSTEM PRIVATE ${libcuckoo_SOURCE_DIR})
target_link_libraries(bench-libcuckoo pthread)
