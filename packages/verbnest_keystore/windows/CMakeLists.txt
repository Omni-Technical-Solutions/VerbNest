# NOT BUILT OR TESTED YET (FR-HTTP-013f phase K). The plugin is not listed for
# windows in ../pubspec.yaml, so Flutter does not compile this until that entry
# is added (see docs/release/keystore-linux-windows.md).
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "verbnest_keystore")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "verbnest_keystore_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/verbnest_keystore/verbnest_keystore_plugin_c_api.h"
  "verbnest_keystore_plugin_c_api.cpp"
  "verbnest_keystore_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  secur32 crypt32 ncrypt ws2_32)

set(verbnest_keystore_bundled_libraries "" PARENT_SCOPE)
