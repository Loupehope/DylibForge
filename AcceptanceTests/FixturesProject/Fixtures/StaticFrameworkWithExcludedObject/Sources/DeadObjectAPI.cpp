#include "StaticFrameworkWithExcludedObject.h"

#include <dlfcn.h>

namespace dylib_forge_acceptance {
class ExcludedObjectValidator {
  public:
    int validate() const {
        using MissingRuntimeHook = void (*)(void);
        const auto hook = reinterpret_cast<MissingRuntimeHook>(
            dlsym(RTLD_DEFAULT, "invoke_missing_runtime_hook"));
        if (hook != nullptr) {
            hook();
        }
        return 42;
    }
};
} // namespace dylib_forge_acceptance

extern "C" int validateStaticFrameworkWithExcludedObject(void) {
    return dylib_forge_acceptance::ExcludedObjectValidator().validate();
}
