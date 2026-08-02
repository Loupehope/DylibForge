@_silgen_name("validateStaticFrameworkWithDuplicateObjects")
private func duplicateObjectsValidationValue() -> Int32

/// Validates a fixture whose byte-identical native object file is deduplicated before linking.
public final class DuplicateObjectsValidator {
    public init() {}

    public func validate() -> Int {
        Int(duplicateObjectsValidationValue())
    }
}
