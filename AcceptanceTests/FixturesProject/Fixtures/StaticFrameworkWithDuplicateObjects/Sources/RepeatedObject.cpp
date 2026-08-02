namespace dylib_forge_acceptance {
extern int duplicate_object_initialization_count;

class DuplicateObjectRegistration {
  public:
    DuplicateObjectRegistration() { ++duplicate_object_initialization_count; }
};

DuplicateObjectRegistration duplicate_object_registration;

int repeated_object_measurement() { return 41; }
} // namespace dylib_forge_acceptance
