#include "StaticFrameworkWithExcludedObject.h"

namespace acceptance_ghost {
class MissingRuntimeHook {
  public:
    virtual void attach();
};
} // namespace acceptance_ghost

// A dead object with a missing definition, intentionally excluded during
// relinking.
extern "C" __attribute__((used)) void invoke_missing_runtime_hook() {
    auto *hook = static_cast<acceptance_ghost::MissingRuntimeHook *>(nullptr);
    hook->acceptance_ghost::MissingRuntimeHook::attach();
}
