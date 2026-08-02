@_silgen_name("validateStaticFrameworkWithExcludedObject")
private func excludedObjectValidationValue() -> Int32

public final class ExcludedObjectValidator {
    public init() {}

    public func validate() -> Int {
        Int(excludedObjectValidationValue())
    }
}
