# NOTES: Building tarballs requires specific pathing for supporting github CI
#        workflows

PLATFORM=$(uname -s)

ITK_GIT_TAG=${ITK_GIT_TAG:=v6.0b02}

case ${PLATFORM} in
  Darwin)
    PLATFORM_PREFIX="macos"
    DASHBOARD_BUILD_DIRECTORY=${DASHBOARD_BUILD_DIRECTORY:=/Users/svc-dashboard/D/P}
    ;;
  Linux)
    PLATFORM_PREFIX="linux"
    DASHBOARD_BUILD_DIRECTORY=$(cd $(dirname $0) || exit 1; pwd)
    ;;
#  POSIX build env NOT SUPPORTED for windows, Needs to be done in a .ps1 shell
#  MINGW*|MSYS*|CYGWIN*)
#    PLATFORM_PREFIX="windows"
#    DASHBOARD_BUILD_DIRECTORY="C:\P"
#    ;;
  *)
    echo "Unsupported platform: ${PLATFORM}"
    exit 1
    ;;
esac

# Required environment variables
required_vars=(
  ITK_GIT_TAG
  PLATFORM_PREFIX
  DASHBOARD_BUILD_DIRECTORY

)

# Sanity Validation loop
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: Required environment variable '$v' is not set or empty."
    exit 1
  fi
done

if [ ! -d ${DASHBOARD_BUILD_DIRECTORY} ]; then
  # This is the expected directory for the cache
  mkdir -p ${DASHBOARD_BUILD_DIRECTORY}
fi
script_dir=$(cd $(dirname $0) || exit 1; pwd)
if [ "${script_dir}" !=  "${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage/scripts" ]; then
   echo "ERROR: Github CI requires rigid directory structure"
   echo "  RUN: git checkout git@github.com:InsightSoftwareConsortium/ITKPythonPackage.git ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage"
   echo "  RUN: ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage/scripts/make_tarballs.sh"
   exit 1
fi

export PIXI_HOME=${DASHBOARD_BUILD_DIRECTORY}/.pixi
if [ ! -f ${PIXI_HOME}/bin/pixi ]; then
  #PIXI INSTALL
  if [ ! -f  ${PIXI_HOME}/bin/pixi ]; then
    curl -fsSL https://pixi.sh/install.sh | sh
    export PATH="${PIXI_HOME}/bin:$PATH"
  fi
fi

for pyenv in py39 py310 py311; do
  cd ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage
  ${PIXI_HOME}/bin/pixi run -e ${PLATFORM_PREFIX}-${pyenv} \
          python3 scripts/build_wheels.py \
          --platform-env ${PLATFORM_PREFIX}-${pyenv} \
          --build-dir-root ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build \
          --itk-source-dir ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build/ITK \
          --itk-git-tag ${ITK_GIT_TAG} \
          --build-itk-tarball-cache
done
