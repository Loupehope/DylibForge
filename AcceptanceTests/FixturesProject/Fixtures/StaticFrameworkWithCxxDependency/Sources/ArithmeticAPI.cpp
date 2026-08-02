#include "StaticFrameworkWithCxxDependency.h"

namespace dylib_forge_acceptance {
int measured_value();

class CxxDependencyValidator {
  public:
    int validate() const { return measured_value(); }
};
} // namespace dylib_forge_acceptance

extern "C" int validateStaticFrameworkWithCxxDependency(void) {
    return dylib_forge_acceptance::CxxDependencyValidator().validate();
}
