import StaticFrameworkWithSwiftDependency

public final class SwiftDependentFrameworkValidator {
    public init() {}

    public func validate() -> Int {
        SwiftDependencyValidator().validate()
    }
}
