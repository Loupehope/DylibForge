import Testing

/// Exercises every relinked fixture on each client test destination.
@Test
func `Every relinked fixture returns its expected value`() throws {
    try FixtureValidation().validate()
}
