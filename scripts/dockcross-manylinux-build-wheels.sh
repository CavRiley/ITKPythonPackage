#!/bin/bash
# Run this script to build the ITK Python wheel packages for Linux.
#
# Versions can be restricted by passing them in as arguments to the script
# For example,
#
#   scripts/dockcross-manylinux-build-wheels.sh cp39
#
# A specialized manylinux image and tag can be used by setting
# MANYLINUX_VERSION and IMAGE_TAG
#
# For example,
#   scripts/dockcross-manylinux-build-module-wheels.sh cp39
#
script_dir=$(cd $(dirname $0) || exit 1; pwd)
_ipp_dir=$(dirname ${script_dir})

for cand in nerdctl docker podman; do
  which ${cand} > /dev/null
  if [ $? -eq 0 ]; then
    export OCI_EXE=${OCI_EXE:="$cand"}
    break
  fi
done
echo "FOUND OCI_EXE=$(which ${OCI_EXE})"

#TODO: This needs updating to pass along values to
ITK_GIT_TAG=${ITK_GIT_TAG:="main"}
MANYLINUX_VERSION=${MANYLINUX_VERSION:=_2_28}
IMAGE_TAG=${IMAGE_TAG:=20250913-6ea98ba}
TARGET_ARCH=${TARGET_ARCH:=x64}
ITKPYTHONPACKAGE_ORG=${ITKPYTHONPACKAGE_ORG:=InsightSoftwareConsortium}
ITKPYTHONPACKAGE_TAG=${ITKPYTHONPACKAGE_TAG:=main}

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

mkdir -p ${_ipp_dir}/build
_local_dockercross_script=${_ipp_dir}/build/runner_dockcross-${MANYLINUX_VERSION}-x64_${IMAGE_TAG}.sh
cd $(dirname ${_ipp_dir})

# Generate dockcross scripts
$OCI_EXE run \
             --rm docker.io/dockcross/manylinux${MANYLINUX_VERSION}-x64:${IMAGE_TAG} > ${_local_dockercross_script}
chmod u+x ${_local_dockercross_script}

# Build wheels in dockcross environment
CONTAINER_WORK_DIR=/work
CONTAINER_PACKAGE_BUILD_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage-build
CONTAINER_PACKAGE_SCRIPTS_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage
CONTAINER_ITK_SOURCE_DIR=${CONTAINER_PACKAGE_BUILD_DIR}/ITK

HOST_PACKAGE_SCRIPTS_DIR=${_ipp_dir}
HOST_PACKAGE_BUILD_DIR=$(dirname ${_ipp_dir})/ITKPythonPackage-manylinux${MANYLINUX_VERSION}-build
mkdir -p ${HOST_PACKAGE_BUILD_DIR}

DOCKER_ARGS="  -v ${HOST_PACKAGE_BUILD_DIR}:${CONTAINER_PACKAGE_BUILD_DIR} "
DOCKER_ARGS+=" -v ${HOST_PACKAGE_SCRIPTS_DIR}:${CONTAINER_PACKAGE_SCRIPTS_DIR} "
if [ "${ITK_SOURCE_DIR}" != "" ]; then
  DOCKER_ARGS+=" -v${ITK_SOURCE_DIR}:${CONTAINER_ITK_SOURCE_DIR} "
fi
DOCKER_ARGS+=" -e PYTHONUNBUFFERED=1 " # Turn off buffering of outputs in python

# To build tarballs in manylinux, use 'export BUILD_WHEELS_EXTRA_FLAGS=" --build-itk-tarball-cache "'
BUILD_WHEELS_EXTRA_FLAGS=${BUILD_WHEELS_EXTRA_FLAGS:=""} # No tarball by default

# If args are given, use them. Otherwise use default python environments
PY_ENVS=("${@:-py39 py310 py311}")

# When building ITK wheels, --module-source-dir, --module-dependancies-root-dir, and --itk-module-deps to be empty
cmd=$(echo bash -x ${_local_dockercross_script} \
  -a \"$DOCKER_ARGS\" \
   /usr/bin/env \
     PY_ENVS=\"${PY_ENVS}\" \
     ITK_GIT_TAG=\"${ITK_GIT_TAG}\" \
     MANYLINUX_VERSION=\"${MANYLINUX_VERSION}\" \
     IMAGE_TAG=\"${IMAGE_TAG}\" \
     TARGET_ARCH=\"${TARGET_ARCH}\" \
     ITKPYTHONPACKAGE_ORG=\"${ITKPYTHONPACKAGE_ORG}\" \
     ITKPYTHONPACKAGE_TAG=\"${ITKPYTHONPACKAGE_ORG}\" \
     BUILD_WHEELS_EXTRA_FLAGS=\"${BUILD_WHEELS_EXTRA_FLAGS}\" \
     /bin/bash -x ${CONTAINER_PACKAGE_SCRIPTS_DIR}/scripts/docker_build_environment_driver.sh
)
echo "RUNNING: $cmd"
eval $cmd
