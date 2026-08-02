@main
final class AcceptanceClient {
    static func main() throws {
        try FixtureValidation().validate()
        print("DylibForge acceptance passed")
    }
}
