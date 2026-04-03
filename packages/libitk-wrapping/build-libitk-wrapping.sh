#!/bin/bash
set -euo pipefail

# Build ITK C++ with Python wrapping for use as a conda package.
# This produces headers, shared libraries, CMake config, and all
# wrapping metadata (SWIG .i/.idx/.mdx files, Python stubs) needed
# by downstream ITK remote modules.

BUILD_DIR="${SRC_DIR}/../build"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Use TBB on Linux; macOS has known issues with conda TBB
use_tbb=ON
if [ "$(uname)" = "Darwin" ]; then
  use_tbb=OFF
fi

# Handle cross-compilation try-run results if available
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]]; then
  try_run_results="${RECIPE_DIR}/TryRunResults-${target_platform}.cmake"
  if [[ -f "${try_run_results}" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -C ${try_run_results}"
  fi
fi

cmake \
  -G "Ninja" \
  ${CMAKE_ARGS} \
  -D BUILD_SHARED_LIBS:BOOL=ON \
  -D BUILD_TESTING:BOOL=OFF \
  -D BUILD_EXAMPLES:BOOL=OFF \
  -D CMAKE_BUILD_TYPE:STRING=Release \
  -D "CMAKE_INSTALL_PREFIX=${PREFIX}" \
  \
  -D ITK_WRAP_PYTHON:BOOL=ON \
  -D ITK_WRAP_DOC:BOOL=ON \
  -D ITK_LEGACY_SILENT:BOOL=ON \
  -D CMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON \
  \
  -D ITK_WRAP_unsigned_short:BOOL=ON \
  -D ITK_WRAP_double:BOOL=ON \
  -D ITK_WRAP_complex_double:BOOL=ON \
  -D "ITK_WRAP_IMAGE_DIMS:STRING=2;3;4" \
  \
  -D WRAP_ITK_INSTALL_COMPONENT_IDENTIFIER:STRING=PythonWheel \
  -D WRAP_ITK_INSTALL_COMPONENT_PER_MODULE:BOOL=ON \
  \
  -D ITK_USE_SYSTEM_EXPAT:BOOL=ON \
  -D ITK_USE_SYSTEM_HDF5:BOOL=ON \
  -D ITK_USE_SYSTEM_JPEG:BOOL=ON \
  -D ITK_USE_SYSTEM_PNG:BOOL=ON \
  -D ITK_USE_SYSTEM_TIFF:BOOL=ON \
  -D ITK_USE_SYSTEM_ZLIB:BOOL=ON \
  -D ITK_USE_SYSTEM_FFTW:BOOL=ON \
  -D ITK_USE_SYSTEM_EIGEN:BOOL=ON \
  -D ITK_USE_FFTWD:BOOL=ON \
  -D ITK_USE_FFTWF:BOOL=ON \
  \
  -D ITK_BUILD_DEFAULT_MODULES:BOOL=ON \
  -D Module_ITKReview:BOOL=ON \
  -D Module_ITKTBB:BOOL=${use_tbb} \
  -D Module_MGHIO:BOOL=ON \
  -D Module_ITKIOTransformMINC:BOOL=ON \
  -D Module_GenericLabelInterpolator:BOOL=ON \
  -D Module_AdaptiveDenoising:BOOL=ON \
  \
  -D ITK_USE_KWSTYLE:BOOL=OFF \
  -D NIFTI_SYSTEM_MATH_LIB= \
  -D GDCM_USE_COREFOUNDATION_LIBRARY:BOOL=OFF \
  -D "ITK_DEFAULT_THREADER:STRING=Pool" \
  \
  "${SRC_DIR}"

cmake --build . --config Release

cmake --install . --config Release
