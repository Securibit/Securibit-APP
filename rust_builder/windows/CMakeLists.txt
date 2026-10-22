# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "securibit_api")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
# Flutter 用 windows/flutter/ephemeral/.plugin_symlinks/securibit_api 這個捷徑（symlink）指到 rust_builder，
# Windows 解析 .. 時不會先跟著捷徑走（Linux 的 ../../rust/api 在這裡會變成 .plugin_symlinks/rust/api），
# 所以從捷徑的位置往上六層回到專案根目錄（和 flutter_rust_bridge 的 Windows 範本相同）
apply_cargokit(${PROJECT_NAME} ../../../../../../rust/api securibit_api "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(securibit_api_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
