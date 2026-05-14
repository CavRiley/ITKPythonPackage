# Conda-supplied ITK stub: bridge conda-forge's lowercase hdf5:: namespace
# to the uppercase HDF5::HDF5 target ITKConfig.cmake expects.
#
# Installed onto CMAKE_MODULE_PATH by ITKPythonPackage when a conda-supplied
# ITK is in use and the conda env did not ship its own stub-find-modules
# directory.  See `scripts/conda_itk_stubs.py:install_stubs`.

if(NOT TARGET HDF5::HDF5)
  if(TARGET hdf5::hdf5-shared)
    add_library(HDF5::HDF5 INTERFACE IMPORTED)
    target_link_libraries(HDF5::HDF5 INTERFACE hdf5::hdf5-shared)
  elseif(TARGET hdf5::hdf5)
    add_library(HDF5::HDF5 INTERFACE IMPORTED)
    target_link_libraries(HDF5::HDF5 INTERFACE hdf5::hdf5)
  endif()
endif()
set(HDF5_FOUND TRUE)
