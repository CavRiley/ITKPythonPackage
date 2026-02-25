#!/bin/bash

########################################################################
# Run this script to build the Python wheel packages for Linux for an ITK
# external module.
#
# ========================================================================
# REQUIRED ENVIRONMENT VARIABLES:
#   ITK_PACKAGE_VERSION    - Version of ITK to build against
#
# OPTIONAL ENVIRONMENT VARIABLES:
#   MANYLINUX_VERSION      - Manylinux version (default: _2_28)
#   IMAGE_TAG              - Docker image tag (default: 20250913-6ea98ba)
#   TARGET_ARCH            - Target architecture (default: x64)
#   ITKPYTHONPACKAGE_ORG   - GitHub org (default: InsightSoftwareConsortium)
#   ITKPYTHONPACKAGE_TAG   - Git tag/branch (default: main)
#   ITK_MODULE_PREQ        - Colon-delimited list of prerequisite modules
#   LD_LIBRARY_PATH        - Additional library paths to mount
#   NO_SUDO                - Set to 1 to skip sudo for docker commands
#
# DIRECTORY STRUCTURE (expected):
#   ${IPP_DIR}/                              <- ITKPythonPackage
#   ${BUILD_DIR}/                            <- ITKPythonPackage-manylinux${VERSION}-build
#   ${MODULE_SOURCE_DIR}/                    <- Module source (current directory)
########################################################################

script_dir=$(cd "$(dirname "$0")" || exit 1; pwd)
_ipp_dir=$(dirname "${script_dir}")

# -----------------------------------------------------------------------
# Find container runtime
for cand in nerdctl docker podman; do
  which ${cand} > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    export OCI_EXE=${OCI_EXE:-"$cand"}
    break
  fi
done

if [ -z "${OCI_EXE}" ]; then
  echo "ERROR: No container runtime found. Please install docker, podman, or nerdctl."
  exit 1
fi
echo "Found OCI_EXE=$(which "${OCI_EXE}")"

# -----------------------------------------------------------------------
# Set default values
MANYLINUX_VERSION=${MANYLINUX_VERSION:-_2_28}
IMAGE_TAG=${IMAGE_TAG:-20250913-6ea98ba}
TARGET_ARCH=${TARGET_ARCH:-x64}
ITKPYTHONPACKAGE_ORG=${ITKPYTHONPACKAGE_ORG:-InsightSoftwareConsortium}
ITKPYTHONPACKAGE_TAG=${ITKPYTHONPACKAGE_TAG:-main}

# For backwards compatibility
ITK_GIT_TAG=${ITK_GIT_TAG:-${ITK_PACKAGE_VERSION}}

# Required environment variables
required_vars=(
  ITK_GIT_TAG
  MANYLINUX_VERSION
  IMAGE_TAG
  TARGET_ARCH
  ITKPYTHONPACKAGE_ORG
  ITKPYTHONPACKAGE_TAG
)
# Sanity Validation loop
_missing_required=0
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    _missing_required=1
    echo "ERROR: Required environment variable '$v' is not set or empty."
  fi
done
if [ $_missing_required -ne 0 ]; then
    exit 1
fi
unset _missing_required


# Create dockercross script
mkdir -p "${_ipp_dir}"/build
_local_dockercross_script=${_ipp_dir}/build/runner_dockcross-${MANYLINUX_VERSION}-${TARGET_ARCH}_${IMAGE_TAG}.sh
cd "$(dirname "${_ipp_dir}")"

# Generate dockcross scripts
$OCI_EXE run \
             --rm docker.io/dockcross/manylinux"${MANYLINUX_VERSION}"-"${TARGET_ARCH}":"${IMAGE_TAG}" > "${_local_dockercross_script}"
chmod u+x ${_local_dockercross_script}


# NOTE: Directory must be in ${MODULE_ROOT_DIR}/ITKPythonPackage/scripts
#                                     ^        |        ^       |   ^
#                         HOST_MODULE_DIRECTORY|    _ipp_dir    |scripts_dir
#HOST_MODULE_DIRECTORY=$(dirname ${_ipp_dir})
HOST_MODULE_DIRECTORY=${MODULE_SRC_DIRECTORY}

# Set up paths and variables for build
#HOST_MODULE_TOOLS_DIR=${HOST_MODULE_DIRECTORY}/tools
#mkdir -p  ${HOST_MODULE_TOOLS_DIR}
#chmod 777 ${HOST_MODULE_TOOLS_DIR}

CONTAINER_WORK_DIR=/work
CONTAINER_PACKAGE_BUILD_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage-build
CONTAINER_PACKAGE_SCRIPTS_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage
HOST_PACKAGE_BUILD_DIR=$(dirname "${_ipp_dir}")/ITKPythonPackage-build
HOST_PACKAGE_SCRIPTS_DIR=${_ipp_dir}

CONTAINER_ITK_SOURCE_DIR=${CONTAINER_PACKAGE_BUILD_DIR}/ITK
HOST_PACKAGE_DIST=${HOST_MODULE_DIRECTORY}/dist
mkdir -p "${HOST_PACKAGE_DIST}"
CONTAINER_MODULE_DIR=${CONTAINER_WORK_DIR}/$(basename "${MODULE_SRC_DIRECTORY}")
CONTAINER_MODULE_DEPS_DIR=${CONTAINER_WORK_DIR}/$(basename "${MODULE_DEPS_DIR}")

# Build docker arguments
DOCKER_ARGS=" --network=host "
DOCKER_ARGS+=" -v ${HOST_PACKAGE_BUILD_DIR}:${CONTAINER_PACKAGE_BUILD_DIR} "
DOCKER_ARGS+=" -v ${HOST_PACKAGE_SCRIPTS_DIR}:${CONTAINER_PACKAGE_SCRIPTS_DIR} "
DOCKER_ARGS+=" -v ${MODULE_SRC_DIRECTORY}:${CONTAINER_MODULE_DIR} "
DOCKER_ARGS+=" -v ${MODULE_DEPS_DIR}:${CONTAINER_MODULE_DEPS_DIR} "

if [ "${ITK_SOURCE_DIR}" != "" ]; then
  DOCKER_ARGS+=" -v ${ITK_SOURCE_DIR}:${CONTAINER_ITK_SOURCE_DIR} "
fi

# Environment variables for the container
DOCKER_ARGS+=" -e PYTHONUNBUFFERED=1 "
DOCKER_ARGS+=" -e CMAKE_OPTIONS='${CMAKE_OPTIONS}' "

# Mount shared libraries if LD_LIBRARY_PATH is set
if [[ -n ${LD_LIBRARY_PATH} ]]; then
  for libpath in ${LD_LIBRARY_PATH//:/ }; do
          DOCKER_LIBRARY_PATH="/usr/lib64/$(basename -- ${libpath})"
          DOCKER_ARGS+=" -v ${libpath}:${DOCKER_LIBRARY_PATH}"
          if test -d ${libpath}; then
              DOCKER_LD_LIBRARY_PATH+="${DOCKER_LIBRARY_PATH}:${DOCKER_LD_LIBRARY_PATH}"
          fi
  done
fi
export LD_LIBRARY_PATH="${DOCKER_LD_LIBRARY_PATH}"

# To build tarballs in manylinux, use 'export BUILD_WHEELS_EXTRA_FLAGS=" --build-itk-tarball-cache "'
BUILD_WHEELS_EXTRA_FLAGS=${BUILD_WHEELS_EXTRA_FLAGS:=""} # No tarball by default

PY_ENVS=("${@:-py310}")

# When building ITK remote wheels, --module-source-dir, --module-dependancies-root-dir, and --itk-module-deps should be present
cmd=$(echo bash -x ${_local_dockercross_script} \
  -a \"$DOCKER_ARGS\" \
   /usr/bin/env \
     PY_ENVS=\"${PY_ENVS}\" \
     ITK_GIT_TAG=\"${ITK_GIT_TAG}\" \
     ITK_PACKAGE_VERSION=\"${ITK_PACKAGE_VERSION}\" \
     ITK_MODULE_PREQ=\"${ITK_MODULE_PREQ}\" \
     MODULE_SRC_DIRECTORY=\"${CONTAINER_MODULE_DIR}\" \
     MODULE_DEPS_DIR=\"${CONTAINER_MODULE_DEPS_DIR}\" \
     MANYLINUX_VERSION=\"${MANYLINUX_VERSION}\" \
     IMAGE_TAG=\"${IMAGE_TAG}\" \
     TARGET_ARCH=\"${TARGET_ARCH}\" \
     ITKPYTHONPACKAGE_ORG=\"${ITKPYTHONPACKAGE_ORG}\" \
     ITKPYTHONPACKAGE_TAG=\"${ITKPYTHONPACKAGE_TAG}\" \
     BUILD_WHEELS_EXTRA_FLAGS=\"${BUILD_WHEELS_EXTRA_FLAGS}\" \
     /bin/bash -x "${CONTAINER_PACKAGE_SCRIPTS_DIR}"/scripts/docker_build_environment_driver.sh
)

echo "RUNNING: $cmd"
eval "$cmd"
