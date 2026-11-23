# NOT BUILT OR TESTED YET (FR-HTTP-013f phase J). The plugin is not listed for
# linux in ../pubspec.yaml, so Flutter does not compile this until that entry
# is added (see docs/release/keystore-linux-windows.md).
cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "verbnest_keystore")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "verbnest_keystore_plugin")

find_package(PkgConfig REQUIRED)
pkg_check_modules(GNUTLS REQUIRED IMPORTED_TARGET gnutls)

add_library(${PLUGIN_NAME} SHARED "verbnest_keystore_plugin.cc")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GNUTLS)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

set(verbnest_keystore_bundled_libraries "" PARENT_SCOPE)
