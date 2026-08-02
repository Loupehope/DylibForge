#include "StaticFrameworkWithDuplicateSymbols.h"

namespace dylib_forge_acceptance {
int repeated_measurement();

int bridged_measurement() { return repeated_measurement(); }
} // namespace dylib_forge_acceptance

extern "C" int validate(void) {
    return dylib_forge_acceptance::bridged_measurement();
}
