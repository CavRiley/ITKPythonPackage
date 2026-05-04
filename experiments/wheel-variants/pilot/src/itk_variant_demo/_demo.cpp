#include <pybind11/pybind11.h>

namespace py = pybind11;

PYBIND11_MODULE(_demo, m) {
  m.doc() = "itk_variant_demo: trivial module exposing the variant build flag";
#if ITK_VARIANT_DEMO_TBB
  constexpr bool kTbbEnabled = true;
#else
  constexpr bool kTbbEnabled = false;
#endif
  m.def("tbb_enabled", []() { return kTbbEnabled; },
        "Returns true if this wheel was built with the TBB variant flag set.");
}
