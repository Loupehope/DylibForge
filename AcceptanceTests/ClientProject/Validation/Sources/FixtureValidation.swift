import Foundation
import StaticFrameworkWithCxxDependency
import StaticFrameworkWithDuplicateSymbols
import StaticFrameworkWithExcludedObject
import StaticFrameworkWithObjC
import StaticFrameworkWithObjCAndSwift
import StaticFrameworkWithPrivateObjC
import StaticFrameworkWithSwift
import StaticFrameworkWithSwiftDependency
import StaticFrameworkWithSwiftDependentFramework

final class FixtureValidation {
    func validate() throws {
        for fixture in fixtureResults where fixture.value != expectedFixtureValue {
            throw FixtureValidationError(
                fixture: fixture.name,
                actual: fixture.value,
                expected: expectedFixtureValue,
            )
        }
    }
}

private extension FixtureValidation {
    var expectedFixtureValue: Int {
        42
    }

    var fixtureResults: [(name: String, value: Int)] {
        [
            ("StaticFrameworkWithPrivateObjC", Int(StaticFrameworkWithPrivateObjC.validate())),
            ("StaticFrameworkWithCxxDependency", Int(StaticFrameworkWithCxxDependency.validate())),
            ("StaticFrameworkWithDuplicateSymbols", Int(StaticFrameworkWithDuplicateSymbols.validate())),
            ("StaticFrameworkWithExcludedObject", Int(StaticFrameworkWithExcludedObject.validate())),
            ("StaticFrameworkWithSwift", StaticFrameworkWithSwift.validate()),
            ("StaticFrameworkWithSwiftDependency", StaticFrameworkWithSwiftDependency.validate()),
            ("StaticFrameworkWithSwiftDependentFramework", StaticFrameworkWithSwiftDependentFramework.validate()),
            ("StaticFrameworkWithObjC", Int(StaticFrameworkWithObjC.validate())),
            ("StaticFrameworkWithObjCAndSwift", StaticFrameworkWithObjCAndSwift.validate()),
        ]
    }

    struct FixtureValidationError: LocalizedError {
        let fixture: String
        let actual: Int
        let expected: Int

        var errorDescription: String? {
            "\(fixture) returned \(actual), expected \(expected)"
        }
    }
}
