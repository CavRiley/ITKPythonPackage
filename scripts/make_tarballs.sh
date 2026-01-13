# NOTES: Building tarballs requires specific pathing for supporting github CI
#        workflows


ITK_GIT_TAG=${ITK_GIT_TAG:=v6.0b02}

# If args are given, use them. Otherwise use default python environments
pyenvs=("${@:-py39 py310 py311}")


case "$(uname -s)" in
  Darwin)
    PLATFORM_PREFIX="macos"
    DASHBOARD_BUILD_DIRECTORY=${DASHBOARD_BUILD_DIRECTORY:=/Users/svc-dashboard/D/P}
    ;;
  Linux)
    PLATFORM_PREFIX="linux"
    DASHBOARD_BUILD_DIRECTORY=${DASHBOARD_BUILD_DIRECTORY:=/work}
    ;;
#  POSIX build env NOT SUPPORTED for windows, Needs to be done in a .ps1 shell
#  MINGW*|MSYS*|CYGWIN*)
#    PLATFORM_PREFIX="windows"
#    DASHBOARD_BUILD_DIRECTORY="C:\P"
#    ;;
  *)
    echo "Unsupported platform: $(uname -s)"
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

for pyenv in ${pyenvs[@]}; do
  cd ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage
  ${PIXI_HOME}/bin/pixi run -e ${PLATFORM_PREFIX}-${pyenv} \
          python3 scripts/build_wheels.py \
          --platform-env ${PLATFORM_PREFIX}-${pyenv} \
          --build-dir-root ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build \
          --itk-source-dir ${DASHBOARD_BUILD_DIRECTORY}/ITKPythonPackage-build/ITK \
          --itk-git-tag ${ITK_GIT_TAG} \
          --build-itk-tarball-cache
done
