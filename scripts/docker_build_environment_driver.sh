#!/bin/bash

# Required environment variables
required_vars=(
  ITK_GIT_TAG
  MANYLINUX_VERSION
  IMAGE_TAG
  TARGET_ARCH
  ITKPYTHONPACKAGE_ORG
  ITKPYTHONPACKAGE_TAG
  PY_ENVS
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

CONTAINER_WORK_DIR=/work
cd ${CONTAINER_WORK_DIR}
CONTAINER_PACKAGE_BUILD_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage-build
CONTAINER_PACKAGE_SCRIPTS_DIR=${CONTAINER_WORK_DIR}/ITKPythonPackage
CONTAINER_PACKAGE_DIST=${CONTAINER_PACKAGE_BUILD_DIR}/dist
ITK_SOURCE_DIR=${CONTAINER_PACKAGE_BUILD_DIR}/ITK

BUILD_WHEELS_EXTRA_FLAGS=${BUILD_WHEELS_EXTRA_FLAGS:=""}

echo "BUILD FOR ${PY_ENVS}"

for py_indicator in ${PY_ENVS}; do
  py_squashed_numeric=$(echo "${py_indicator}" |sed 's/py//g' |sed 's/cp//g' |sed 's/\.//g')
  manylinux_vername=$(echo ${MANYLINUX_VERSION} |sed 's/_//g')
  PIXI_ENV="manylinux${manylinux_vername}-py${py_squashed_numeric}"

  # Use pixi to ensure all required tools are installed and
  # visible in the PATH
  export PIXI_HOME=${CONTAINER_PACKAGE_SCRIPTS_DIR}/.pixi
  export PATH=${PIXI_HOME}/bin:${PATH}
  python3.12 ${CONTAINER_PACKAGE_SCRIPTS_DIR}/scripts/install_pixi.py --platform-env ${PIXI_ENV}

  cd ${CONTAINER_PACKAGE_SCRIPTS_DIR}
  pixi run -e ${PIXI_ENV} python3 \
    ${CONTAINER_PACKAGE_SCRIPTS_DIR}/scripts/build_wheels.py \
    --platform-env ${PIXI_ENV} \
    ${BUILD_WHEELS_EXTRA_FLAGS} \
   --build-dir-root ${CONTAINER_PACKAGE_BUILD_DIR} \
   --itk-source-dir ${ITK_SOURCE_DIR} \
   --itk-git-tag ${ITK_GIT_TAG} \
   --manylinux-version ${MANYLINUX_VERSION}

done
