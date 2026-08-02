#include "StaticFrameworkWithDuplicateSymbols.h"

namespace dylib_forge_acceptance {
int repeated_measurement();
int repeated_measurement_a();
int repeated_measurement_b();

class DuplicateSymbolsValidator {
  public:
    int validate() const {
        return repeated_measurement() + repeated_measurement_a() +
               repeated_measurement_b();
    }
};
} // namespace dylib_forge_acceptance

extern "C" int validateStaticFrameworkWithDuplicateSymbols(void) {
    return dylib_forge_acceptance::DuplicateSymbolsValidator().validate();
}
