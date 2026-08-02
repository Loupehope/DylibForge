#include "StaticFrameworkWithDuplicateObjects.h"

namespace dylib_forge_acceptance {
int duplicate_object_initialization_count = 0;
int repeated_object_measurement();

class DuplicateObjectsValidator {
  public:
    int validate() const {
        return repeated_object_measurement() +
               duplicate_object_initialization_count;
    }
};
} // namespace dylib_forge_acceptance

extern "C" int validateStaticFrameworkWithDuplicateObjects(void) {
    return dylib_forge_acceptance::DuplicateObjectsValidator().validate();
}
