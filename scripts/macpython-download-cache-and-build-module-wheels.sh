#!/bin/bash

########################################################################
# This module should be pulled and run from an ITK external module root directory
# to generate the Mac python wheels of this module.
#
# ========================================================================
# PARAMETERS
#
# Versions can be restricted by passing them in as arguments to the script.
# For example,
#
#   scripts/macpython-download-cache-and-build-module-wheels.sh 3.9 3.11
#
# Shared libraries can be included in the wheel by setting DYLD_LIBRARY_PATH before
# running this script.

# ===========================================
# ENVIRONMENT VARIABLES: ITK_GIT_TAG ITKPYTHONPACKAGE_ORG ITK_USE_LOCAL_PYTHON ITK_PACKAGE_VERSION
#
# These variables are set with the `export` bash command before calling the script.
# For example,
#   scripts/macpython-build-module-wheels.sh 3.9 3.10 3.11
#
########################################################################
DEFAULT_MODULE_DIRECTORY=$(cd $(dirname $0) || exit 1; pwd)
# if not specified, use the current directory for MODULE_SRC_DIRECTORY
MODULE_SRC_DIRECTORY=${MODULE_SRC_DIRECTORY:=${DEFAULT_MODULE_DIRECTORY}}

if [ -z "${ITK_PACKAGE_VERSION}" ]; then
   echo "MUST SET ITK_PACKAGE_VERSION BEFORE RUNNING THIS SCRIPT"
   exit -1
fi

DASHBOARD_BUILD_DIRECTORY=${DASHBOARD_BUILD_DIRECTORY:=/Users/svc-dashboard/D/P}
ITKPYTHONPACKAGE_ORG=${ITKPYTHONPACKAGE_ORG:=InsightSoftwareConsortium}
# Run build scripts
if [ -z "${NO_SUDO}" ] || [ ${NO_SUDO} -ne 1 ]; then
   sudo_exec=sudo
fi
if [ ! -d ${DASHBOARD_BUILD_DIRECTORY} ]; then
  ${sudo_exec} mkdir -p ${DASHBOARD_BUILD_DIRECTORY} && ${sudo_exec} chown $UID:$GID ${DASHBOARD_BUILD_DIRECTORY}
fi
cd ${DASHBOARD_BUILD_DIRECTORY}

# NOTE: download phase will install pixi in the DASHBOARD_BUILD_DIRECTORY (which is separate from the pixi
#       environment used by ITKPYthonPackagbe).
export PIXI_HOME=${DASHBOARD_BUILD_DIRECTORY}/.pixi
if [ ! -f  ${PIXI_HOME}/.pixi/bin/pixi ]; then
  # Install pixi
  curl -fsSL https://pixi.sh/install.sh | sh
  # These are the tools needed for cross platform downloads of the ITK build caches stored in https://github.com/InsightSoftwareConsortium/ITKPythonBuilds
  pixi global install zstd
  pixi global install aria2
  pixi global install gnu-tar
  pixi global install git
  pixi global install rsync
fi
export PATH="${PIXI_HOME}/.pixi/bin:$PATH"

if [[ $(arch) == "arm64" ]]; then
  tarball_arch="-arm64"
else
  tarball_arch=""
fi
# Fetch ITKPythonBuilds archive containing ITK build artifacts
echo "Fetching https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/${ITK_PACKAGE_VERSION}/ITKPythonBuilds-macosx${tarball_arch}.tar.zst"
local_compress_tarball_name=${DASHBOARD_BUILD_DIRECTORY}/ITKPythonBuilds-macosx${tarball_arch}_${ITK_PACKAGE_VERSION}.tar.zst
if [[ ! -f ${local_compress_tarball_name} ]]; then
        pixi run aria2c -c --file-allocation=none -d $(dirname ${local_compress_tarball_name}) -o $(basename ${local_compress_tarball_name}) -s 10 -x 10 https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/${ITK_PACKAGE_VERSION}/ITKPythonBuilds-macosx${tarball_arch}.tar.zst
fi
local_tarball_name=${DASHBOARD_BUILD_DIRECTORY}/ITKPythonBuilds-macosx${tarball_arch}_${ITK_PACKAGE_VERSION}.tar
pixi run unzstd --long=31 ${local_compress_tarball_name} -o ${local_tarball_name}
PATH="$(dirname $(brew list gnu-tar |grep gtar |grep "/bin/")):$PATH"
pixi run tar xf ${local_tarball_name} --warning=no-unknown-keyword --checkpoint=10000 --checkpoint-action=dot
rm ${local_tarball_name}

# Optional: Update build scripts
if [[ -n ${ITKPYTHONPACKAGE_TAG} ]]; then
  echo "Updating build scripts to ${ITKPYTHONPACKAGE_ORG}/ITKPythonPackage@${ITKPYTHONPACKAGE_TAG}"
  local_clone_ipp=${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage_${ITKPYTHONPACKAGE_TAG}
  if [ ! -d ${local_clone_ipp}/.git ]; then
    pixi run git clone "https://github.com/${ITKPYTHONPACKAGE_ORG}/ITKPythonPackage.git" "${local_clone_ipp}"
  fi
  pushd ${local_clone_ipp}
    pixi run git checkout "${ITKPYTHONPACKAGE_TAG}"
    pixi run git reset origin/${ITKPYTHONPACKAGE_TAG} --hard
    pixi run git status
  popd
  pixi run rsync -av "${local_clone_ipp}/" "${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage/"
fi

echo "Building module wheels"
cd ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage
args=$@
echo "${args[@]}"
for py_indicator in ${args[@]}; do
   # The following line is to convert "py3.11|py311|cp311|3.11" -> py311 normalized form
   py_squashed_numeric=$(echo "${py_indicator}" |sed 's/py//g' |sed 's/cp//g' |sed 's/\.//g')
   pyenv=py${py_squashed_numeric}
   pixi run -e macosx-${pyenv} -- python \
           ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage/scripts/build_wheels.py \
           --platform-env macosx-${pyenv} \
           --lib-paths '' '' \
           --module-source-dir ${MODULE_SRC_DIRECTORY} \
           --module-dependencies-root-dir ${DASHBOARD_BUILD_DIRECTORY}/MODULE_DEPENDENCIES \
           --itk-module-deps "${ITK_MODULE_PREQ}" \
           --no-build-itk-tarball-cache \
           --build-dir-root ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build \
           --manylinux-version '' \
           --itk-git-tag ${ITK_PACKAGE_VERSION} \
           --itk-source-dir ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build/ITK \
           --itk-package-version ${ITK_PACKAGE_VERSION} \
           --itk-pythonpackage-org ${ITKPYTHONPACKAGE_ORG} \
           --itk-pythonpackage-tag ${ITKPYTHONPACKAGE_TAG} \
           --no-use-sudo \
           --no-use-ccache

           #Let this be automatically selected --macosx-deployment-target 10.7 \
done
