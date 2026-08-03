import Foundation

public extension Array where Element: Sendable {
    /// Performs operations concurrently, limiting active operations to available processor cores.
    func concurrentForEach(
        _ operation: @escaping @Sendable (Element) async throws -> Void,
    ) async throws {
        guard !isEmpty else { return }

        let maximumConcurrentTasks = Swift.max(1, ProcessInfo.processInfo.activeProcessorCount)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = makeIterator()

            func addNextTask() {
                guard let element = iterator.next() else { return }
                group.addTask {
                    try await operation(element)
                }
            }

            for _ in 0 ..< Swift.min(maximumConcurrentTasks, count) {
                addNextTask()
            }

            while try await group.next() != nil {
                addNextTask()
            }
        }
    }
}
