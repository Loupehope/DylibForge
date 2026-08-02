import XCTest

/// Exercises every relinked fixture on each client test destination.
final class FixtureValidationTests: XCTestCase {
    /// Confirms that every fixture exposes the common expected validation value.
    func testFixtures() throws {
        try FixtureValidation().validate()
    }
}
