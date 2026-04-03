@echo off
setlocal enabledelayedexpansion

:: Build ITK C++ with Python wrapping for use as a conda package (Windows).

set BUILD_DIR=%SRC_DIR%\..\build
mkdir %BUILD_DIR%
cd %BUILD_DIR%

cmake ^
  -G "Ninja" ^
  %CMAKE_ARGS% ^
  -D BUILD_SHARED_LIBS:BOOL=ON ^
  -D BUILD_TESTING:BOOL=OFF ^
  -D BUILD_EXAMPLES:BOOL=OFF ^
  -D CMAKE_BUILD_TYPE:STRING=Release ^
  -D "CMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX%" ^
  ^
  -D ITK_WRAP_PYTHON:BOOL=ON ^
  -D ITK_WRAP_DOC:BOOL=ON ^
  -D ITK_LEGACY_SILENT:BOOL=ON ^
  -D CMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON ^
  ^
  -D ITK_WRAP_unsigned_short:BOOL=ON ^
  -D ITK_WRAP_double:BOOL=ON ^
  -D ITK_WRAP_complex_double:BOOL=ON ^
  -D "ITK_WRAP_IMAGE_DIMS:STRING=2;3;4" ^
  ^
  -D WRAP_ITK_INSTALL_COMPONENT_IDENTIFIER:STRING=PythonWheel ^
  -D WRAP_ITK_INSTALL_COMPONENT_PER_MODULE:BOOL=ON ^
  ^
  -D ITK_USE_SYSTEM_EXPAT:BOOL=ON ^
  -D ITK_USE_SYSTEM_HDF5:BOOL=ON ^
  -D ITK_USE_SYSTEM_JPEG:BOOL=ON ^
  -D ITK_USE_SYSTEM_PNG:BOOL=ON ^
  -D ITK_USE_SYSTEM_TIFF:BOOL=ON ^
  -D ITK_USE_SYSTEM_ZLIB:BOOL=ON ^
  -D ITK_USE_SYSTEM_FFTW:BOOL=ON ^
  -D ITK_USE_SYSTEM_EIGEN:BOOL=ON ^
  -D ITK_USE_FFTWD:BOOL=ON ^
  -D ITK_USE_FFTWF:BOOL=ON ^
  ^
  -D ITK_BUILD_DEFAULT_MODULES:BOOL=ON ^
  -D Module_ITKReview:BOOL=ON ^
  -D Module_ITKTBB:BOOL=ON ^
  -D Module_MGHIO:BOOL=ON ^
  -D Module_ITKIOTransformMINC:BOOL=ON ^
  -D Module_GenericLabelInterpolator:BOOL=ON ^
  -D Module_AdaptiveDenoising:BOOL=ON ^
  ^
  -D ITK_USE_KWSTYLE:BOOL=OFF ^
  -D "ITK_DEFAULT_THREADER:STRING=Pool" ^
  ^
  "%SRC_DIR%"

if errorlevel 1 exit /b 1

cmake --build . --config Release
if errorlevel 1 exit /b 1

cmake --install . --config Release
if errorlevel 1 exit /b 1
