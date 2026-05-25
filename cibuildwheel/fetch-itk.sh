#!/usr/bin/env bash
# Resolve a pre-built ITK from ITKPythonBuilds and unpack it for a cibuildwheel
# remote-module build. Designed to be called from a module's [tool.cibuildwheel]
# before-all. Prints the suggested ITK_DIR (the cp311 build tree) as the LAST
# line of stdout.
#
# Inputs (environment):
#   ITK_PACKAGE_VERSION       Release tag, e.g. v6.0b02 (required).
#   ITKPYTHONBUILDS_TARBALL   Optional absolute path to a local .tar.zst; if set,
#                             skips the download (offline dev).
#   ITKPYTHONBUILDS_CACHE     Cache root (default: ~/.cache/itk-python-builds).
#
# v1 scope: macOS arm64 only.
set -euo pipefail

: "${ITK_PACKAGE_VERSION:?set ITK_PACKAGE_VERSION (e.g. v6.0b02)}"
CACHE_ROOT="${ITKPYTHONBUILDS_CACHE:-$HOME/.cache/itk-python-builds}"

# --- platform/arch -> asset name (v1: macOS arm64 only) -------------------
os="$(uname -s)"
arch="$(uname -m)"
if [ "$os" != "Darwin" ] || [ "$arch" != "arm64" ]; then
  echo "fetch-itk.sh v1 supports macOS arm64 only (got $os $arch)" >&2
  exit 2
fi
ASSET="ITKPythonBuilds-macosx-arm64.tar.zst"

TAG_DIR="$CACHE_ROOT/$ITK_PACKAGE_VERSION"
UNPACK_MARKER="$TAG_DIR/ITKPythonPackage/ITK-source"
ITK_DIR="$TAG_DIR/ITKPythonPackage/ITK-3.11-macosx_arm64"

mkdir -p "$TAG_DIR"

# --- resolve the tarball: local override -> cache -> download -------------
if [ -n "${ITKPYTHONBUILDS_TARBALL:-}" ]; then
  TARBALL="$ITKPYTHONBUILDS_TARBALL"
  echo "Using local override tarball: $TARBALL" >&2
else
  TARBALL="$TAG_DIR/$ASSET"
  if [ ! -f "$TARBALL" ]; then
    URL="https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/$ITK_PACKAGE_VERSION/$ASSET"
    echo "Downloading $URL" >&2
    curl -L --fail -o "$TARBALL.partial" "$URL"
    mv "$TARBALL.partial" "$TARBALL"
  else
    echo "Using cached tarball: $TARBALL" >&2
  fi
fi

# --- unpack (idempotent; REQUIRES --long=31 for the 2GB window) -----------
if [ ! -e "$UNPACK_MARKER" ]; then
  echo "Unpacking into $TAG_DIR ..." >&2
  zstd -dc --long=31 "$TARBALL" | tar -xf - -C "$TAG_DIR"
else
  echo "Already unpacked at $TAG_DIR" >&2
fi

# --- verify + emit ITK_DIR ------------------------------------------------
if [ ! -f "$ITK_DIR/ITKConfig.cmake" ]; then
  echo "ERROR: ITKConfig.cmake not found at $ITK_DIR" >&2
  echo "Available build trees:" >&2
  ls -d "$TAG_DIR"/ITKPythonPackage/ITK-*-macosx_arm64 2>/dev/null >&2 || true
  exit 1
fi

# Last stdout line = the resolved ITK_DIR (consumed by callers/tests).
echo "$ITK_DIR"
