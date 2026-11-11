cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "dropclip_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "dropclip_windows_plugin")

# The Win32 clipboard core lives in native/windows (T1.7). Flutter reaches this
# folder through .plugin_symlinks, so resolve the link before walking up.
get_filename_component(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
set(DROPCLIP_NATIVE_DIR "${PLUGIN_DIR}/../../../native/windows")

add_library(${PLUGIN_NAME} SHARED "dropclip_windows_plugin.cpp")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${DROPCLIP_NATIVE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(dropclip_windows_bundled_libraries "" PARENT_SCOPE)
