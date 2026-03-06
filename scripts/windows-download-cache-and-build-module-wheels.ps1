########################################################################
# Pull build dependencies and build an ITK external module on Windows.
#
# This script must be run in an x64 Developer PowerShell.
# See https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=vs-2022#developer-powershell
#
# -----------------------------------------------------------------------
# Positional parameters / named options:
#
# -python_version_minor  Python minor version (required).
#     For instance, for Python 3.11:
#     > windows-download-cache-and-build-module-wheels.ps1 -python_version_minor 11
#     or positionally:
#     > windows-download-cache-and-build-module-wheels.ps1 11
#
# -setup_options         pyproject.toml options forwarded to the build script.
#     For instance, to exclude a library during packaging:
#     > ... -setup_options "--exclude-libs nvcuda.dll"
#
# -cmake_options         CMake options passed to pyproject.toml for project configuration.
#     For instance:
#     > ... -cmake_options "-DRTK_USE_CUDA:BOOL=ON"
#
# -----------------------------------------------------------------------
# Environment variables used in this script:
#
# `$env:ITK_PACKAGE_VERSION`
#     Tag for the ITKPythonBuilds archive to download/use. Required.
#
# `$env:ITKPYTHONPACKAGE_TAG`
#     Tag for ITKPythonPackage build scripts to use.
#     If empty, the scripts bundled in the archive will be used.
#
# `$env:ITKPYTHONPACKAGE_ORG`
#     GitHub organization/user for ITKPythonPackage. Default: InsightSoftwareConsortium.
#     Ignored if ITKPYTHONPACKAGE_TAG is empty.
#
# `$env:ITK_MODULE_PREQ`
#     Colon-delimited list of ITK module dependencies.
#     Format: `<org>/<module>@<tag>:<org>/<module>@<tag>:...`
#     Example: `InsightSoftwareConsortium/ITKMeshToPolyData@v0.10.0`
#     Passed directly to build_wheels.py via --itk-module-deps.
#
# `$env:MODULE_SRC_DIRECTORY`
#     Path to the ITK external module source. Defaults to the directory
#     containing this script.
#
########################################################################
param (
  [int]$python_version_minor,
  [string]$setup_options = "",
  [string]$cmake_options = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate required inputs
if (-not $python_version_minor) {
  Write-Error "ERROR: -python_version_minor is required. Example: -python_version_minor 11"
  exit 1
}
if (-not $env:ITK_PACKAGE_VERSION) {
  Write-Error "ERROR: `$env:ITK_PACKAGE_VERSION must be set before running this script."
  exit 1
}

# Resolve configuration
$MODULE_SRC_DIRECTORY = if ($env:MODULE_SRC_DIRECTORY) {
  $env:MODULE_SRC_DIRECTORY
} else {
  $PSScriptRoot
}
echo "MODULE_SRC_DIRECTORY: $MODULE_SRC_DIRECTORY"

$ITK_PACKAGE_VERSION   = $env:ITK_PACKAGE_VERSION
$ITKPYTHONPACKAGE_ORG  = if ($env:ITKPYTHONPACKAGE_ORG) { $env:ITKPYTHONPACKAGE_ORG } else { "InsightSoftwareConsortium" }
$ITKPYTHONPACKAGE_TAG  = if ($env:ITKPYTHONPACKAGE_TAG)  { $env:ITKPYTHONPACKAGE_TAG  } else { "" }

$DASHBOARD_BUILD_DIRECTORY = "C:\BDR"
$platformEnv = "win-py3$python_version_minor"

echo "Python version     : 3.$python_version_minor"
echo "ITK_PACKAGE_VERSION: $ITK_PACKAGE_VERSION"
echo "Platform env       : $platformEnv"

# Install pixi
# NOTE: Python and Doxygen are provided by the pixi environment; no need to
#       install them separately here.
$env:PIXI_HOME = "$DASHBOARD_BUILD_DIRECTORY\.pixi"
if (-not (Test-Path "$env:PIXI_HOME\bin\pixi.exe")) {
  echo "Installing pixi..."
  Invoke-WebRequest -Uri "https://pixi.sh/install.ps1" -OutFile "install-pixi.ps1"
  powershell -ExecutionPolicy Bypass -File "install-pixi.ps1"
}
$env:Path = "$env:PIXI_HOME\bin;$env:Path"

# Download ITKPythonBuilds archive (skip if already cached)
$zipName        = "ITKPythonBuilds-windows.zip"
$zipDownloadUrl = "https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/$ITK_PACKAGE_VERSION/$zipName"
$localZipName   = "ITKPythonBuilds-windows_${ITK_PACKAGE_VERSION}.zip"

if (Test-Path $localZipName) {
  echo "Found cached archive: $localZipName -- skipping download."
} else {
  echo "Downloading $zipDownloadUrl ..."
  Invoke-WebRequest -Uri $zipDownloadUrl -OutFile $localZipName
}

# Unpack archive
# Expected layout after extraction under $DASHBOARD_BUILD_DIRECTORY:
#   \ITK                          ITK source tree
#   \build\<cached-itk-build>     pre-built ITK artifacts
#   \IPP                          ITKPythonPackage scripts
if (Test-Path $DASHBOARD_BUILD_DIRECTORY) {
  echo "Removing existing build directory: $DASHBOARD_BUILD_DIRECTORY"
  Remove-Item -Recurse -Force $DASHBOARD_BUILD_DIRECTORY
}
echo "Extracting archive to $DASHBOARD_BUILD_DIRECTORY ..."
Expand-Archive -Path $localZipName -DestinationPath $DASHBOARD_BUILD_DIRECTORY -Force

# ---------------------------------------------------------------------------
# Optional: overlay ITKPythonPackage build scripts from a specific tag
# ---------------------------------------------------------------------------
if ($ITKPYTHONPACKAGE_TAG) {
  echo "Updating build scripts to $ITKPYTHONPACKAGE_ORG/ITKPythonPackage@$ITKPYTHONPACKAGE_TAG"

  $ippTmpDir   = "$DASHBOARD_BUILD_DIRECTORY\IPP-tmp"
  $ippCloneUrl = "https://github.com/$ITKPYTHONPACKAGE_ORG/ITKPythonPackage.git"

  if (-not (Test-Path "$ippTmpDir\.git")) {
    git clone $ippCloneUrl $ippTmpDir
  }

  pushd $ippTmpDir
    git checkout $ITKPYTHONPACKAGE_TAG
    git reset "origin/$ITKPYTHONPACKAGE_TAG" --hard
    git status
  popd

  Copy-Item -Recurse -Force "$ippTmpDir\*" "$DASHBOARD_BUILD_DIRECTORY\IPP\"
  Remove-Item -Recurse -Force $ippTmpDir
}

# Assemble paths used by build_wheels.py
$ippDir        = "$DASHBOARD_BUILD_DIRECTORY\IPP"
$buildScript   = "$ippDir\scripts\build_wheels.py"
# build_wheels.py expects the cached ITK build at <build-dir-root>\build\ITK-windows-py3XX-...
# Since the zip extracts directly into BDR (i.e. BDR\build\ITK-windows-py311-...), BDR is the root.
$buildDirRoot  = $DASHBOARD_BUILD_DIRECTORY
$itkSourceDir  = "$DASHBOARD_BUILD_DIRECTORY\ITK"
$moduleDepsDir = "$DASHBOARD_BUILD_DIRECTORY\MDEPS"

# Build the module wheel via pixi
$build_command  = "pixi run -e `"$platformEnv`" --manifest-path `"$ippDir\pixi.toml`" python `"$buildScript`""
$build_command += " --platform-env `"$platformEnv`""
$build_command += " --module-source-dir `"$MODULE_SRC_DIRECTORY`""
$build_command += " --module-dependencies-root-dir `"$moduleDepsDir`""
$build_command += " --itk-module-deps `"$env:ITK_MODULE_PREQ`""
$build_command += " --no-build-itk-tarball-cache"
$build_command += " --build-dir-root `"$buildDirRoot`""
$build_command += " --manylinux-version `"`""
$build_command += " --itk-git-tag `"$ITK_PACKAGE_VERSION`""
$build_command += " --itk-source-dir `"$itkSourceDir`""
$build_command += " --itk-package-version `"$ITK_PACKAGE_VERSION`""
$build_command += " --itk-pythonpackage-org `"$ITKPYTHONPACKAGE_ORG`""
$build_command += " --itk-pythonpackage-tag `"$ITKPYTHONPACKAGE_TAG`""
$build_command += " --no-use-ccache"
$build_command += " --skip-itk-build"
$build_command += " --skip-itk-wheel-build"

if ($setup_options.Length -gt 0) {
  $build_command += " $setup_options"
}
if ($cmake_options.Length -gt 0) {
  $build_command += " -- $cmake_options"
}

echo "Build command: $build_command"
echo "Building target module ..."
iex $build_command