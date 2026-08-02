#include "StaticFrameworkWithCxxDependency.h"

namespace dylib_forge_acceptance {
int measured_value();
}

extern "C" int validate(void) {
    return dylib_forge_acceptance::measured_value();
}
