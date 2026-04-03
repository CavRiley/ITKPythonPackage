# conda-forge Submission

This directory contains recipe files for submitting ITK packages to conda-forge
via [staged-recipes](https://github.com/conda-forge/staged-recipes).

## Packages

### libitk-wrapping

A conda package containing ITK C++ libraries with full Python wrapping
artifacts (SWIG interfaces, CastXML outputs, compiled Python modules).
This package enables building ITK Python wheels and remote module wheels
without recompiling ITK from source.

### Submission Process

1. Fork [conda-forge/staged-recipes](https://github.com/conda-forge/staged-recipes)
2. Copy `libitk-wrapping/` into `recipes/libitk-wrapping/`
3. Open a PR against staged-recipes
4. Address conda-forge review feedback
5. Once merged, a feedstock will be created automatically

### Updating the existing libitk feedstock

The existing [libitk-feedstock](https://github.com/conda-forge/libitk-feedstock)
(currently at v5.4.5) should be updated to ITK 6 separately. The `libitk-wrapping`
package will depend on `libitk-devel` once both are at ITK 6.

## Environment Variables for Custom Builds

When building from a non-default ITK branch (e.g., for PR testing):

```bash
export ITK_GIT_URL="https://github.com/BRAINSia/ITK.git"
export ITK_GIT_TAG="itk-conda-pythonpackage-support"
```
