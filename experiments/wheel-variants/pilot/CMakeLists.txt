cmake_minimum_required(VERSION 3.16)
project(itk_variant_demo LANGUAGES CXX)

find_package(Python COMPONENTS Interpreter Development.Module REQUIRED)
find_package(pybind11 CONFIG REQUIRED)

# Variant axis: TBB on/off. The CMake define is propagated by the build
# driver via --config-setting=cmake.define.ITK_VARIANT_DEMO_TBB=ON|OFF.
option(ITK_VARIANT_DEMO_TBB "Mark this build as a TBB-enabled variant" OFF)

pybind11_add_module(_demo MODULE src/itk_variant_demo/_demo.cpp)
target_compile_definitions(_demo PRIVATE
  ITK_VARIANT_DEMO_TBB=$<IF:$<BOOL:${ITK_VARIANT_DEMO_TBB}>,1,0>)

install(TARGETS _demo LIBRARY DESTINATION itk_variant_demo)
