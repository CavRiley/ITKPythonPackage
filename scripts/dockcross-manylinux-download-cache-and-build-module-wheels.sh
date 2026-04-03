#!/bin/bash

########################################################################
# Pull this script and run from an ITK external module root directory
# to generate the Linux Python wheels for the external module.
#
# ========================================================================
# PARAMETERS
#
# Versions can be restricted by passing them in as arguments to the script
# For example,
#
#   scripts/dockcross-manylinux-build-module-wheels.sh cp310
#
# ===========================================
# ENVIRONMENT VARIABLES
#
# These variables are set with the `export` bash command before calling the script.
#
# `ITKPYTHONPACKAGE_ORG`: Github organization for fetching ITKPythonPackage build scripts.
#
# `ITKPYTHONPACKAGE_TAG`: ITKPythonPackage tag for fetching build scripts.
#
# Additional environment variables may be defined in accompanying build scripts.
#
########################################################################

download_script_dir=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# if not specified, use the current directory for MODULE_SRC_DIRECTORY
MODULE_SRC_DIRECTORY=${MODULE_SRC_DIRECTORY:=${download_script_dir}}
# if not specified then use the a dummy MODULE_DEPENDENCIES directory in the build dashboard
MODULE_DEPS_DIR=${MODULE_DEPS_DIR:=${DASHBOARD_BUILD_DIRECTORY}/MODULE_DEPENDENCIES}
# -----------------------------------------------------------------------
# Script argument parsing
#
usage() {
  echo "Usage:
  dockcross-manylinux-download-cache-and-build-module-wheels
    [ -h | --help ]           show usage
    [ -c | --cmake_options ]  space-delimited string containing CMake options to forward to the module (e.g. \"-DBUILD_TESTING=OFF\")
    [ -x | --exclude_libs ]   semicolon-delimited library names to exclude when repairing wheel (e.g. \"libcuda.so\")
    [ python_version ]        build wheel for a specific python version. (e.g. cp310)"
  exit 2
}

PARSED_ARGS=$(getopt -a -n dockcross-manylinux-download-cache-and-build-module-wheels \
  -o hc:x: --long help,cmake_options:,exclude_libs: -- "$@")
eval set -- "$PARSED_ARGS"

while :; do
  case "$1" in
  -h | --help)
    usage
    ;;
  -c | --cmake_options)
    export CMAKE_OPTIONS="$2"
    shift 2
    ;;
  -x | --exclude_libs)
    export EXCLUDE_LIBS="$2"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Unexpected option: $1."
    usage
    ;;
  esac
done

#For backwards compatibility when the ITK_GIT_TAG was required to match the ITK_PACKAGE_VERSION
ITK_PACKAGE_VERSION=${ITK_PACKAGE_VERSION:="v6.0b02"}
ITK_GIT_TAG=${ITK_GIT_TAG:=${ITK_PACKAGE_VERSION}}

# -----------------------------------------------------------------------
# Set default values
MANYLINUX_VERSION=${MANYLINUX_VERSION:-_2_28}
TARGET_ARCH=${TARGET_ARCH:-x64}

ITKPYTHONPACKAGE_ORG=${ITKPYTHONPACKAGE_ORG:-InsightSoftwareConsortium}
ITKPYTHONPACKAGE_TAG=${ITKPYTHONPACKAGE_TAG:-main}

# -----------------------------------------------------------------------
# Check for conda/pixi-provided ITK (libitk-wrapping package).
# When available, skip the tarball download entirely.

_conda_itk_dir=""
for _prefix_var in CONDA_PREFIX PIXI_ENVIRONMENT_DIR; do
  _prefix="${!_prefix_var:-}"
  if [ -n "${_prefix}" ]; then
    for _candidate in "${_prefix}"/lib/cmake/ITK-*; do
      if [ -f "${_candidate}/ITKConfig.cmake" ]; then
        _conda_itk_dir="${_candidate}"
        echo "Detected conda-installed ITK at ${_conda_itk_dir} (via \$${_prefix_var})"
        break 2
      fi
    done
  fi
done

if [ -n "${_conda_itk_dir}" ]; then
  echo "Using conda-installed ITK; skipping tarball download."
  # Point to this repo's own scripts (already present on disk)
  untarred_ipp_dir=${download_script_dir}
  ITK_SOURCE_DIR=""
else
  # -----------------------------------------------------------------------
  # Download and extract cache (legacy tarball path)

  echo "Fetching https://raw.githubusercontent.com/${ITKPYTHONPACKAGE_ORG}/ITKPythonPackage/${ITKPYTHONPACKAGE_TAG}/scripts/dockcross-manylinux-download-cache.sh"
  curl -L "https://raw.githubusercontent.com/${ITKPYTHONPACKAGE_ORG}/ITKPythonPackage/${ITKPYTHONPACKAGE_TAG}/scripts/dockcross-manylinux-download-cache.sh" -O
  chmod u+x dockcross-manylinux-download-cache.sh
  _download_cmd="ITK_GIT_TAG=${ITK_GIT_TAG} \
      ITK_PACKAGE_VERSION=${ITK_PACKAGE_VERSION} \
      ITKPYTHONPACKAGE_ORG=${ITKPYTHONPACKAGE_ORG} \
      ITKPYTHONPACKAGE_TAG=${ITKPYTHONPACKAGE_TAG} \
      MANYLINUX_VERSION=${MANYLINUX_VERSION} \
      TARGET_ARCH=${TARGET_ARCH} \
      bash -x \
      ${download_script_dir}/dockcross-manylinux-download-cache.sh $1"
  echo "Running: ${_download_cmd}"
  eval "${_download_cmd}"

  #NOTE: in this scenario, untarred_ipp_dir is extracted from tarball
  #      during ${download_script_dir}/dockcross-manylinux-download-cache.sh
  untarred_ipp_dir=${download_script_dir}/ITKPythonPackage

  ITK_SOURCE_DIR=${download_script_dir}/ITKPythonPackage-build/ITK
fi

# -----------------------------------------------------------------------
# Build module wheels

echo "Building module wheels"

_bld_cmd="NO_SUDO=${NO_SUDO} \
    LD_LIBRARY_PATH=${LD_LIBRARY_PATH} \
    IMAGE_TAG=${IMAGE_TAG} \
    TARGET_ARCH=${TARGET_ARCH} \
    ITK_SOURCE_DIR=${ITK_SOURCE_DIR} \
    ITK_GIT_TAG=${ITK_GIT_TAG} \
    ITK_PACKAGE_VERSION=${ITK_PACKAGE_VERSION} \
    ITK_MODULE_PREQ=${ITK_MODULE_PREQ} \
    ITK_MODULE_NO_CLEANUP=${ITK_MODULE_NO_CLEANUP} \
    MODULE_SRC_DIRECTORY=${MODULE_SRC_DIRECTORY} \
    MODULE_DEPS_DIR=${MODULE_DEPS_DIR} \
    MANYLINUX_VERSION=${MANYLINUX_VERSION} \
    ${untarred_ipp_dir}/scripts/dockcross-manylinux-build-module-wheels.sh $*"
echo "Running: ${_bld_cmd}"
eval "${_bld_cmd}"
