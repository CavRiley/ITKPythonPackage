#!/usr/bin/env bash
# Smoke test for fetch-itk.sh. Uses a local-override tarball so it runs offline.
# Usage: ITKPYTHONBUILDS_TARBALL=/path/to/local.tar.zst bash cibuildwheel/test-fetch-itk.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ITKPYTHONBUILDS_TARBALL:?set ITKPYTHONBUILDS_TARBALL to a local ITKPythonBuilds .tar.zst}"

# Isolated cache so the test never collides with a real cache.
TEST_CACHE="$(mktemp -d)"
trap 'rm -rf "$TEST_CACHE"' EXIT

export ITK_PACKAGE_VERSION="test-local"
export ITKPYTHONBUILDS_CACHE="$TEST_CACHE"
# ITKPYTHONBUILDS_TARBALL inherited from caller.

# Run the helper; capture the ITK_DIR it prints on its last stdout line.
ITK_DIR_RESOLVED="$(bash "$SCRIPT_DIR/fetch-itk.sh" | tail -n1)"

echo "Resolved ITK_DIR: $ITK_DIR_RESOLVED"
test -f "$ITK_DIR_RESOLVED/ITKConfig.cmake" ||
  {
    echo "FAIL: ITKConfig.cmake not found under resolved ITK_DIR"
    exit 1
  }

echo "PASS: fetch-itk.sh unpacked ITK and located ITKConfig.cmake"
