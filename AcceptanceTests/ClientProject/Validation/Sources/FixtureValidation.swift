import Foundation
import StaticFrameworkWithCxxDependency
import StaticFrameworkWithDuplicateObjects
import StaticFrameworkWithDuplicateSymbols
import StaticFrameworkWithExcludedObject
import StaticFrameworkWithObjC
import StaticFrameworkWithObjCAndSwift
import StaticFrameworkWithPrivateObjC
import StaticFrameworkWithSwift
import StaticFrameworkWithSwiftDependency
import StaticFrameworkWithSwiftDependentFramework
import StaticLibraryWithSwift

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
            (
                "StaticFrameworkWithPrivateObjC",
                Int(PrivateObjCImplementation().validate()),
            ),
            (
                "StaticFrameworkWithCxxDependency",
                CxxDependencyValidator().validate(),
            ),
            (
                "StaticFrameworkWithDuplicateSymbols",
                DuplicateSymbolsValidator().validate(),
            ),
            (
                "StaticFrameworkWithDuplicateObjects",
                DuplicateObjectsValidator().validate(),
            ),
            (
                "StaticFrameworkWithExcludedObject",
                ExcludedObjectValidator().validate(),
            ),
            (
                "StaticFrameworkWithSwift",
                SwiftValidator().validate(),
            ),
            (
                "StaticLibraryWithSwift",
                SwiftStaticLibraryValidator().validate(),
            ),
            (
                "StaticFrameworkWithSwiftDependency",
                SwiftDependencyValidator().validate(),
            ),
            (
                "StaticFrameworkWithSwiftDependentFramework",
                SwiftDependentFrameworkValidator().validate(),
            ),
            (
                "StaticFrameworkWithObjC",
                Int(ObjectiveCOnlyValidator().validate()),
            ),
            (
                "StaticFrameworkWithObjCAndSwift",
                MixedLanguageValidator().validate(),
            ),
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
