#include "StaticFrameworkWithExcludedObject.h"

// A dead object with a missing definition, intentionally excluded during
// relinking.
extern "C" void missing_runtime_hook(void);

extern "C" __attribute__((used)) void invoke_missing_runtime_hook() {
    missing_runtime_hook();
}
